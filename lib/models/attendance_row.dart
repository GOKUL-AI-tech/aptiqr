import 'test_attempt.dart';

/// Row shown on the faculty Student Monitoring screen — a test_attempts
/// record enriched with the student's identity for display/filtering.
class AttendanceRow {
  final TestAttempt attempt;
  final String studentName;
  final String registerNumber;
  final String departmentId;
  final int year;
  final String? section;

  const AttendanceRow({
    required this.attempt,
    required this.studentName,
    required this.registerNumber,
    required this.departmentId,
    required this.year,
    this.section,
  });

  factory AttendanceRow.fromJson(Map<String, dynamic> json) {
    final student = json['students'] as Map<String, dynamic>?;
    final profile = student?['profiles'] as Map<String, dynamic>?;
    return AttendanceRow(
      attempt: TestAttempt.fromJson(json),
      studentName: profile?['full_name'] as String? ?? '',
      registerNumber: student?['register_number'] as String? ?? '',
      departmentId: student?['department_id'] as String? ?? '',
      year: student?['year'] as int? ?? 0,
      section: student?['section'] as String?,
    );
  }

  /// Rows from the `fetch_attendance` RPC (see supabase/functions.sql) —
  /// a flat left-join of every student in scope against `test_attempts`
  /// for one test, so students who never even opened the test still show
  /// up (as 'not_started') instead of being silently absent from the list.
  factory AttendanceRow.fromRpcJson(Map<String, dynamic> json, {required String dailyTestId}) {
    return AttendanceRow(
      attempt: TestAttempt(
        id: json['attempt_id'] as String? ?? '',
        dailyTestId: dailyTestId,
        studentId: json['student_id'] as String,
        status: attemptStatusFromString(json['status'] as String? ?? 'not_started'),
        startedAt: json['started_at'] == null ? null : DateTime.parse(json['started_at'] as String),
        submittedAt: json['submitted_at'] == null ? null : DateTime.parse(json['submitted_at'] as String),
        score: json['score'] as int?,
        totalQuestions: json['total_questions'] as int?,
      ),
      studentName: json['full_name'] as String? ?? '',
      registerNumber: json['register_number'] as String? ?? '',
      departmentId: json['department_id'] as String? ?? '',
      year: json['year'] as int? ?? 0,
      section: json['section'] as String?,
    );
  }
}
