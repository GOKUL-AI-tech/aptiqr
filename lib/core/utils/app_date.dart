/// College-local ("Asia/Kolkata", UTC+5:30, no DST) calendar helpers.
///
/// Several screens need to agree on "what calendar day is it right now" —
/// e.g. a faculty device must land on the exact same `test_date` an admin
/// device used when generating today's test (`daily_tests.test_date`),
/// or the faculty Today's QR screen simply won't find the row (see
/// FacultyService.fetchTestsForDate: it filters with `.eq('test_date',
/// ...)`, and a mismatched date means an empty result, not an error).
///
/// Computing "today" from each device's own `DateTime.now()` breaks the
/// moment either device's system clock/timezone is wrong — common on
/// emulators (see the note in core/supabase/supabase_client.dart about
/// autoRefreshToken existing specifically because of a skewed emulator
/// clock) or simply not set to IST. The admin's own "Recent tests" list
/// has no date filter (fetchRecentTests just orders by test_date
/// descending), so a test generated with a wrong calendar date still
/// shows up there — masking the mismatch from the admin's point of view
/// while it makes the row invisible to a faculty/student device computing
/// "today" correctly (or differently).
///
/// Since the college is always IST, this derives "today" from UTC plus a
/// fixed +5:30 offset instead of trusting the device's local timezone
/// setting. That fixes the timezone half of the problem; it does not
/// protect against a device's clock being wrong by hours/days in
/// absolute terms — there's no way to fix that client-side.
class AppDate {
  AppDate._();

  static const Duration istOffset = Duration(hours: 5, minutes: 30);

  /// Today's calendar date in India Standard Time, independent of the
  /// device's own timezone setting.
  static DateTime todayIst() {
    final nowIst = DateTime.now().toUtc().add(istOffset);
    return DateTime(nowIst.year, nowIst.month, nowIst.day);
  }

  /// Formats a calendar date as the `YYYY-MM-DD` string Postgres expects
  /// for a `date` column — matches the padding StudentService/
  /// FacultyService/AdminService already used ad hoc in several places.
  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
