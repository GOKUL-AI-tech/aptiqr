import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/app_date.dart';
import '../../../models/admin_profile.dart';
import '../../../models/app_profile.dart';
import '../../../models/test_category.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/refresh_icon_button.dart';

/// Deck slide 07/08 — "Admins manage the 3,000-question bank, students,
/// faculty, departments, and daily test configuration from one console."
///
/// Redesigned from a plain title + bordered grid into a gradient hero
/// header (matching the identity now used across every role's home
/// screen) and dashboard tiles with gradient icon badges + real shadow
/// depth instead of a flat 1px border, so the admin console doesn't look
/// visually disconnected from the rest of the app.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final adminAsync = ref.watch(currentAdminProvider);
    // recentTestsProvider is already scoped to this admin's own category
    // (see providers/admin_provider.dart), so "today's test" here only
    // ever means "today's test in *my* category".
    final testsAsync = ref.watch(recentTestsProvider);
    // AppDate.todayIst(), not DateTime.now() — see that class's doc
    // comment. recentTestsProvider has no date filter at all (it just
    // orders by test_date descending), so it happily lists a test dated
    // for the "wrong" day if this admin's device clock/timezone ever
    // disagrees with the college's actual IST calendar day — comparing
    // against the device's own DateTime.now() here would silently agree
    // with that wrong date instead of catching it.
    final today = AppDate.todayIst();
    final todayTest = testsAsync.valueOrNull?.where((t) {
      return t.testDate.year == today.year && t.testDate.month == today.month && t.testDate.day == today.day;
    }).toList();

    Future<void> onRefresh() {
      ref.invalidate(currentProfileProvider);
      ref.invalidate(currentAdminProvider);
      ref.invalidate(recentTestsProvider);
      return ref.read(recentTestsProvider.future);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Header(profileAsync: profileAsync, adminAsync: adminAsync, onRefresh: onRefresh),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (todayTest == null || todayTest.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No ${adminAsync.valueOrNull?.category.label ?? ''} test generated for today yet.',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/admin/daily-test'),
                          child: const Text('Generate'),
                        ),
                      ],
                    ),
                  ),
                if (todayTest == null || todayTest.isEmpty) const SizedBox(height: 20),
                const Text('Manage', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.25,
                  children: [
                    _DashCard(
                      icon: Icons.menu_book_rounded,
                      title: 'Question Bank',
                      subtitle: 'Upload, edit, filter',
                      color: AppColors.admin,
                      onTap: () => context.push('/admin/question-bank'),
                    ),
                    _DashCard(
                      icon: Icons.groups_rounded,
                      title: 'Students & Faculty',
                      subtitle: 'Add, import, manage',
                      color: AppColors.faculty,
                      onTap: () => context.push('/admin/people'),
                    ),
                    _DashCard(
                      icon: Icons.apartment_rounded,
                      title: 'Departments',
                      subtitle: 'AIML, CSE, IT, ECE...',
                      color: AppColors.primaryOrange,
                      onTap: () => context.push('/admin/departments'),
                    ),
                    _DashCard(
                      icon: Icons.qr_code_2_rounded,
                      title: 'Daily Test',
                      subtitle: 'Configure & generate',
                      color: AppColors.admin,
                      onTap: () => context.push('/admin/daily-test'),
                    ),
                    _DashCard(
                      icon: Icons.emoji_events_rounded,
                      title: 'Results',
                      subtitle: 'Publish & rankings',
                      color: AppColors.faculty,
                      onTap: () => context.push('/admin/results'),
                    ),
                    _DashCard(
                      icon: Icons.insights_rounded,
                      title: 'Reports & Analytics',
                      subtitle: 'Trends, attendance',
                      color: AppColors.primaryOrange,
                      onTap: () => context.push('/admin/reports'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AsyncValue<AppProfile?> profileAsync;
  final AsyncValue<AdminProfile?> adminAsync;
  final Future<void> Function() onRefresh;
  const _Header({required this.profileAsync, required this.adminAsync, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 26),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.admin, AppColors.adminDark],
          ),
        ),
        child: Stack(
          children: [
            Positioned(top: -50, right: -40, child: _blob(140, 0.09)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        // Category-scoped since each admin login only
                        // manages one track — see AdminProfile.category /
                        // README "Creating the Technical / Communication
                        // admin logins".
                        '${adminAsync.valueOrNull?.category.shortLabel ?? ''} ADMIN CONSOLE'.trim(),
                        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                      ),
                    ),
                    const Spacer(),
                    RefreshIconButton(onRefresh: onRefresh, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 12),
                profileAsync.when(
                  data: (p) => Text(
                    'Welcome, ${p?.fullName ?? 'Admin'}',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                  ),
                  loading: () => const SizedBox(height: 28),
                  error: (e, st) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 4),
                const Text('Full control over content and people', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(double size, double opacity) =>
      Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(opacity)));
}

class _DashCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DashCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: LinearGradient(colors: [color, color.withOpacity(0.75)]),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const Spacer(),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
            ],
          ),
        ),
      ),
    );
  }
}
