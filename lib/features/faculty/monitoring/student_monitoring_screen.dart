import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/attendance_row.dart';
import '../../../models/test_attempt.dart';
import '../../../providers/faculty_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/category_selector.dart';
import '../../../widgets/home_back_button.dart';
import '../../../widgets/refresh_icon_button.dart';

/// Deck slide 05/06 — "Track attendance, completed, pending and absent
/// students — filtered by department, year, section or date."
/// (Department filtering happens automatically via RLS — faculty only
/// ever see their own department's students.)
class StudentMonitoringScreen extends ConsumerWidget {
  const StudentMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(attendanceProvider);
    final filter = ref.watch(attendanceFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Monitoring'),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    value: filter.year,
                    decoration: const InputDecoration(labelText: 'Year', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All years')),
                      ...AppConstants.years.map((y) => DropdownMenuItem(value: y, child: Text('Year $y'))),
                    ],
                    onChanged: (v) => ref.read(attendanceFilterProvider.notifier).state = AttendanceFilter(year: v, section: filter.section),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: filter.section,
                    decoration: const InputDecoration(labelText: 'Section', isDense: true, hintText: 'e.g. A'),
                    onChanged: (v) => ref.read(attendanceFilterProvider.notifier).state = AttendanceFilter(year: filter.year, section: v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncValueWidget<List<AttendanceRow>>(
              value: attendanceAsync,
              data: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(icon: Icons.groups_outlined, title: 'No students found for these filters');
                }
                final completed = rows.where((r) => r.attempt.status == AttemptStatus.submitted).length;
                final pending = rows.where((r) => r.attempt.status == AttemptStatus.inProgress || r.attempt.status == AttemptStatus.notStarted).length;
                final absent = rows.where((r) => r.attempt.status == AttemptStatus.absent).length;

                return RefreshIndicator(
                  color: AppColors.faculty,
                  onRefresh: () {
                    ref.invalidate(attendanceProvider);
                    return ref.read(attendanceProvider.future);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      Row(
                        children: [
                          Expanded(child: _CountChip(label: 'Completed', count: completed, color: AppColors.success)),
                          const SizedBox(width: 8),
                          Expanded(child: _CountChip(label: 'Pending', count: pending, color: AppColors.warning)),
                          const SizedBox(width: 8),
                          Expanded(child: _CountChip(label: 'Absent', count: absent, color: AppColors.absent)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...rows.map((r) => _StudentRow(row: r)),
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

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CountChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  final AttendanceRow row;
  const _StudentRow({required this.row});

  Color _statusColor(AttemptStatus status) {
    switch (status) {
      case AttemptStatus.submitted:
        return AppColors.success;
      case AttemptStatus.absent:
        return AppColors.absent;
      default:
        return AppColors.warning;
    }
  }

  String _statusLabel(AttemptStatus status) {
    switch (status) {
      case AttemptStatus.submitted:
        return 'Completed';
      case AttemptStatus.absent:
        return 'Absent';
      case AttemptStatus.inProgress:
        return 'In progress';
      case AttemptStatus.notStarted:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(row.attempt.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.studentName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${row.registerNumber} · Year ${row.year}${row.section != null ? ' · ${row.section}' : ''}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(_statusLabel(row.attempt.status), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
