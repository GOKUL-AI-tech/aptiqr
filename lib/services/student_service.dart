import 'dart:async' show unawaited;

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../core/device/device_identity.dart';
import '../core/location/location_service.dart';
import '../core/supabase/supabase_client.dart';
import '../core/utils/app_date.dart';
import '../local_db/app_database.dart';
import '../models/daily_test.dart';
import '../models/question.dart';
import '../models/ranking.dart';
import '../models/test_attempt.dart';
import '../models/test_category.dart';
import 'offline_sync_service.dart';

class StartAttemptException implements Exception {
  final String message;
  StartAttemptException(this.message);
  @override
  String toString() => message;
}

class StudentService {
  final _client = SupabaseService.client;
  final _db = AppDatabase.instance;
  final _uuid = const Uuid();
  final OfflineSyncService syncService;

  StudentService(this.syncService);

  /// Every one of today's tests — up to 3 (Aptitude/Technical/
  /// Communication), however many the admins have generated so far.
  /// Was `fetchTodayTest` returning a single row via `.maybeSingle()`,
  /// back when `test_date` alone was unique on `daily_tests`; now that a
  /// date can have one row per category (see supabase/schema.sql), this
  /// returns the whole list, sorted into a stable, predictable order for
  /// the Home screen's stack of test cards.
  Future<List<DailyTest>> fetchTodayTests() async {
    // AppDate.todayIst(), not DateTime.now() — see that class's doc
    // comment. A student's device computing a different calendar date
    // than the admin device that generated today's test (clock skew,
    // wrong device timezone) means this query silently returns nothing
    // instead of erroring, which looked exactly like "no test today"
    // even though one exists.
    final dateStr = AppDate.isoDate(AppDate.todayIst());
    final rows = await _client.from('daily_tests').select().eq('test_date', dateStr);
    final tests = (rows as List).map((r) => DailyTest.fromJson(r as Map<String, dynamic>)).toList();
    tests.sort((a, b) => a.category.index.compareTo(b.category.index));
    return tests;
  }

  /// A single test by id — used once the student has picked a specific
  /// category's card from Home and moved into that test's instructions/
  /// question/review/result screens (all keyed by testId already).
  Future<DailyTest?> fetchTestById(String dailyTestId) async {
    final row = await _client.from('daily_tests').select().eq('id', dailyTestId).maybeSingle();
    if (row == null) return null;
    return DailyTest.fromJson(row);
  }

