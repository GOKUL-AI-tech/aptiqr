import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily_test.dart';
import '../models/ranking.dart';
import '../models/test_attempt.dart';
import '../services/offline_sync_service.dart';
import '../services/student_service.dart';
import 'auth_provider.dart';

final studentServiceProvider = Provider<StudentService>((ref) {
  return StudentService(ref.watch(offlineSyncServiceProvider));
});

// Every provider below reads `ref.watch(currentUserIdProvider)` purely to
// register it as a dependency, even though the value itself is unused —
// these are plain (non-autoDispose) providers, so without this their
// cached Future result survives a sign-out/sign-in cycle within the same
// app process untouched. Two students testing in a row on the same
// device (or the same emulator across dev sessions) would otherwise have
// the SECOND student's Home/Progress/Results screens serving the FIRST
// student's cached attempt/ranking/history — e.g. a student who never
// took today's test seeing "View Result" because the previous student's
// submitted attempt for that same daily_test_id was still cached. Tying
// each provider to currentUserIdProvider forces Riverpod to treat a
// user-id change (any sign-out/sign-in) as a reason to refetch.

/// Every one of today's tests — up to 3 (Aptitude/Technical/
/// Communication), however many the admins have generated so far.
/// Replaces the old single-test `todayTestProvider`.
final todayTestsProvider = FutureProvider<List<DailyTest>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(studentServiceProvider).fetchTodayTests();
});

/// A single test by id, for screens reached after the student has
/// already picked a specific category's card off Home (test
/// instructions/question/review/result — all keyed by testId).
final testByIdProvider = FutureProvider.family<DailyTest?, String>((ref, testId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(studentServiceProvider).fetchTestById(testId);
});

final myAttemptProvider = FutureProvider.family<TestAttempt?, String>((ref, dailyTestId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(studentServiceProvider).fetchMyAttempt(dailyTestId);
});

final myRankingProvider = FutureProvider.family<RankingEntry?, String>((ref, dailyTestId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(studentServiceProvider).myRanking(dailyTestId);
});

/// Overall + own-department top score for a test — needs the signed-in
/// student's own departmentId (to know which department's top score to
/// fetch), so this reads currentStudentProvider first rather than taking
/// the department as a second family argument (Riverpod families take a
/// single parameter).
final topScoresProvider = FutureProvider.family<Map<String, int?>, String>((ref, dailyTestId) async {
  final student = await ref.watch(currentStudentProvider.future);
  if (student == null) return {'overallTop': null, 'departmentTop': null};
  return ref.watch(studentServiceProvider).fetchTopScores(dailyTestId, student.departmentId);
});

final myAttemptHistoryProvider = FutureProvider<List<TestAttempt>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(studentServiceProvider).myAttemptHistory();
});
