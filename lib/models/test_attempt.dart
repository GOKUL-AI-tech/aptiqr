enum AttemptStatus { notStarted, inProgress, submitted, absent }

AttemptStatus attemptStatusFromString(String value) {
  switch (value) {
    case 'in_progress':
      return AttemptStatus.inProgress;
    case 'submitted':
      return AttemptStatus.submitted;
    case 'absent':
      return AttemptStatus.absent;
    default:
      return AttemptStatus.notStarted;
  }
}

String attemptStatusToString(AttemptStatus status) {
  switch (status) {
    case AttemptStatus.inProgress:
      return 'in_progress';
    case AttemptStatus.submitted:
      return 'submitted';
    case AttemptStatus.absent:
      return 'absent';
    case AttemptStatus.notStarted:
      return 'not_started';
  }
}

class TestAttempt {
  final String id;
  final String dailyTestId;
  final String studentId;
  final AttemptStatus status;
  final DateTime? startedAt;
  final DateTime? submittedAt;
  final int? score;
  final int? totalQuestions;
  final bool syncedOffline;

  const TestAttempt({
    required this.id,
    required this.dailyTestId,
    required this.studentId,
    required this.status,
    this.startedAt,
    this.submittedAt,
    this.score,
    this.totalQuestions,
    this.syncedOffline = false,
  });

  factory TestAttempt.fromJson(Map<String, dynamic> json) {
    return TestAttempt(
      id: json['id'] as String,
      dailyTestId: json['daily_test_id'] as String,
      studentId: json['student_id'] as String,
      status: attemptStatusFromString(json['status'] as String),
      startedAt: json['started_at'] == null ? null : DateTime.parse(json['started_at'] as String),
      submittedAt: json['submitted_at'] == null ? null : DateTime.parse(json['submitted_at'] as String),
      score: json['score'] as int?,
      totalQuestions: json['total_questions'] as int?,
      syncedOffline: json['synced_offline'] as bool? ?? false,
    );
  }
}
