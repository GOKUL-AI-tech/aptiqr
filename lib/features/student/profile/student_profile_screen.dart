import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/department_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/home_back_button.dart';
import '../../../widgets/profile_header.dart';
import '../../../widgets/profile_info_card.dart';
import '../../../widgets/refresh_icon_button.dart';

class StudentProfileScreen extends ConsumerWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
        leading: const HomeBackButton(homeRoute: '/student'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            ref.invalidate(currentProfileProvider);
            ref.invalidate(currentStudentProvider);
            await ref.read(currentStudentProvider.future);
          }),
        ],
      ),
      body: AsyncValueWidget(
        value: studentAsync,
        data: (student) {
          if (student == null) {
            // No matching row in `students` for this account — most likely
            // it's actually a faculty/admin account that ended up here
            // because `profiles.role` wasn't set correctly. Always leave a
            // way to sign out rather than stranding the user.
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
                      'This account has no student record. If you meant to sign in as faculty or admin, sign out and check that account\'s role.',
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
          final dept = ref.watch(departmentByIdProvider(student.departmentId));
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              ProfileHeader(
                role: 'student',
                name: student.fullName,
                subtitle: '${student.registerNumber} · Year ${student.year}${student.section != null ? ' · Sec ${student.section}' : ''}',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProfileInfoCard(
                      role: 'student',
                      items: [
                        ProfileInfoItem(icon: Icons.apartment_rounded, label: 'Department', value: dept?.name ?? '—'),
                        ProfileInfoItem(icon: Icons.calendar_today_rounded, label: 'Year', value: 'Year ${student.year}'),
                        if (student.section != null)
                          ProfileInfoItem(icon: Icons.groups_rounded, label: 'Section', value: student.section!),
                        if (student.email != null)
                          ProfileInfoItem(icon: Icons.email_rounded, label: 'Email', value: student.email!),
                      ],
                    ),
                    const SizedBox(height: 24),
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
