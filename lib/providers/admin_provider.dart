import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily_test.dart';
import '../models/faculty.dart';
import '../models/question.dart';
import '../models/student.dart';
import '../services/admin_service.dart';
import 'auth_provider.dart';

final adminServiceProvider = Provider<AdminService>((ref) => AdminService());

// Moved here (from students_faculty_screen.dart, previously private
// `_allStudentsProvider`/`_allFacultyProvider`) so the admin bulk-import
// screen can invalidate them after a successful import without a
// circular import between the two screen files.
final allStudentsProvider = FutureProvider.autoDispose<List<StudentProfile>>((ref) => ref.watch(adminServiceProvider).fetchStudents());
final allFacultyProvider = FutureProvider.autoDispose<List<FacultyProfile>>((ref) => ref.watch(adminServiceProvider).fetchFaculty());

class QuestionFilter {
  final String? subject;
  final QuestionDifficulty? difficulty;
  final String? search;
  const QuestionFilter({this.subject, this.difficulty, this.search});
}

final questionFilterProvider = StateProvider<QuestionFilter>((ref) => const QuestionFilter());

final questionsProvider = FutureProvider.autoDispose<List<Question>>((ref) {
  final f = ref.watch(questionFilterProvider);
  return ref.watch(adminServiceProvider).fetchQuestions(subject: f.subject, difficulty: f.difficulty, search: f.search);
});

final subjectsProvider = FutureProvider<List<String>>((ref) {
  // Server-side RLS already scopes `questions` (and so `fetchSubjects`)
  // to the calling admin's own category, but without this the *cache*
  // doesn't know that: this provider isn't autoDispose, so on a shared
  // device an Admin A -> sign out -> Admin B switch (same app process)
  // used to keep serving Admin A's category's subject list in Admin B's
  // filter dropdowns until something else happened to invalidate it —
  // same class of bug already fixed for the student providers in
  // student_provider.dart.
  ref.watch(currentUserIdProvider);
  return ref.watch(adminServiceProvider).fetchSubjects();
});

/// Scoped to the signed-in admin's own category — `daily_tests` select
/// RLS deliberately stays open to every signed-in user (students/
/// faculty need to see all 3 categories' tests), so unlike questions
/// this filter has to happen client-side rather than via RLS. See
/// AdminService.fetchRecentTests.
final recentTestsProvider = FutureProvider.autoDispose<List<DailyTest>>((ref) async {
  final admin = await ref.watch(currentAdminProvider.future);
  if (admin == null) return [];
  return ref.watch(adminServiceProvider).fetchRecentTests(category: admin.category);
});
