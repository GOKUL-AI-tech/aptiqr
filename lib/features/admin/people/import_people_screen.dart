import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/department.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/department_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/loading_button.dart';

/// Admin bulk import for either students or faculty — [role] picks which.
/// Unlike the faculty "Import students" screen (always the caller's own
/// department, no column needed), admin can import into *any* department
/// in one file, so a Department Code column is required and validated
/// against the live department list here.
class ImportPeopleScreen extends ConsumerStatefulWidget {
  final String role; // 'student' or 'faculty'
  const ImportPeopleScreen({super.key, required this.role});

  @override
  ConsumerState<ImportPeopleScreen> createState() => _ImportPeopleScreenState();
}

class _ImportPeopleScreenState extends ConsumerState<ImportPeopleScreen> {
  String? _fileName;
  List<List<dynamic>>? _rows;
  bool _loading = false;
  bool _importing = false;
  int? _importedCount;
  List<String> _skippedRows = const [];
  String? _error;

  bool get _isStudent => widget.role == 'student';

  Future<void> _pickFile() async {
    setState(() {
      _loading = true;
      _error = null;
      _importedCount = null;
      _skippedRows = const [];
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _error = 'Could not read the selected file (no data returned by the picker).');
        return;
      }

      List<List<dynamic>> rows;
      if (file.extension?.toLowerCase() == 'csv') {
        final text = utf8.decode(bytes, allowMalformed: true).replaceAll('\r\n', '\n');
        rows = const CsvToListConverter().convert(text, eol: '\n');
      } else {
        rows = await ref.read(adminServiceProvider).parseExcelBytes(bytes);
      }

      if (rows.isEmpty) {
        setState(() => _error = 'That file has no rows (or nothing after the header).');
        return;
      }

      setState(() {
        _fileName = file.name;
        _rows = rows;
      });
    } catch (e) {
      setState(() => _error = 'Could not open that file: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _import(Map<String, String> deptCodeToId) async {
    if (_rows == null) return;
    setState(() => _importing = true);
    try {
      final result = _isStudent
          ? await ref.read(adminServiceProvider).bulkImportStudents(_rows!, deptCodeToId)
          : await ref.read(adminServiceProvider).bulkImportFaculty(_rows!, deptCodeToId);
      setState(() {
        _importedCount = result.imported;
        _skippedRows = result.skipped;
      });
      if (result.imported > 0) {
        ref.invalidate(_isStudent ? allStudentsProvider : allFacultyProvider);
      }
    } catch (e) {
      setState(() => _error = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deptsAsync = ref.watch(allDepartmentsProvider);
    final columns = _isStudent
        ? 'Full Name · Email · Register Number · Department Code · Year · Section · Temp Password'
        : 'Full Name · Email · Faculty ID · Department Code · Assigned Years (e.g. 1,2,3,4) · Temp Password';

    return Scaffold(
      appBar: AppBar(title: Text(_isStudent ? 'Bulk Import Students' : 'Bulk Import Faculty')),
      body: AsyncValueWidget<List<Department>>(
        value: deptsAsync,
        data: (depts) {
          final deptCodeToId = {for (final d in depts) d.code.toUpperCase(): d.id};
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Columns expected (first row is treated as a header and skipped):\n$columns\n\n'
                  'Department Code must match a code from the Departments screen (${depts.map((d) => d.code).join(', ')}).',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickFile,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(_fileName ?? 'Choose .xlsx or .csv file'),
                ),
                if (_loading) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (_rows != null) ...[
                  const SizedBox(height: 16),
                  Text('${_rows!.length - 1} row${_rows!.length - 1 == 1 ? '' : 's'} detected', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  LoadingButton(
                    label: 'Import ${_isStudent ? 'students' : 'faculty'}',
                    loading: _importing,
                    onPressed: () => _import(deptCodeToId),
                    color: AppColors.admin,
                  ),
                ],
                if (_importedCount != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _skippedRows.isEmpty
                        ? 'Imported $_importedCount ${_isStudent ? 'students' : 'faculty'} successfully.'
                        : 'Imported $_importedCount ${_isStudent ? 'students' : 'faculty'}. ${_skippedRows.length} row${_skippedRows.length == 1 ? '' : 's'} skipped.',
                    style: TextStyle(color: _importedCount! > 0 ? AppColors.success : AppColors.warning, fontWeight: FontWeight.w600),
                  ),
                ],
                if (_skippedRows.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.warningLight, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Rows that need fixing (not imported):', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        ..._skippedRows.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('•  $s', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
