import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/department_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/home_back_button.dart';
import '../../../widgets/profile_header.dart';
import '../../../widgets/profile_info_card.dart';
import '../../../widgets/refresh_icon_button.dart';

class FacultyProfileScreen extends ConsumerWidget {
  const FacultyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facultyAsync = ref.watch(currentFacultyProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
        leading: const HomeBackButton(homeRoute: '/faculty'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            ref.invalidate(currentProfileProvider);
            ref.invalidate(currentFacultyProvider);
            await ref.read(currentFacultyProvider.future);
          }),
        ],
      ),
      body: AsyncValueWidget(
        value: facultyAsync,
        data: (faculty) {
          if (faculty == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_off_outlined, size: 48, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    const Text('Profile not found', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text(
                      'This account has no faculty record. If you meant to sign in as student or admin, sign out and check that account\'s role.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () => ref.read(authServiceProvider).signOut(),
                      icon: const Icon(Icons.logout_rounded, color: AppColors.error),
                      label: const Text('Sign out', style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              ),
            );
          }
          final dept = ref.watch(departmentByIdProvider(faculty.departmentId));
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              ProfileHeader(role: 'faculty', name: faculty.fullName, subtitle: faculty.facultyId),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProfileInfoCard(
                      role: 'faculty',
                      items: [
                        ProfileInfoItem(icon: Icons.apartment_rounded, label: 'Department', value: dept?.name ?? '—'),
                        ProfileInfoItem(icon: Icons.school_rounded, label: 'Assigned years', value: faculty.assignedYears.join(', ')),
                        if (faculty.email != null) ProfileInfoItem(icon: Icons.email_rounded, label: 'Email', value: faculty.email!),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.facultyLight, width: 1.4),
                          backgroundColor: AppColors.facultyLight,
                        ),
                        onPressed: () => context.push('/faculty/import-students'),
                        icon: const Icon(Icons.upload_file_rounded, color: AppColors.faculty),
                        label: const Text('Import students', style: TextStyle(color: AppColors.faculty, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.errorLight, width: 1.4),
                          backgroundColor: AppColors.errorLight,
                        ),
                        onPressed: () => ref.read(authServiceProvider).signOut(),
                        icon: const Icon(Icons.logout_rounded, color: AppColors.error),
                        label: const Text('Sign out', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
