import 'package:excel/excel.dart' as xls;

import '../core/supabase/supabase_client.dart';
import '../models/daily_test.dart';
import '../models/faculty.dart';
import '../models/question.dart';
import '../models/student.dart';
import '../models/test_category.dart';

/// Outcome of [AdminService.bulkImportQuestions] — always returned even
/// when some rows were bad, so the admin sees exactly what happened
/// instead of a single opaque success/failure.
class BulkImportResult {
  final int imported;
  final List<String> skipped;
  const BulkImportResult({required this.imported, required this.skipped});
}

class AdminService {
  final _client = SupabaseService.client;

  // ---------------------------------------------------------------- Questions
  Future<List<Question>> fetchQuestions({String? subject, QuestionDifficulty? difficulty, String? search}) async {
    var query = _client.from('questions').select();
    if (subject != null && subject.isNotEmpty) query = query.eq('subject', subject);
    if (difficulty != null) query = query.eq('difficulty', difficulty.name);
    if (search != null && search.isNotEmpty) query = query.ilike('question_text', '%$search%');
    final rows = await query.order('created_at', ascending: false).limit(200);
    return (rows as List).map((r) => Question.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<String>> fetchSubjects() async {
    final rows = await _client.from('questions').select('subject');
    final set = <String>{};
    for (final r in rows as List) {
      set.add((r as Map<String, dynamic>)['subject'] as String);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> createQuestion(Question q) async {
    await _client.from('questions').insert(q.toInsertJson());
  }

  Future<void> updateQuestion(String id, Question q) async {
    await _client.from('questions').update(q.toInsertJson()).eq('id', id);
  }

  Future<void> deleteQuestion(String id) async {
    await _client.from('questions').delete().eq('id', id);
  }

  Future<void> setQuestionActive(String id, bool active) async {
    await _client.from('questions').update({'is_active': active}).eq('id', id);
  }

  /// Bulk import from a parsed Excel/CSV sheet. Expected column order:
  /// Subject, Topic, Question, Option A, Option B, Option C, Option D,
  /// Correct (A/B/C/D), Difficulty (easy/medium/hard) — header row skipped.
  ///
  /// [category] is NOT a column in the file — every question in the
  /// import is stamped with the *signed-in admin's own* category (an
  /// Aptitude admin's import always lands as 'aptitude' questions, etc),
  /// matching the `questions_write_admin` RLS policy that would reject
  /// the insert otherwise (see policies.sql). "Subject"/"Topic" stay the
  /// free-text sub-topic columns they always were, one level below
  /// category.
  ///
  /// Validates every row *before* sending anything to Supabase. This
  /// matters because `questions.correct_option` has a `check (... in
  /// ('A','B','C','D'))` constraint (see supabase/schema.sql) and the
  /// whole batch is sent as a single `insert(payload)` call — previously,
  /// one row with a missing/blank/invalid answer column (or simply fewer
  /// columns than expected, e.g. a trailing blank cell Excel/CSV
  /// sometimes drops) would throw and abort the *entire* import, with
  /// every other otherwise-valid row silently not imported either. Now
  /// bad rows are skipped individually (with a reason reported back to
  /// the admin) and everything else still imports.
  Future<BulkImportResult> bulkImportQuestions(List<List<dynamic>> rows, TestCategory category) async {
    final payload = <Map<String, dynamic>>[];
    final skipped = <String>[];

    String cell(List<dynamic> row, int idx) => (idx < row.length && row[idx] != null) ? '${row[idx]}'.trim() : '';

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 1; // 1-based, matching what a spreadsheet shows (row 1 = header)
      if (row.isEmpty || cell(row, 0).isEmpty) continue; // fully blank row — not worth reporting

      final subject = cell(row, 0);
      final topic = cell(row, 1);
      final questionText = cell(row, 2);
      final a = cell(row, 3);
      final b = cell(row, 4);
      final c = cell(row, 5);
      final d = cell(row, 6);
      final correct = cell(row, 7).toUpperCase();
      final difficultyRaw = cell(row, 8).toLowerCase();

      if (questionText.isEmpty || a.isEmpty || b.isEmpty || c.isEmpty || d.isEmpty) {
        // Report which specific column(s) were empty and what this row's
        // first few cells actually contain — a single "missing" message
        // with no detail was indistinguishable from "your columns are
        // shifted" vs. "this one row is genuinely incomplete". Seeing the
        // raw cells makes a systematic misalignment (e.g. an extra leading
        // column, or a missing Topic column) obvious immediately instead
        // of requiring a re-upload with guesses.
        final empties = [
          if (questionText.isEmpty) 'Question',
          if (a.isEmpty) 'Option A',
          if (b.isEmpty) 'Option B',
          if (c.isEmpty) 'Option C',
          if (d.isEmpty) 'Option D',
        ].join(', ');
        final preview = row.map((c) => c == null || '$c'.trim().isEmpty ? '(blank)' : '$c').join(' | ');
        skipped.add(
          'Row $rowNum: missing $empties — skipped. This row\'s ${row.length} column(s) as read: $preview',
        );
        continue;
      }
      if (!const ['A', 'B', 'C', 'D'].contains(correct)) {
        final shown = correct.isEmpty ? '(blank)' : correct;
        skipped.add('Row $rowNum: correct answer must be A, B, C or D — got "$shown" — skipped.');
        continue;
      }

      payload.add({
        'category': category.value,
        'subject': subject,
        'topic': topic.isEmpty ? null : topic,
        'question_text': questionText,
        'option_a': a,
        'option_b': b,
        'option_c': c,
        'option_d': d,
        'correct_option': correct,
        'difficulty': const ['easy', 'medium', 'hard'].contains(difficultyRaw) ? difficultyRaw : 'medium',
      });
    }

    if (payload.isNotEmpty) {
      await _client.from('questions').insert(payload);
    }
    return BulkImportResult(imported: payload.length, skipped: skipped);
  }

  Future<List<List<dynamic>>> parseExcelBytes(List<int> bytes) async {
    final workbook = xls.Excel.decodeBytes(bytes);
    final sheet = workbook.tables[workbook.tables.keys.first]!;
    return sheet.rows.map((row) => row.map((c) => c?.value).toList()).toList();
  }

  // ------------------------------------------------------------- Departments
  // See DepartmentService for CRUD — reused by the People and Departments
  // screens.

  // ------------------------------------------------------------ Students
  Future<List<StudentProfile>> fetchStudents({String? departmentId, int? year}) async {
    var query = _client.from('students').select('*, profiles(full_name, email, is_active)');
    if (departmentId != null) query = query.eq('department_id', departmentId);
    if (year != null) query = query.eq('year', year);
    final rows = await query.order('register_number');
    return (rows as List).map((r) => StudentProfile.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> setStudentActive(String studentId, bool active) async {
    await _client.from('profiles').update({'is_active': active}).eq('id', studentId);
  }

  Future<Map<String, dynamic>> createStudent({
    required String fullName,
    required String email,
    required String password,
    required String registerNumber,
    required String departmentId,
    required int year,
    String? section,
  }) async {
    final res = await _client.functions.invoke('create-user', body: {
      'role': 'student',
      'full_name': fullName,
      'email': email,
      'password': password,
      'register_number': registerNumber,
      'department_id': departmentId,
      'year': year,
      'section': section,
    });
    return res.data as Map<String, dynamic>;
  }

  /// Bulk student import across any department. Expected columns: Full
  /// Name, Email, Register Number, Department Code, Year, Section, Temp
  /// Password. Used by the admin People screen (which can import into
  /// several departments in one file).
  ///
  /// Same defensive column access as bulkImportQuestions: a row shorter
  /// than expected (e.g. missing trailing columns) used to throw a
  /// RangeError *outside* the per-row try/catch below, which would abort
  /// the whole import instead of just skipping that one row. Also
  /// returns *why* each row was skipped instead of a bare count — a
  /// silent int made it impossible to tell "12 imported" from "12
  /// imported, 40 silently failed because of a typo'd department code".
  Future<BulkImportResult> bulkImportStudents(List<List<dynamic>> rows, Map<String, String> deptCodeToId) async {
    String cell(List<dynamic> row, int idx) => (idx < row.length && row[idx] != null) ? '${row[idx]}'.trim() : '';
    final skipped = <String>[];
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 1;
      if (row.isEmpty || cell(row, 0).isEmpty) continue;

      final fullName = cell(row, 0);
      final email = cell(row, 1);
      final registerNumber = cell(row, 2);
      final deptCode = cell(row, 3).toUpperCase();
      final deptId = deptCodeToId[deptCode];

      if (email.isEmpty || registerNumber.isEmpty) {
        skipped.add('Row $rowNum: missing email or register number — skipped.');
        continue;
      }
      if (deptId == null) {
        skipped.add('Row $rowNum: department code "$deptCode" not recognized — skipped.');
        continue;
      }
      try {
        await createStudent(
          fullName: fullName,
          email: email,
          registerNumber: registerNumber,
          departmentId: deptId,
          year: int.tryParse(cell(row, 4)) ?? 1,
          section: cell(row, 5).isEmpty ? null : cell(row, 5),
          password: cell(row, 6).isEmpty ? 'Welcome@123' : cell(row, 6),
        );
        count++;
      } catch (e) {
        skipped.add('Row $rowNum: $e — skipped.');
      }
    }
    return BulkImportResult(imported: count, skipped: skipped);
  }

  /// Bulk student import into a single, fixed department — used by the
  /// faculty "Import students" screen, where the department isn't a
  /// column in the file at all (it's always the faculty member's own
  /// department; the create-user Edge Function enforces this server-side
  /// too, so this client-side restriction is a UX convenience, not the
  /// real security boundary). Expected columns: Full Name, Email,
  /// Register Number, Year, Section, Temp Password.
  Future<BulkImportResult> bulkImportStudentsToDepartment(List<List<dynamic>> rows, String departmentId) async {
    String cell(List<dynamic> row, int idx) => (idx < row.length && row[idx] != null) ? '${row[idx]}'.trim() : '';
    final skipped = <String>[];
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 1;
      if (row.isEmpty || cell(row, 0).isEmpty) continue;

      final fullName = cell(row, 0);
      final email = cell(row, 1);
      final registerNumber = cell(row, 2);
      if (email.isEmpty || registerNumber.isEmpty) {
        skipped.add('Row $rowNum: missing email or register number — skipped.');
        continue;
      }
      try {
        await createStudent(
          fullName: fullName,
          email: email,
          registerNumber: registerNumber,
          departmentId: departmentId,
          year: int.tryParse(cell(row, 3)) ?? 1,
          section: cell(row, 4).isEmpty ? null : cell(row, 4),
          password: cell(row, 5).isEmpty ? 'Welcome@123' : cell(row, 5),
        );
        count++;
      } catch (e) {
        skipped.add('Row $rowNum: $e — skipped.');
      }
    }
    return BulkImportResult(imported: count, skipped: skipped);
  }

  // ------------------------------------------------------------- Faculty
  Future<List<FacultyProfile>> fetchFaculty({String? departmentId}) async {
    var query = _client.from('faculty').select('*, profiles(full_name, email, is_active)');
    if (departmentId != null) query = query.eq('department_id', departmentId);
    final rows = await query.order('faculty_id');
    return (rows as List).map((r) => FacultyProfile.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> createFaculty({
    required String fullName,
    required String email,
    required String password,
    required String facultyId,
    String? departmentId,
    List<int>? assignedYears,
  }) async {
    final res = await _client.functions.invoke('create-user', body: {
      'role': 'faculty',
      'full_name': fullName,
      'email': email,
      'password': password,
      'faculty_id': facultyId,
      'department_id': departmentId,
      'assigned_years': assignedYears ?? [1, 2, 3, 4],
    });
    return res.data as Map<String, dynamic>;
  }

  Future<void> setFacultyActive(String facultyId, bool active) async {
    await _client.from('profiles').update({'is_active': active}).eq('id', facultyId);
  }

  Future<void> assignFacultyDepartment(String facultyId, String departmentId, List<int> years) async {
    await _client.from('faculty').update({'department_id': departmentId, 'assigned_years': years}).eq('id', facultyId);
  }

  /// Bulk faculty import — admin only (the create-user Edge Function
  /// rejects a faculty-role body from a non-admin caller). Expected
  /// columns: Full Name, Email, Faculty ID, Department Code, Assigned
  /// Years (e.g. "1,2,3,4" — blank means all four), Temp Password.
  Future<BulkImportResult> bulkImportFaculty(List<List<dynamic>> rows, Map<String, String> deptCodeToId) async {
    String cell(List<dynamic> row, int idx) => (idx < row.length && row[idx] != null) ? '${row[idx]}'.trim() : '';
    final skipped = <String>[];
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 1;
      if (row.isEmpty || cell(row, 0).isEmpty) continue;

      final fullName = cell(row, 0);
      final email = cell(row, 1);
      final facultyId = cell(row, 2);
      final deptCode = cell(row, 3).toUpperCase();
      final deptId = deptCodeToId[deptCode];

      if (email.isEmpty || facultyId.isEmpty) {
        skipped.add('Row $rowNum: missing email or faculty ID — skipped.');
        continue;
      }
      if (deptCode.isNotEmpty && deptId == null) {
        skipped.add('Row $rowNum: department code "$deptCode" not recognized — skipped.');
        continue;
      }
      final years = cell(row, 4).isEmpty
          ? [1, 2, 3, 4]
          : cell(row, 4).split(RegExp(r'[,/]')).map((s) => int.tryParse(s.trim())).whereType<int>().toList();
      try {
        await createFaculty(
          fullName: fullName,
          email: email,
          facultyId: facultyId,
          departmentId: deptId,
          assignedYears: years.isEmpty ? [1, 2, 3, 4] : years,
          password: cell(row, 5).isEmpty ? 'Welcome@123' : cell(row, 5),
        );
        count++;
      } catch (e) {
        skipped.add('Row $rowNum: $e — skipped.');
      }
    }
    return BulkImportResult(imported: count, skipped: skipped);
  }

  // ---------------------------------------------------------- Daily tests
  /// [category] scopes the list to one admin's own track — `daily_tests`
  /// select RLS is deliberately open to every signed-in user (students/
  /// faculty need all 3 categories), so this filter has to happen here
  /// rather than via RLS. Pass null to fetch across all categories
  /// (not used by the admin app today, but kept for flexibility).
  Future<List<DailyTest>> fetchRecentTests({TestCategory? category, int limit = 30}) async {
    var query = _client.from('daily_tests').select();
    if (category != null) query = query.eq('category', category.value);
    final rows = await query.order('test_date', ascending: false).limit(limit);
    return (rows as List).map((r) => DailyTest.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<DailyTest> generateDailyTest({
    required DateTime testDate,
    required TestCategory category,
    int questionCount = 20,
    int durationMinutes = 30,
    DateTime? openTime,
    DateTime? closeTime,
    DateTime? resultsTime,
    String selectionMode = 'auto',
    List<String>? questionIds,
  }) async {
    final dateStr = '${testDate.year.toString().padLeft(4, '0')}-${testDate.month.toString().padLeft(2, '0')}-${testDate.day.toString().padLeft(2, '0')}';
    final row = await _client.rpc('generate_daily_test', params: {
      'p_test_date': dateStr,
      'p_category': category.value,
      'p_question_count': questionCount,
      'p_duration_minutes': durationMinutes,
      // .toUtc() before serializing matters: DateTime.toIso8601String() on
      // a *local* DateTime omits the timezone offset entirely (a known
      // Dart gotcha — no 'Z', no '+05:30', nothing), so Postgres/PostgREST
      // interprets the naive string using the DB session's timezone
      // (UTC on Supabase), not the admin's device timezone. Without this,
      // an admin in India picking "10 AM" here actually opened the test
      // at 10:00 UTC = 3:30 PM IST — 5.5 hours later than intended, and
      // the exact reason a student saw "Not open yet" all morning.
      if (openTime != null) 'p_open_time': openTime.toUtc().toIso8601String(),
      if (closeTime != null) 'p_close_time': closeTime.toUtc().toIso8601String(),
      if (resultsTime != null) 'p_results_time': resultsTime.toUtc().toIso8601String(),
      'p_selection_mode': selectionMode,
      if (questionIds != null) 'p_question_ids': questionIds,
    });
    return DailyTest.fromJson(row as Map<String, dynamic>);
  }

  /// Edits a test that hasn't opened yet (server rejects anything past
  /// 'scheduled' — see update_daily_test in supabase/functions.sql for
  /// why: an already-open/closed/published test may have real student
  /// attempts tied to it, so its question set/timing can't safely change
  /// under them). Every parameter is optional; only pass what the admin
  /// actually changed on the edit sheet.
  Future<DailyTest> updateDailyTest({
    required String testId,
    DateTime? testDate,
    int? questionCount,
    int? durationMinutes,
    DateTime? openTime,
    DateTime? closeTime,
    DateTime? resultsTime,
    String? selectionMode,
    List<String>? questionIds,
  }) async {
    String dateStr(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final row = await _client.rpc('update_daily_test', params: {
      'p_test_id': testId,
      if (testDate != null) 'p_test_date': dateStr(testDate),
      if (questionCount != null) 'p_question_count': questionCount,
      if (durationMinutes != null) 'p_duration_minutes': durationMinutes,
      // Same .toUtc() reasoning as generateDailyTest above.
      if (openTime != null) 'p_open_time': openTime.toUtc().toIso8601String(),
      if (closeTime != null) 'p_close_time': closeTime.toUtc().toIso8601String(),
      if (resultsTime != null) 'p_results_time': resultsTime.toUtc().toIso8601String(),
      if (selectionMode != null) 'p_selection_mode': selectionMode,
      if (questionIds != null) 'p_question_ids': questionIds,
    });
    return DailyTest.fromJson(row as Map<String, dynamic>);
  }

  /// Rotating-QR / auto-publish / geofence options for a test that hasn't
  /// opened yet (see set_test_options in supabase/upgrade_v2.sql).
  Future<DailyTest> setTestOptions({
    required String testId,
    bool? qrRotating,
    bool? autoPublish,
    double? geoLat,
    double? geoLng,
    int? geoRadiusM,
    bool clearGeofence = false,
  }) async {
    final row = await _client.rpc('set_test_options', params: {
      'p_test_id': testId,
      if (qrRotating != null) 'p_qr_rotating': qrRotating,
      if (autoPublish != null) 'p_auto_publish': autoPublish,
      if (geoLat != null) 'p_geo_lat': geoLat,
      if (geoLng != null) 'p_geo_lng': geoLng,
      if (geoRadiusM != null) 'p_geo_radius_m': geoRadiusM,
      'p_clear_geofence': clearGeofence,
    });
    return DailyTest.fromJson(row as Map<String, dynamic>);
  }

  /// Permanently deletes a test — including, deliberately, one that's
  /// already open/closed/published (updateDailyTest refuses those; this
  /// doesn't). Cascades to every attempt/answer/ranking tied to that day
  /// (see delete_daily_test in supabase/functions.sql). The UI must
  /// confirm with the admin before calling this — there's no undo.
  Future<void> deleteDailyTest(String testId) async {
    await _client.rpc('delete_daily_test', params: {'p_test_id': testId});
  }

  // -------------------------------------------------------------- Results
  Future<void> publishResults(String dailyTestId) async {
    await _client.rpc('publish_results', params: {'p_daily_test_id': dailyTestId});
  }

  // ------------------------------------------------------------ Analytics
  /// [departmentId] narrows the summary down to students in a single
  /// department. This needs `students!inner(department_id)` (not a plain
  /// left-embed) because PostgREST only lets you filter *on* an embedded
  /// resource's column when that embed is an inner join — with a left
  /// join the `.eq('students.department_id', ...)` filter is silently
  /// ignored and every attempt comes back regardless of department.
  Future<Map<String, dynamic>> fetchAnalyticsSummary(String dailyTestId, {String? departmentId}) async {
    var query = _client
        .from('test_attempts')
        .select(departmentId != null ? 'status, score, students!inner(department_id)' : 'status, score')
        .eq('daily_test_id', dailyTestId);
    if (departmentId != null) {
      query = query.eq('students.department_id', departmentId);
    }
    final attempts = await query;
    final list = attempts as List;
    final submitted = list.where((r) => (r as Map)['status'] == 'submitted').toList();
    final absent = list.where((r) => (r as Map)['status'] == 'absent').length;
    final avgScore = submitted.isEmpty
        ? 0.0
        : submitted.map((r) => ((r as Map)['score'] as int? ?? 0)).reduce((a, b) => a + b) / submitted.length;
    return {
      'totalAttempts': list.length,
      'submitted': submitted.length,
      'absent': absent,
      'avgScore': avgScore,
    };
  }
}
