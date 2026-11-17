import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/department.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/department_provider.dart';
import '../../../widgets/loading_button.dart';

Future<void> showAddFacultySheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => const _AddFacultySheet());
}

class _AddFacultySheet extends ConsumerStatefulWidget {
  const _AddFacultySheet();

  @override
  ConsumerState<_AddFacultySheet> createState() => _AddFacultySheetState();
}

class _AddFacultySheetState extends ConsumerState<_AddFacultySheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _facultyId = TextEditingController();
  final _password = TextEditingController(text: 'Welcome@123');
  Department? _dept;
  final Set<int> _years = {1, 2, 3, 4};
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminServiceProvider).createFaculty(
            fullName: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            facultyId: _facultyId.text.trim(),
            departmentId: _dept?.id,
            assignedYears: _years.toList()..sort(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deptsAsync = ref.watch(departmentsProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Form(
          key: _formKey,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Text('Add faculty', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'), validator: _req),
              const SizedBox(height: 12),
              TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'Email'), validator: _req),
              const SizedBox(height: 12),
              TextFormField(controller: _facultyId, decoration: const InputDecoration(labelText: 'Faculty ID'), validator: _req),
              const SizedBox(height: 12),
              deptsAsync.when(
                data: (depts) => DropdownButtonFormField<Department>(
                  value: _dept,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: depts
                      .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text('${d.code} — ${d.name}', overflow: TextOverflow.ellipsis, maxLines: 1),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _dept = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, st) => const Text('Could not load departments'),
              ),
              const SizedBox(height: 12),
              const Text('Assigned years', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 8,
                children: AppConstants.years
                    .map((y) => FilterChip(
                          label: Text('Year $y'),
                          selected: _years.contains(y),
                          onSelected: (sel) => setState(() => sel ? _years.add(y) : _years.remove(y)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _password, decoration: const InputDecoration(labelText: 'Temporary password'), validator: _req),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: 20),
              LoadingButton(label: 'Add faculty', loading: _saving, onPressed: _save, color: AppColors.admin),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;
}
