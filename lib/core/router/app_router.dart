import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../../models/user_role.dart';
import '../../models/daily_test.dart';
import '../../providers/auth_provider.dart';
import '../theme/app_theme.dart';

import '../../features/splash/splash_screen.dart';
import '../../features/auth/role_select_screen.dart';
import '../../features/auth/student_login_screen.dart';
import '../../features/auth/faculty_login_screen.dart';
import '../../features/auth/admin_login_screen.dart';
import '../../features/auth/reset_password_screen.dart';

import '../../features/student/shell/student_shell.dart';
import '../../features/student/home/student_home_screen.dart';
import '../../features/student/test/test_instructions_screen.dart';
import '../../features/student/test/test_question_screen.dart';
import '../../features/student/test/test_review_screen.dart';
import '../../features/student/result/result_screen.dart';
import '../../features/student/progress/progress_screen.dart';
import '../../features/student/profile/student_profile_screen.dart';

import '../../features/faculty/shell/faculty_shell.dart';
import '../../features/faculty/qr/today_qr_screen.dart';
import '../../features/faculty/monitoring/student_monitoring_screen.dart';
import '../../features/faculty/ranking/faculty_ranking_screen.dart';
import '../../features/faculty/reports/faculty_reports_screen.dart';
import '../../features/faculty/profile/faculty_profile_screen.dart';
import '../../features/faculty/people/import_students_screen.dart';

import '../../features/admin/shell/admin_shell.dart';
import '../../features/admin/dashboard/admin_dashboard_screen.dart';
import '../../features/admin/question_bank/question_bank_screen.dart';
import '../../features/admin/question_bank/question_upload_screen.dart';
import '../../features/admin/people/students_faculty_screen.dart';
import '../../features/admin/people/import_people_screen.dart';
import '../../features/admin/departments/departments_screen.dart';
import '../../features/admin/daily_test/daily_test_config_screen.dart';
import '../../features/admin/daily_test/admin_test_qr_screen.dart';
import '../../features/admin/results/results_management_screen.dart';
import '../../features/admin/analytics/reports_analytics_screen.dart';
import '../../features/admin/profile/admin_profile_screen.dart';

