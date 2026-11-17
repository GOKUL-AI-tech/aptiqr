/// Non-secret, non-visual constants used across the app.
class AppConstants {
  AppConstants._();

  static const String appName = 'Daily Aptitude Test';
  static const String collegeName = 'Nehru Arts & Science College, Coimbatore';

  static const int defaultQuestionCount = 20;
  static const int defaultDurationMinutes = 30;

  // Default daily test window (overridable per-day by admin) — see
  // supabase/functions.sql::generate_daily_test.
  static const int defaultOpenHour = 10; // 10 AM
  static const int defaultCloseHour = 14; // 2 PM
  static const int defaultResultsHour = 15; // 3 PM

  static const List<String> departmentCodes = [
    'AIML',
    'CSE',
    'IT',
    'ECE',
    'BCA',
    'MCA',
  ];

  static const List<int> years = [1, 2, 3, 4];

  /// Deep link Supabase's password-reset email points back to (see
  /// AuthService.sendPasswordReset, ResetPasswordScreen, and the
  /// matching intent-filter in android/app/src/main/AndroidManifest.xml).
  /// This exact URL must also be added under Supabase Dashboard >
  /// Authentication > URL Configuration > Redirect URLs, or Supabase
  /// will reject it and the email link will fail.
  static const String passwordResetRedirectUrl = 'aptiqr://reset-callback';

  // Local (offline) DB / secure storage keys
  static const String secureKeySessionRole = 'aptiqr_session_role';
  static const String secureKeyLastSyncAt = 'aptiqr_last_sync_at';
}
