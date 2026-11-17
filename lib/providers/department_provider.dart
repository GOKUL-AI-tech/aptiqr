import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/department.dart';
import '../services/department_service.dart';

final departmentServiceProvider = Provider((ref) => DepartmentService());

final departmentsProvider = FutureProvider<List<Department>>((ref) {
  return ref.watch(departmentServiceProvider).fetchAll();
});

/// Active AND inactive departments — used only by the admin Departments
/// management screen. [departmentsProvider] above defaults to active-only
/// (correct for the student login picker and the faculty/student
/// assignment dropdowns — you shouldn't be able to pick a department
/// that's been switched off), but the *management* screen needs to see
/// everything, or toggling a department inactive there would make it
/// vanish from that same screen with no way to ever switch it back on.
final allDepartmentsProvider = FutureProvider<List<Department>>((ref) {
  return ref.watch(departmentServiceProvider).fetchAll(activeOnly: false);
});

final departmentByIdProvider = Provider.family<Department?, String?>((ref, id) {
  if (id == null) return null;
  final list = ref.watch(departmentsProvider).valueOrNull ?? [];
  for (final d in list) {
    if (d.id == id) return d;
  }
  return null;
});
