import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/attendance_row.dart';
import '../../../models/test_category.dart';
import '../../../providers/faculty_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/category_selector.dart';
import '../../../widgets/home_back_button.dart';
import '../../../widgets/loading_button.dart';
import '../../../widgets/refresh_icon_button.dart';

/// Deck slide 05 — "Download daily performance reports as Excel or PDF."
class FacultyReportsScreen extends ConsumerStatefulWidget {
  const FacultyReportsScreen({super.key});

  @override
  ConsumerState<FacultyReportsScreen> createState() => _FacultyReportsScreenState();
}

class _FacultyReportsScreenState extends ConsumerState<FacultyReportsScreen> {
  bool _generatingExcel = false;
  bool _generatingPdf = false;

  Future<void> _exportExcel(List<AttendanceRow> rows) async {
    setState(() => _generatingExcel = true);
    try {
      final label = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final category = ref.read(selectedFacultyCategoryProvider).label;
      final bytes = await ref.read(facultyServiceProvider).buildExcelReport(label, rows);
      final xFile = XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'aptiqr_report_$label.xlsx',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      await Share.shareXFiles([xFile], text: 'Daily $category Test report — $label');
    } catch (e) {
      // Previously uncaught — a failure here (file write, or the share
      // sheet itself, e.g. no app available to handle it) just stopped
      // the spinner with no explanation, looking like the button did
      // nothing at all.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not export the Excel report. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingExcel = false);
    }
  }

  Future<void> _exportPdf(List<AttendanceRow> rows) async {
    setState(() => _generatingPdf = true);
    try {
      final label = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final category = ref.read(selectedFacultyCategoryProvider).label;
      final bytes = await ref.read(facultyServiceProvider).buildPdfReport(label, rows);
      final xFile = XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'aptiqr_report_$label.pdf',
        mimeType: 'application/pdf',
      );
      await Share.shareXFiles([xFile], text: 'Daily $category Test report — $label');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not export the PDF report. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attendanceAsync = ref.watch(attendanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        leading: const HomeBackButton(homeRoute: '/faculty'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            ref.invalidate(attendanceProvider);
            await ref.read(attendanceProvider.future);
          }),
        ],
      ),
      body: Column(
        children: [
          const CategorySelector(),
          Expanded(
            child: AsyncValueWidget<List<AttendanceRow>>(
        value: attendanceAsync,
        data: (rows) {
          return RefreshIndicator(
            color: AppColors.faculty,
            onRefresh: () {
              ref.invalidate(attendanceProvider);
              return ref.read(attendanceProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Today\'s report', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  '${rows.length} students in your department · ${ref.watch(selectedFacultyCategoryProvider).label}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                LoadingButton(
                  label: 'Download as Excel',
                  loading: _generatingExcel,
                  onPressed: rows.isEmpty ? null : () => _exportExcel(rows),
                ),
                const SizedBox(height: 12),
                LoadingButton(
                  label: 'Download as PDF',
                  loading: _generatingPdf,
                  onPressed: rows.isEmpty ? null : () => _exportPdf(rows),
                  color: AppColors.faculty,
                ),
              ],
            ),
          );
        },
            ),
          ),
        ],
      ),
    );
  }
}
