import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/test_category.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/loading_button.dart';

/// Deck slide 07 — "Upload 3,000+ questions by Excel/CSV."
/// Expected columns (header row skipped): Subject, Topic, Question,
/// Option A, Option B, Option C, Option D, Correct (A-D), Difficulty.
class QuestionUploadScreen extends ConsumerStatefulWidget {
  const QuestionUploadScreen({super.key});

  @override
  ConsumerState<QuestionUploadScreen> createState() => _QuestionUploadScreenState();
}

class _QuestionUploadScreenState extends ConsumerState<QuestionUploadScreen> {
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
        // Normalize CRLF -> LF before parsing. Files exported from Excel/
        // Windows tools are almost always \r\n; forcing eol: '\n' without
        // this would leave a trailing \r stuck on the *last* column of
        // every row (harmless here since bulkImportQuestions trims each
        // cell, but not guaranteed in general, and confusing to debug).
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
      // Previously uncaught — a picker/permission/parse failure would
      // silently do nothing from the user's point of view. Now it shows.
      setState(() => _error = 'Could not open that file: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _import() async {
    if (_rows == null) return;
    final category = ref.read(currentAdminProvider).valueOrNull?.category;
    if (category == null) {
      setState(() => _error = 'Could not determine your admin category yet — try again in a moment.');
      return;
    }
    setState(() => _importing = true);
    try {
      final result = await ref.read(adminServiceProvider).bulkImportQuestions(_rows!, category);
      setState(() {
        _importedCount = result.imported;
        _skippedRows = result.skipped;
      });
      if (result.imported > 0) {
        ref.invalidate(questionsProvider);
        ref.invalidate(subjectsProvider);
      }
    } catch (e) {
      setState(() => _error = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryLabel = ref.watch(currentAdminProvider).valueOrNull?.category.label;
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk Import Questions')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (categoryLabel != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.adminLight, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'Every question imported here is added to your $categoryLabel bank.',
                  style: const TextStyle(color: AppColors.admin, fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'Columns expected (first row is treated as a header and skipped):\n'
              'Subject · Topic · Question · Option A · Option B · Option C · Option D · Correct (A-D) · Difficulty',
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
              Text('${_rows!.length - 1} question rows detected', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              LoadingButton(label: 'Import into Question Bank', loading: _importing, onPressed: _import, color: AppColors.admin),
            ],
            if (_importedCount != null) ...[
              const SizedBox(height: 16),
              Text(
                _skippedRows.isEmpty
                    ? 'Imported $_importedCount questions successfully.'
                    : 'Imported $_importedCount questions. ${_skippedRows.length} row${_skippedRows.length == 1 ? '' : 's'} skipped.',
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
                    const SizedBox(height: 4),
                    const Text(
                      'Fix these rows in your file (make sure the Correct answer column has A, B, C or D) and re-upload, '
                      'or add them one at a time with "Add question" from the Question Bank screen.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
      ),
    );
  }
}
