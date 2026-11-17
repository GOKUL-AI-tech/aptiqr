import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/department.dart';
import '../../../providers/department_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/loading_button.dart';
import '../../../widgets/refresh_icon_button.dart';

/// Deck slide 07 — "Manage AIML, CSE, IT, ECE, BCA, MCA and their year groups."
class DepartmentsScreen extends ConsumerWidget {
  const DepartmentsScreen({super.key});

  void _refresh(WidgetRef ref) {
    // Both providers can be affected by any mutation here (add/toggle/
    // delete), so refresh both — the active-only one feeds the student
    // login picker and the people-assignment dropdowns elsewhere.
    ref.invalidate(departmentsProvider);
    ref.invalidate(allDepartmentsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Deliberately allDepartmentsProvider, not departmentsProvider — this
    // screen needs to show inactive departments too, or switching one
    // off here would make it vanish from this very screen with no way
    // to ever switch it back on. See providers/department_provider.dart.
    final deptsAsync = ref.watch(allDepartmentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Departments'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            _refresh(ref);
            await ref.read(allDepartmentsProvider.future);
          }),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.admin,
        onPressed: () => _showAddDeptSheet(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: AsyncValueWidget<List<Department>>(
        value: deptsAsync,
        data: (depts) {
          if (depts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No departments yet — tap + to add one.', style: TextStyle(color: AppColors.textSecondary)),
              ),
            );
          }
          return RefreshIndicator(
            color: AppColors.admin,
            onRefresh: () async {
              _refresh(ref);
              await ref.read(allDepartmentsProvider.future);
            },
            child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
            itemCount: depts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = depts[i];
              // d.code.substring(0, 2) used to crash outright
              // (RangeError) for any department whose code was shorter
              // than 2 characters — including an empty string, which the
              // "Add department" sheet could produce before it had real
              // validation (see that fix's comment below). This clamps
              // to whatever the code actually has instead of assuming
              // it's always >= 2 chars.
              final badge = d.code.isEmpty ? '?' : d.code.substring(0, d.code.length < 2 ? d.code.length : 2);
              return Opacity(
                opacity: d.isActive ? 1 : 0.5,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.adminLight, shape: BoxShape.circle),
                        child: Text(badge, style: const TextStyle(color: AppColors.admin, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.code.isEmpty ? '(no code)' : d.code,
                              style: TextStyle(fontWeight: FontWeight.w700, color: d.code.isEmpty ? AppColors.error : null),
                            ),
                            Text(
                              d.name.isEmpty ? '(no name)' : d.name,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: d.isActive,
                        activeThumbColor: AppColors.admin,
                        onChanged: (v) async {
                          try {
                            await ref.read(departmentServiceProvider).setActive(d.id, v);
                            _refresh(ref);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                            }
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                        tooltip: 'Delete department',
                        onPressed: () => _confirmDelete(context, ref, d),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Department d) async {
    final label = d.code.isEmpty ? '(no code)' : d.code;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $label?'),
        content: const Text(
          'This cannot be undone. If any student or faculty is already assigned to this '
          'department, deletion will be blocked — deactivate it instead in that case.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(departmentServiceProvider).delete(d.id);
      _refresh(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted $label.')));
      }
    } catch (e) {
      final msg = '$e'.contains('foreign key') || '$e'.contains('violates')
          ? 'Can\'t delete "$label" — students or faculty are still assigned to it. Deactivate it instead.'
          : 'Could not delete: $e';
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  void _showAddDeptSheet(BuildContext context, WidgetRef ref) {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    bool saving = false;
    String? error;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add department', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Code (e.g. CSE)')),
              const SizedBox(height: 12),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full name')),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: 20),
              LoadingButton(
                label: 'Add',
                loading: saving,
                color: AppColors.admin,
                onPressed: () async {
                  // Previously this had no validation and no try/catch at
                  // all: an empty field, a duplicate code (the `code`
                  // column is `unique` in schema.sql), or any other
                  // Postgres/network error left the button spinning
                  // forever with zero feedback — indistinguishable from
                  // "doesn't work". That's exactly what was reported.
                  final code = codeCtrl.text.trim().toUpperCase();
                  final name = nameCtrl.text.trim();
                  if (code.isEmpty || name.isEmpty) {
                    setState(() => error = 'Enter both a code and a full name.');
                    return;
                  }
                  setState(() {
                    saving = true;
                    error = null;
                  });
                  try {
                    await ref.read(departmentServiceProvider).create(code: code, name: name);
                    _refresh(ref);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  } catch (e) {
                    final msg = '$e'.contains('duplicate key') || '$e'.contains('already exists')
                        ? 'A department with code "$code" already exists.'
                        : 'Could not add department: $e';
                    if (ctx.mounted) setState(() => error = msg);
                  } finally {
                    if (ctx.mounted) setState(() => saving = false);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
