import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/department.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/department_provider.dart';
import '../../../widgets/loading_button.dart';

Future<void> showAddStudentSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => const _AddStudentSheet());
}

class _AddStudentSheet extends ConsumerStatefulWidget {
  const _AddStudentSheet();

  @override
  ConsumerState<_AddStudentSheet> createState() => _AddStudentSheetState();
}

class _AddStudentSheetState extends ConsumerState<_AddStudentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _regNo = TextEditingController();
  final _password = TextEditingController(text: 'Welcome@123');
  final _section = TextEditingController();
  Department? _dept;
  int _year = 1;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _dept == null) {
      setState(() => _error = _dept == null ? 'Select a department' : null);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminServiceProvider).createStudent(
            fullName: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            registerNumber: _regNo.text.trim(),
            departmentId: _dept!.id,
            year: _year,
            section: _section.text.trim().isEmpty ? null : _section.text.trim(),
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
              Text('Add student', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'), validator: _req),
              const SizedBox(height: 12),
              TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'Email'), validator: _req),
              const SizedBox(height: 12),
              TextFormField(controller: _regNo, decoration: const InputDecoration(labelText: 'Register number'), validator: _req),
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
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _year,
                      decoration: const InputDecoration(labelText: 'Year'),
                      items: AppConstants.years.map((y) => DropdownMenuItem(value: y, child: Text('Year $y'))).toList(),
                      onChanged: (v) => setState(() => _year = v ?? 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _section, decoration: const InputDecoration(labelText: 'Section (optional)'))),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _password, decoration: const InputDecoration(labelText: 'Temporary password'), validator: _req),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: 20),
              LoadingButton(label: 'Add student', loading: _saving, onPressed: _save, color: AppColors.admin),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;
}