// IMPORTANT: this provider must build the GoRouter exactly once. Calling
// ref.watch(...) here (as an earlier version of this file did) makes the
// *entire* GoRouter get recreated every time auth/profile state changes —
// and a freshly-constructed GoRouter always resets to `initialLocation`,
// which looked like "navigating to Profile bounces back to Dashboard"
// (really: some unrelated provider read triggered a full router rebuild).
// Instead, `redirect` reads live state via `ref.read` each time go_router
// calls it, and `GoRouterRefreshStream` (using `ref.listen`, not `watch`)
// just tells this *same* router instance to re-run `redirect`.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = GoRouterRefreshStream(ref);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/' ||
          state.matchedLocation == '/role-select' ||
          state.matchedLocation.startsWith('/login');

      final authState = ref.read(authStateChangesProvider);
      final session = authState.valueOrNull?.session;
      final signedIn = session != null;

      if (!signedIn) {
        return loggingIn ? null : '/role-select';
      }

      // "Forgot password?" email link deep-linked back into the app —
      // Supabase treats this as a normal signed-in session, so without
      // this check the redirect below would send them straight into
      // their role's home screen with the OLD password still active and
      // no way back to actually set a new one. See
      // GoRouterRefreshStream.needsPasswordReset and ResetPasswordScreen.
      if (refreshListenable.needsPasswordReset) {
        return state.matchedLocation == '/reset-password' ? null : '/reset-password';
      }

      // Signed in — once we know the role, keep the user inside their
      // own section and bounce them off the auth screens.
      final profile = ref.read(currentProfileProvider).valueOrNull;
      if (profile == null) return null; // still loading profile — hold position

      final role = profile.role;
      final inOwnSection = switch (role) {
        UserRole.student => state.matchedLocation.startsWith('/student'),
        UserRole.faculty => state.matchedLocation.startsWith('/faculty'),
        UserRole.admin => state.matchedLocation.startsWith('/admin'),
      };

      if (loggingIn || !inOwnSection) {
        return switch (role) {
          UserRole.student => '/student',
          UserRole.faculty => '/faculty',
          UserRole.admin => '/admin',
        };
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/role-select', builder: (context, state) => const RoleSelectScreen()),
      GoRoute(path: '/login/student', builder: (context, state) => const StudentLoginScreen()),
      GoRoute(path: '/login/faculty', builder: (context, state) => const FacultyLoginScreen()),
      GoRoute(path: '/login/admin', builder: (context, state) => const AdminLoginScreen()),
      GoRoute(path: '/reset-password', builder: (context, state) => const ResetPasswordScreen()),

      // ---------------- Student ----------------
      ShellRoute(
        builder: (context, state, child) => StudentShell(child: child),
        routes: [
          GoRoute(path: '/student', builder: (context, state) => const StudentHomeScreen()),
          GoRoute(path: '/student/result', builder: (context, state) => const ResultScreen()),
          GoRoute(path: '/student/progress', builder: (context, state) => const ProgressScreen()),
          GoRoute(path: '/student/profile', builder: (context, state) => const StudentProfileScreen()),
        ],
      ),
      GoRoute(
        path: '/student/test/:testId/instructions',
        builder: (context, state) => TestInstructionsScreen(testId: state.pathParameters['testId']!),
      ),
      GoRoute(
        path: '/student/test/:testId/question',
        builder: (context, state) => TestQuestionScreen(testId: state.pathParameters['testId']!),
      ),
      GoRoute(
        path: '/student/test/:testId/review',
        builder: (context, state) => TestReviewScreen(testId: state.pathParameters['testId']!),
      ),
      // A day can have up to 3 tests (Aptitude/Technical/Communication),
      // so "today's result" is no longer a single thing — the bottom-nav
      // Result tab (/student/result, in StudentShell below) is now a list
      // of today's tests, and this pushes the actual score/ranking view
      // for whichever one the student tapped.
      GoRoute(
        path: '/student/result/:testId',
        builder: (context, state) => ResultDetailScreen(testId: state.pathParameters['testId']!),
      ),
      // Note: the three routes above sit outside StudentShell (full-screen
      // test flow, no bottom nav), so they don't automatically inherit
      // StudentShell's Theme wrapper. Student's accent happens to equal
      // the app's default theme color, so this is a non-issue today — but
      // if that ever diverges, wrap these the same way the admin routes
      // below are wrapped.

      // ---------------- Faculty ----------------
      ShellRoute(
        builder: (context, state, child) => FacultyShell(child: child),
        routes: [
          GoRoute(path: '/faculty', builder: (context, state) => const TodayQrScreen()),
          GoRoute(path: '/faculty/monitoring', builder: (context, state) => const StudentMonitoringScreen()),
          GoRoute(path: '/faculty/ranking', builder: (context, state) => const FacultyRankingScreen()),
          GoRoute(path: '/faculty/reports', builder: (context, state) => const FacultyReportsScreen()),
          GoRoute(path: '/faculty/profile', builder: (context, state) => const FacultyProfileScreen()),
        ],
      ),

      // Pushed full-screen from Faculty Profile's "Import students" button,
      // so (like the admin routes below) it sits outside FacultyShell and
      // needs its own Theme wrapper to pick up the faculty (blue) accent.
      GoRoute(
        path: '/faculty/import-students',
        builder: (context, state) => Theme(data: AppTheme.forRole('faculty'), child: const ImportStudentsScreen()),
      ),

      // ---------------- Admin ----------------
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(path: '/admin', builder: (context, state) => const AdminDashboardScreen()),
          GoRoute(path: '/admin/question-bank', builder: (context, state) => const QuestionBankScreen()),
          GoRoute(path: '/admin/people', builder: (context, state) => const StudentsFacultyScreen()),
          GoRoute(path: '/admin/reports', builder: (context, state) => const ReportsAnalyticsScreen()),
          GoRoute(path: '/admin/profile', builder: (context, state) => const AdminProfileScreen()),
        ],
      ),
      // These four sit outside AdminShell (pushed full-screen from the
      // Dashboard's quick actions / Question Bank's app bar action), so
      // each needs its own Theme wrapper to pick up the admin (green)
      // accent — otherwise they'd silently fall back to the app's default
      // orange theme, same bug this whole fix addresses.
      GoRoute(
        path: '/admin/question-bank/upload',
        builder: (context, state) => Theme(data: AppTheme.forRole('admin'), child: const QuestionUploadScreen()),
      ),
      GoRoute(
        path: '/admin/people/import-students',
        builder: (context, state) => Theme(data: AppTheme.forRole('admin'), child: const ImportPeopleScreen(role: 'student')),
      ),
      GoRoute(
        path: '/admin/people/import-faculty',
        builder: (context, state) => Theme(data: AppTheme.forRole('admin'), child: const ImportPeopleScreen(role: 'faculty')),
      ),
      GoRoute(
        path: '/admin/departments',
        builder: (context, state) => Theme(data: AppTheme.forRole('admin'), child: const DepartmentsScreen()),
      ),
      GoRoute(
        path: '/admin/daily-test',
        builder: (context, state) => Theme(data: AppTheme.forRole('admin'), child: const DailyTestConfigScreen()),
      ),
      GoRoute(
        path: '/admin/results',
        builder: (context, state) => Theme(data: AppTheme.forRole('admin'), child: const ResultsManagementScreen()),
      ),
      GoRoute(
        // Reached both right after generating a test (DailyTestConfigScreen
        // ._generate) and "any time" afterwards from that screen's Recent
        // tests list — the DailyTest is always already in hand at both call
        // sites, so it's passed via `extra` instead of adding a
        // testId-keyed provider just for this.
        path: '/admin/daily-test/qr',
        builder: (context, state) {
          final test = state.extra;
          // extra is only ever missing if this route is reached some way
          // other than the two in-app context.push(..., extra: test)
          // call sites (e.g. a raw deep link) — fail into a clear message
          // rather than crashing on the cast below.
          if (test is! DailyTest) {
            return Theme(
              data: AppTheme.forRole('admin'),
              child: const Scaffold(body: Center(child: Text('No test selected.'))),
            );
          }
          return Theme(data: AppTheme.forRole('admin'), child: AdminTestQrScreen(test: test));
        },
      ),
    ],
  );
});

/// Bridges Riverpod's auth/profile providers into a [Listenable] so
/// GoRouter re-evaluates `redirect` whenever either changes.
class GoRouterRefreshStream extends ChangeNotifier {
  /// Sticky flag: true once Supabase reports we've landed back in the app
  /// via the "Forgot password?" email link (an `AuthChangeEvent
  /// .passwordRecovery` event — see AuthService.sendPasswordReset /
  /// ResetPasswordScreen). Deliberately sticky rather than "is the latest
  /// auth event passwordRecovery" — `redirect` reads this on every check,
  /// and a later unrelated auth event could otherwise overwrite it before
  /// the user's had a chance to actually set their new password. Cleared
  /// on sign-out, which ResetPasswordScreen triggers once it succeeds.
  bool needsPasswordReset = false;

  GoRouterRefreshStream(Ref ref) {
    ref.listen(authStateChangesProvider, (_, next) {
      final event = next.valueOrNull?.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        needsPasswordReset = true;
      } else if (event == AuthChangeEvent.signedOut) {
        needsPasswordReset = false;
      }
      notifyListeners();
    });
    ref.listen(currentProfileProvider, (_, __) => notifyListeners());
  }
}
