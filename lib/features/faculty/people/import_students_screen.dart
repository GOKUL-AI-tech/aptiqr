import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/loading_button.dart';

/// Faculty-facing bulk student import — always into the faculty member's
/// own department (never a column in the file; the create-user Edge
/// Function enforces this server-side too, see supabase/functions/
/// create-user/index.ts). Mirrors the admin question-bank upload screen's
/// pattern: pick a file, preview row count, import, show a per-row skip
/// reason list instead of a bare success/fail count.
class ImportStudentsScreen extends ConsumerStatefulWidget {
  const ImportStudentsScreen({super.key});

  @override
  ConsumerState<ImportStudentsScreen> createState() => _ImportStudentsScreenState();
}

class _ImportStudentsScreenState extends ConsumerState<ImportStudentsScreen> {
  String? _fileName;
  List<List<dynamic>>? _rows;
  bool _loading = false;
  bool _importing = false;
  int? _importedCount;
  List<String> _skippedRows = const [];
  String? _error;

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
        // Normalize CRLF -> LF before parsing — see question_upload_screen.dart
        // for why this matters (Excel/Windows exports use \r\n).
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

  Future<void> _import(String departmentId) async {
    if (_rows == null) return;
    setState(() => _importing = true);
    try {
      final result = await ref.read(adminServiceProvider).bulkImportStudentsToDepartment(_rows!, departmentId);
      setState(() {
        _importedCount = result.imported;
        _skippedRows = result.skipped;
      });
    } catch (e) {
      setState(() => _error = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final facultyAsync = ref.watch(currentFacultyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Import Students')),
      body: facultyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load your profile: $e', style: const TextStyle(color: AppColors.error))),
        data: (faculty) {
          final departmentId = faculty?.departmentId;
          if (departmentId == null || departmentId.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Your faculty account has no assigned department yet — ask an admin to set one before importing students.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Columns expected (first row is treated as a header and skipped):\n'
                  'Full Name · Email · Register Number · Year · Section · Temp Password\n\n'
                  'Students are always added to your own department — no department column needed.',
                  style: TextStyle(color: AppColors.textSecondary),
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
                  Text('${_rows!.length - 1} student rows detected', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  LoadingButton(
                    label: 'Import into my department',
                    loading: _importing,
                    onPressed: () => _import(departmentId),
                    color: AppColors.faculty,
                  ),
                ],
                if (_importedCount != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _skippedRows.isEmpty
                        ? 'Imported $_importedCount students successfully.'
                        : 'Imported $_importedCount students. ${_skippedRows.length} row${_skippedRows.length == 1 ? '' : 's'} skipped.',
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
