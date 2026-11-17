import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/faculty.dart';
import '../../../models/student.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/department_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/home_back_button.dart';
import '../../../widgets/refresh_icon_button.dart';
import 'faculty_form_sheet.dart';
import 'student_form_sheet.dart';

/// Deck slide 07 — "Add, edit, import, activate/deactivate students;
/// assign faculty to departments and years."
class StudentsFacultyScreen extends ConsumerStatefulWidget {
  const StudentsFacultyScreen({super.key});

  @override
  ConsumerState<StudentsFacultyScreen> createState() => _StudentsFacultyScreenState();
}

class _StudentsFacultyScreenState extends ConsumerState<StudentsFacultyScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Students & Faculty'),
        leading: const HomeBackButton(homeRoute: '/admin'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            // Refresh both tabs' data regardless of which is active —
            // simpler and still correct than tracking the tab index here.
            ref.invalidate(allStudentsProvider);
            ref.invalidate(allFacultyProvider);
            await Future.wait([
              ref.read(allStudentsProvider.future),
              ref.read(allFacultyProvider.future),
            ]);
          }),
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'Import from file',
            onPressed: () => context.push(_tabController.index == 0 ? '/admin/people/import-students' : '/admin/people/import-faculty'),
          ),
        ],
        bottom: TabBar(controller: _tabController, labelColor: AppColors.admin, tabs: const [Tab(text: 'Students'), Tab(text: 'Faculty')]),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.admin,
        onPressed: () {
          if (_tabController.index == 0) {
            showAddStudentSheet(context, ref);
          } else {
            showAddFacultySheet(context, ref);
          }
        },
        child: const Icon(Icons.add_rounded),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_StudentsTab(), _FacultyTab()],
      ),
    );
  }
}

class _StudentsTab extends ConsumerWidget {
  const _StudentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(allStudentsProvider);
    return AsyncValueWidget<List<StudentProfile>>(
      value: studentsAsync,
      data: (students) {
        if (students.isEmpty) return const EmptyState(icon: Icons.school_outlined, title: 'No students yet');
        return RefreshIndicator(
          color: AppColors.admin,
          onRefresh: () {
            ref.invalidate(allStudentsProvider);
            return ref.read(allStudentsProvider.future);
          },
          child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
          itemCount: students.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final s = students[i];
            final dept = ref.watch(departmentByIdProvider(s.departmentId));
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${s.registerNumber} · ${dept?.code ?? ''} · Year ${s.year}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  Switch(
                    value: s.isActive,
                    activeThumbColor: AppColors.admin,
                    onChanged: (v) async {
                      try {
                        await ref.read(adminServiceProvider).setStudentActive(s.id, v);
                        ref.invalidate(allStudentsProvider);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
        );
      },
    );
  }
}

class _FacultyTab extends ConsumerWidget {
  const _FacultyTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facultyAsync = ref.watch(allFacultyProvider);
    return AsyncValueWidget<List<FacultyProfile>>(
      value: facultyAsync,
      data: (faculty) {
        if (faculty.isEmpty) return const EmptyState(icon: Icons.badge_outlined, title: 'No faculty yet');
        return RefreshIndicator(
          color: AppColors.admin,
          onRefresh: () {
            ref.invalidate(allFacultyProvider);
            return ref.read(allFacultyProvider.future);
          },
          child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
          itemCount: faculty.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final f = faculty[i];
            final dept = ref.watch(departmentByIdProvider(f.departmentId));
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${f.facultyId} · ${dept?.code ?? 'Unassigned'} · Years ${f.assignedYears.join(', ')}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  Switch(
                    value: f.isActive,
                    activeThumbColor: AppColors.admin,
                    onChanged: (v) async {
                      try {
                        await ref.read(adminServiceProvider).setFacultyActive(f.id, v);
                        ref.invalidate(allFacultyProvider);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
        );
      },
    );
  }
}
