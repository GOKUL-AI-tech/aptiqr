import '../core/supabase/supabase_client.dart';

typedef Json = Map<String, dynamic>;

/// Faculty/admin analytics and integrity RPCs (see supabase/upgrade_v2.sql).
/// All access control is enforced server-side; faculty only ever receive
/// rows for their own department and admins only for their own category.
class InsightsService {
  final _c = SupabaseService.client;

  Future<List<Json>> _rows(String fn, [Json? params]) async {
    final r = await _c.rpc(fn, params: params);
    return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Json>> atRisk() => _rows('fetch_at_risk', {'p_limit': 25});

  Future<List<Json>> topicHeatmap({String? testId, int days = 30}) =>
      _rows('fetch_topic_heatmap', {if (testId != null) 'p_daily_test_id': testId, 'p_days': days});

  Future<List<Json>> trend({int days = 60}) => _rows('fetch_trend', {'p_days': days});

  Future<List<Json>> integrity(String testId) => _rows('fetch_integrity_summary', {'p_daily_test_id': testId});

  Future<Json> readiness(String studentId) async {
    final r = await _c.rpc('placement_readiness', params: {'p_student_id': studentId});
    return Map<String, dynamic>.from(r as Map);
  }

  Future<void> resetDevice(String studentId) async {
    await _c.rpc('reset_student_device', params: {'p_student_id': studentId});
  }

  /// RLS already limits this to the caller's department (faculty) or
  /// everyone (admin).
  Future<List<Json>> searchStudents(String q) async {
    final rows = await _c
        .from('students')
        .select('id, register_number, profiles(full_name)')
        .ilike('register_number', '%${q.trim()}%')
        .limit(20);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
