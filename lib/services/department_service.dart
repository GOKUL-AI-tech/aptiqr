import '../core/supabase/supabase_client.dart';
import '../models/department.dart';

class DepartmentService {
  final _client = SupabaseService.client;

  Future<List<Department>> fetchAll({bool activeOnly = true}) async {
    var query = _client.from('departments').select();
    if (activeOnly) query = query.eq('is_active', true);
    final rows = await query.order('code');
    return (rows as List).map((r) => Department.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Department> create({required String code, required String name, List<int>? years}) async {
    final row = await _client
        .from('departments')
        .insert({'code': code, 'name': name, if (years != null) 'years_offered': years})
        .select()
        .single();
    return Department.fromJson(row);
  }

  Future<void> setActive(String id, bool isActive) async {
    await _client.from('departments').update({'is_active': isActive}).eq('id', id);
  }

  /// Fails with a Postgres foreign-key-violation error (surfaced as-is
  /// to the caller) if any student/faculty row still references this
  /// department — that's intentional protection, not a bug to work
  /// around; deactivate it instead if it has real people in it.
  Future<void> delete(String id) async {
    await _client.from('departments').delete().eq('id', id);
  }
}
