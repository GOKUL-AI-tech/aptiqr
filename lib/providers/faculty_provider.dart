import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/attendance_row.dart';
import '../models/daily_test.dart';
import '../models/test_category.dart';
import '../core/utils/app_date.dart';
import '../services/faculty_service.dart';

final facultyServiceProvider = Provider<FacultyService>((ref) => FacultyService());

/// All of today's daily tests — up to 3, one per category (Aptitude/
/// Technical/Communication), whichever the admins have generated so
/// far. Replaces the old single-test `facultyTodayTestProvider`.
final facultyTodayTestsProvider = FutureProvider<List<DailyTest>>((ref) {
  return ref.watch(facultyServiceProvider).fetchTestsForDate(AppDate.todayIst());
});

/// Which category's test the faculty Ranking/Monitoring/Reports screens
/// are currently inspecting — those RPCs (fetch_attendance,
/// fetch_top_rankings) all key off a single dailyTestId, so rather than
/// rewrite them to aggregate across categories, faculty picks one
/// category at a time via a selector on each screen (see
/// widgets/category_selector.dart).
final selectedFacultyCategoryProvider = StateProvider<TestCategory>((ref) => TestCategory.aptitude);

/// The specific DailyTest (if any) matching [selectedFacultyCategoryProvider]
/// out of today's tests — null if that category's test hasn't been
/// generated for today yet.
final selectedFacultyTestProvider = FutureProvider<DailyTest?>((ref) async {
  final tests = await ref.watch(facultyTodayTestsProvider.future);
  final category = ref.watch(selectedFacultyCategoryProvider);
  return tests.where((t) => t.category == category).firstOrNull;
});

class AttendanceFilter {
  final int? year;
  final String? section;
  const AttendanceFilter({this.year, this.section});
}

final attendanceFilterProvider = StateProvider<AttendanceFilter>((ref) => const AttendanceFilter());

final attendanceProvider = FutureProvider.autoDispose<List<AttendanceRow>>((ref) async {
  final test = await ref.watch(selectedFacultyTestProvider.future);
  if (test == null) return [];
  final filter = ref.watch(attendanceFilterProvider);
  return ref.watch(facultyServiceProvider).fetchAttendance(test.id, year: filter.year, section: filter.section);
});

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