  Future<TestAttempt?> fetchMyAttempt(String dailyTestId) async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('test_attempts')
        .select()
        .eq('daily_test_id', dailyTestId)
        .eq('student_id', uid)
        .maybeSingle();
    if (row == null) return null;
    return TestAttempt.fromJson(row);
  }

  /// Starts (or resumes) the attempt. The server now validates everything
  /// that matters — the rotating QR token, this phone's device binding,
  /// the geofence (if the test has one) and the test window — so this
  /// needs a connection. Throws [StartAttemptException] with a message
  /// that is safe to show the student.
  Future<void> startAttempt(DailyTest test, String qrToken) async {
    final existingLocal = await _db.localAttemptFor(test.id);
    if (existingLocal != null && existingLocal.attemptId != null) return; // already started on this device

    final deviceId = await DeviceIdentity.get();
    double? lat;
    double? lng;
    if (test.hasGeofence) {
      try {
        final pos = await LocationService.current();
        lat = pos.latitude;
        lng = pos.longitude;
      } on LocationException catch (e) {
        throw StartAttemptException(e.message);
      } catch (_) {
        throw StartAttemptException('Could not get your location. Move to an open area and try again.');
      }
    }

    String? serverAttemptId;
    try {
      final row = await _client.rpc('start_test_attempt', params: {
        'p_daily_test_id': test.id,
        'p_qr_token': qrToken.trim(),
        'p_device_id': deviceId,
        if (lat != null) 'p_lat': lat,
        if (lng != null) 'p_lng': lng,
      });
      serverAttemptId = (row as Map<String, dynamic>)['id'] as String?;
    } on PostgrestException catch (e) {
      throw StartAttemptException(e.message);
    } catch (_) {
      throw StartAttemptException('Could not reach the server. Starting a test needs an internet connection.');
    }

    // Cache the paper BEFORE recording the local attempt — if caching
    // fails the student can simply retry, instead of being stuck with a
    // local attempt row and no questions.
    try {
      await _cacheQuestions(test.id);
    } on PostgrestException catch (e) {
      throw StartAttemptException(e.message);
    } catch (_) {
      throw StartAttemptException('Could not download the questions. Check your connection and try again.');
    }

    await _db.upsertLocalAttempt(LocalAttemptsCompanion.insert(
      dailyTestId: test.id,
      attemptId: Value(serverAttemptId),
      status: const Value('in_progress'),
      startedAt: DateTime.now(),
    ));
  }

  /// When this device's attempt began — used to resume the countdown
  /// correctly after the screen is re-created instead of restarting it.
  Future<DateTime?> attemptStartedAt(String dailyTestId) async {
    final local = await _db.localAttemptFor(dailyTestId);
    return local?.startedAt;
  }

  /// Best-effort integrity telemetry (app backgrounded etc.) for faculty.
  Future<void> logIntegrityEvent(String dailyTestId, String type, {String? detail}) async {
    final local = await _db.localAttemptFor(dailyTestId);
    final attemptId = local?.attemptId;
    if (attemptId == null) return;
    try {
      await _client.rpc('log_integrity_event', params: {
        'p_attempt_id': attemptId,
        'p_event_type': type,
        if (detail != null) 'p_detail': detail,
      });
    } catch (_) {}
  }

  /// Uses the `fetch_test_questions` RPC rather than a plain client-side
  /// select — `questions` has no student RLS policy at all (see
  /// policies.sql: students must never browse the bank directly), so a
  /// client-side `daily_test_questions.select('..., questions(...)')`
  /// embed silently comes back with `questions: null` on every row for a
  /// student caller, which crashed this with a bare type-cast exception.
  /// The RPC is security-definer and explicitly withholds correct_option,
  /// so it can safely bypass that RLS gap without leaking the answer key.
  Future<void> _cacheQuestions(String dailyTestId) async {
    final rows = await _client.rpc('fetch_test_questions', params: {'p_daily_test_id': dailyTestId});

    final companions = (rows as List).map((r) {
      final row = r as Map<String, dynamic>;
      return CachedQuestionsCompanion.insert(
        dailyTestId: dailyTestId,
        questionId: row['question_id'] as String,
        questionOrder: row['question_order'] as int,
        subject: row['subject'] as String,
        questionText: row['question_text'] as String,
        optionA: row['option_a'] as String,
        optionB: row['option_b'] as String,
        optionC: row['option_c'] as String,
        optionD: row['option_d'] as String,
      );
    }).toList();

    await _db.cacheQuestions(dailyTestId, companions);
  }

  /// The *local* attempt status for this device, or null if nothing's
  /// been started here at all. Checked by TestQuestionScreen/
  /// TestReviewScreen on load: cancelAttempt's server call is fire-and-
  /// forget (the process can be killed by the OS right after
  /// backgrounding, before it lands), so the server might still say
  /// "in_progress" even though this device already forfeited the
  /// attempt. The local write happens before any network call and
  /// persists to SQLite immediately, so it's the more reliable source of
  /// truth for "is this attempt still live on this device" — a fresh
  /// server round-trip can't be trusted to reflect a cancel that never
  /// made it out.
  Future<String?> localAttemptStatus(String dailyTestId) async {
    final local = await _db.localAttemptFor(dailyTestId);
    return local?.status;
  }

  /// True once this device's attempt can no longer be resumed — either
  /// because it's already in a terminal status, or because
  /// [autoSubmitOnExit] has flagged it `pendingSubmit` (which can be true
  /// while `status` is still 'in_progress', if the auto-submit fired
  /// while offline — see that method). TestQuestionScreen/TestReviewScreen
  /// check this on load instead of comparing `status` alone, so a student
  /// who backgrounded the app mid-test can never re-enter the question
  /// screen and keep answering, even before the real submission has
  /// actually landed on the server.
  Future<bool> isAttemptLocked(String dailyTestId) async {
    final local = await _db.localAttemptFor(dailyTestId);
    if (local == null) return false;
    return local.status != 'in_progress' || local.pendingSubmit;
  }

  Future<List<CachedQuestion>> questionsFor(String dailyTestId) => _db.questionsFor(dailyTestId);

  Future<Map<String, String>> myAnswers(String dailyTestId) => _db.answersFor(dailyTestId);

  /// Always writes locally first (works offline), then opportunistically
  /// tries to push immediately so a connected student sees a live save.
  Future<void> answerQuestion({
    required String dailyTestId,
    required String questionId,
    required String selectedOption,
  }) async {
    await _db.upsertAnswer(
      dailyTestId: dailyTestId,
      questionId: questionId,
      selectedOption: selectedOption,
      clientUuid: _uuid.v4(),
    );
    unawaited(syncService.syncNow());
  }

  /// Flushes any pending answers, then submits. If offline, flags the
  /// local attempt for auto-submit once connectivity returns.
  Future<bool> submitAttempt(String dailyTestId) async {
    await syncService.syncNow();
    final local = await _db.localAttemptFor(dailyTestId);
    if (local?.attemptId == null) {
      await _db.upsertLocalAttempt(LocalAttemptsCompanion(
        dailyTestId: Value(dailyTestId),
        attemptId: Value(local?.attemptId),
        status: const Value('in_progress'),
        startedAt: Value(local?.startedAt ?? DateTime.now()),
        pendingSubmit: const Value(true),
      ));
      return false; // couldn't reach server yet — will auto-submit later
    }
    try {
      await _client.rpc('submit_test_attempt', params: {'p_attempt_id': local!.attemptId});
      await _db.upsertLocalAttempt(LocalAttemptsCompanion(
        dailyTestId: Value(dailyTestId),
        attemptId: Value(local.attemptId),
        status: const Value('submitted'),
        startedAt: Value(local.startedAt),
        submittedAt: Value(DateTime.now()),
        pendingSubmit: const Value(false),
      ));
      return true;
    } catch (_) {
      await _db.upsertLocalAttempt(LocalAttemptsCompanion(
        dailyTestId: Value(dailyTestId),
        attemptId: Value(local!.attemptId),
        status: const Value('in_progress'),
        startedAt: Value(local.startedAt),
        pendingSubmit: const Value(true),
      ));
      return false;
    }
  }

  /// Called when the student backgrounds the app mid-test (see
  /// TestQuestionScreen/TestReviewScreen's WidgetsBindingObserver). Locks
  /// the attempt locally first — so the student can never resume it, even
  /// if the process gets killed right after this and the RPC never goes
  /// out — then best-effort tells the server. Reuses the 'absent' status
  /// rather than adding a new enum value: from a results/attendance point
  /// of view, "started then abandoned before submitting" and "never
  /// showed up" both mean the same thing — no valid submission for today.
  Future<void> cancelAttempt(String dailyTestId) async {
    final local = await _db.localAttemptFor(dailyTestId);
    await _db.upsertLocalAttempt(LocalAttemptsCompanion(
      dailyTestId: Value(dailyTestId),
      attemptId: Value(local?.attemptId),
      status: const Value('absent'),
      startedAt: Value(local?.startedAt ?? DateTime.now()),
      submittedAt: Value(DateTime.now()),
      pendingSubmit: const Value(false),
    ));
    final attemptId = local?.attemptId;
    if (attemptId == null) return; // started fully offline — nothing server-side to tell yet
    try {
      await _client.rpc('cancel_test_attempt', params: {'p_attempt_id': attemptId});
    } catch (_) {
      // Offline, or the attempt was already finalized server-side (e.g.
      // publish_results already ran) — either way the local lock above
      // is what actually stops the student from resuming, so this is
      // safe to drop rather than queue for retry.
    }
  }

  /// Called when the student backgrounds the app mid-test (see
  /// TestQuestionScreen/TestReviewScreen's WidgetsBindingObserver) —
  /// leaving no longer forfeits the attempt (see cancelAttempt above,
  /// now unused for this path); instead whatever's been answered so far
  /// is auto-submitted, same as tapping Submit manually.
  ///
  /// Sets `pendingSubmit = true` *first*, synchronously, before any
  /// network call — the app can be killed by the OS at any point right
  /// after backgrounding, so this has to be the thing that actually
  /// blocks resuming (see StudentService.isAttemptLocked), not whatever
  /// happens to land from the network call below. Deliberately leaves
  /// `status` alone here rather than jumping straight to 'submitted':
  /// if this attempt was started fully offline (no attemptId yet),
  /// OfflineSyncService's backfill step only looks at status ==
  /// 'in_progress' rows, so flipping status early would make this
  /// attempt invisible to that backfill and it would never actually
  /// reach the server.
  Future<void> autoSubmitOnExit(String dailyTestId) async {
    final local = await _db.localAttemptFor(dailyTestId);
    await _db.upsertLocalAttempt(LocalAttemptsCompanion(
      dailyTestId: Value(dailyTestId),
      attemptId: Value(local?.attemptId),
      status: Value(local?.status ?? 'in_progress'),
      startedAt: Value(local?.startedAt ?? DateTime.now()),
      pendingSubmit: const Value(true),
    ));
    try {
      // Reuses the normal submit flow: flushes pending answers, then
      // finalizes server-side if reachable. If offline right now, this
      // safely no-ops into "still pendingSubmit" — OfflineSyncService
      // retries the same way it does for a manual Submit made offline.
      await submitAttempt(dailyTestId);
    } catch (_) {
      // Already locked above regardless of outcome.
    }
  }

  /// Rank entry for the signed-in student on a given test, once published.
  Future<RankingEntry?> myRanking(String dailyTestId) async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('rankings')
        .select('*, students(register_number, profiles(full_name))')
        .eq('daily_test_id', dailyTestId)
        .eq('student_id', uid)
        .maybeSingle();
    if (row == null) return null;
    return RankingEntry.fromJson(row);
  }

  /// The highest score overall, and the highest score within the
  /// student's own department, for one test — shown alongside the
  /// student's own rank once results publish. `rankings_select_all`
  /// (see policies.sql) lets any signed-in user read every row of the
  /// `rankings` table, but this deliberately selects only `score` (no
  /// embedded `students`/`profiles` join) — a plain student can't read
  /// another student's row on `students` (that table's RLS only allows
  /// `id = auth.uid()` for non-admin/faculty), so embedding it here would
  /// hit the same silent-null gap `fetch_test_questions` was added to
  /// avoid for questions. `rank() over (...)` (see publish_results in
  /// functions.sql) gives every tied top scorer the same rank of 1, so
  /// filtering on rank instead of re-sorting by score here also handles
  /// ties correctly for free.
  Future<Map<String, int?>> fetchTopScores(String dailyTestId, String departmentId) async {
    final overallRow = await _client
        .from('rankings')
        .select('score')
        .eq('daily_test_id', dailyTestId)
        .eq('rank_overall', 1)
        .limit(1)
        .maybeSingle();
    final departmentRow = await _client
        .from('rankings')
        .select('score')
        .eq('daily_test_id', dailyTestId)
        .eq('department_id', departmentId)
        .eq('rank_department', 1)
        .limit(1)
        .maybeSingle();
    return {
      'overallTop': overallRow?['score'] as int?,
      'departmentTop': departmentRow?['score'] as int?,
    };
  }

  /// Past attempts (for the Progress screen's history + trend charts).
  Future<List<TestAttempt>> myAttemptHistory({int limit = 30}) async {
    final uid = _client.auth.currentUser!.id;
    final rows = await _client
        .from('test_attempts')
        .select()
        .eq('student_id', uid)
        .eq('status', 'submitted')
        .order('submitted_at', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => TestAttempt.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<Question>> reviewQuestions(String dailyTestId) async {
    final cached = await questionsFor(dailyTestId);
    // Client only ever has the non-answer-key fields cached — full
    // Question objects aren't needed for review (correct_option is
    // withheld client-side by design), so review shows subject/text/
    // selected option only, sourced from CachedQuestions + local answers.
    // `category` isn't part of the on-device cache (CachedQuestions has
    // no such column — see local_db/app_database.dart) and isn't shown
    // anywhere on the review screen, so a placeholder value is fine here.
    return cached
        .map((c) => Question(
              id: c.questionId,
              category: TestCategory.aptitude,
              subject: c.subject,
              questionText: c.questionText,
              optionA: c.optionA,
              optionB: c.optionB,
              optionC: c.optionC,
              optionD: c.optionD,
              correctOption: '',
            ))
        .toList();
  }
}
