class RankingEntry {
  final String id;
  final String dailyTestId;
  final String studentId;
  final String departmentId;
  final int year;
  final int score;
  final int? rankOverall;
  final int? rankDepartment;
  final int? rankYear;
  final String? studentName;
  final String? registerNumber;

  const RankingEntry({
    required this.id,
    required this.dailyTestId,
    required this.studentId,
    required this.departmentId,
    required this.year,
    required this.score,
    this.rankOverall,
    this.rankDepartment,
    this.rankYear,
    this.studentName,
    this.registerNumber,
  });

  factory RankingEntry.fromJson(Map<String, dynamic> json) {
    final student = json['students'] as Map<String, dynamic>?;
    final profile = student?['profiles'] as Map<String, dynamic>?;
    return RankingEntry(
      id: json['id'] as String,
      dailyTestId: json['daily_test_id'] as String,
      studentId: json['student_id'] as String,
      departmentId: json['department_id'] as String,
      year: json['year'] as int,
      score: json['score'] as int,
      rankOverall: json['rank_overall'] as int?,
      rankDepartment: json['rank_department'] as int?,
      rankYear: json['rank_year'] as int?,
      studentName: profile?['full_name'] as String?,
      registerNumber: student?['register_number'] as String?,
    );
  }

  /// Rows from the `fetch_top_rankings` RPC (see supabase/functions.sql)
  /// — a flat shape (no nested students/profiles object) since the RPC
  /// already joins student identity in server-side, security-definer
  /// SQL rather than relying on a client-side embed that RLS would
  /// silently null out for any student outside the faculty caller's own
  /// department. The RPC doesn't return daily_test_id (every row it can
  /// return is already scoped to the one test the caller asked for), so
  /// that — and `id`, which this RPC has no equivalent of — come from
  /// the caller instead of the row itself.
  factory RankingEntry.fromRpcJson(Map<String, dynamic> json, {required String dailyTestId}) {
    final studentId = json['student_id'] as String;
    return RankingEntry(
      id: '$dailyTestId-$studentId',
      dailyTestId: dailyTestId,
      studentId: studentId,
      departmentId: json['department_id'] as String,
      year: json['year'] as int,
      score: json['score'] as int,
      rankOverall: json['rank_overall'] as int?,
      rankDepartment: json['rank_department'] as int?,
      rankYear: json['rank_year'] as int?,
      studentName: json['full_name'] as String?,
      registerNumber: json['register_number'] as String?,
    );
  }
}
