import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/test_category.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/home_back_button.dart';
import '../../../widgets/profile_header.dart';
import '../../../widgets/refresh_icon_button.dart';

class AdminProfileScreen extends ConsumerWidget {
  const AdminProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final adminAsync = ref.watch(currentAdminProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
        leading: const HomeBackButton(homeRoute: '/admin'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            ref.invalidate(currentProfileProvider);
            ref.invalidate(currentAdminProvider);
            await ref.read(currentProfileProvider.future);
          }),
        ],
      ),
      body: AsyncValueWidget(
        value: profileAsync,
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_off_outlined, size: 48, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    const Text('Profile not found', style: TextStyle(fontWeight: FontWeight.w600)),
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
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              ProfileHeader(role: 'admin', name: profile.fullName, subtitle: profile.email),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    adminAsync.when(
                      data: (admin) => admin == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(color: AppColors.adminLight, borderRadius: BorderRadius.circular(14)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.category_rounded, color: AppColors.admin, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'You manage: ${admin.category.label} questions & daily test',
                                        style: const TextStyle(color: AppColors.admin, fontWeight: FontWeight.w600, fontSize: 12.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      loading: () => const SizedBox.shrink(),
                      error: (e, st) => const SizedBox.shrink(),
                    ),
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
