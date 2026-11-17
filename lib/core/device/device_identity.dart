import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A random per-install id. The server binds each student account to one
/// id (see `student_devices` in supabase/upgrade_v2.sql) and refuses a
/// second student on the same id for the same test, which stops one phone
/// from being passed around to mark proxy attendance.
class DeviceIdentity {
  DeviceIdentity._();
  static const _key = 'aptiqr_device_id';
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null || id.length < 8) {
      id = const Uuid().v4();
      await prefs.setString(_key, id);
    }
    return _cached = id;
  }
}
