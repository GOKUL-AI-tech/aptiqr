import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/daily_test.dart';
import '../../../providers/faculty_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/refresh_icon_button.dart';
import '../../../widgets/test_qr_card.dart';

/// Deck slide 05 — "Today's QR: view, download and share the day's
/// test QR code with students."
///
/// A day can now have up to 3 daily tests — one per category (Aptitude/
/// Technical/Communication), each generated independently by its own
/// admin login (see supabase/schema.sql's (test_date, category) unique
/// constraint). This screen shows one QR card per test that's actually
/// been generated so far, each carrying a clear category badge so
/// faculty (and, once shared, students) can tell at a glance which QR
/// unlocks which subject's test — previously this screen assumed
/// exactly one test/QR existed for the whole day.
class TodayQrScreen extends ConsumerWidget {
  const TodayQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testsAsync = ref.watch(facultyTodayTestsProvider);

    Future<void> onRefresh() {
      ref.invalidate(facultyTodayTestsProvider);
      return ref.read(facultyTodayTestsProvider.future);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AsyncValueWidget<List<DailyTest>>(
        value: testsAsync,
        data: (tests) {
          if (tests.isEmpty) {
            return const EmptyState(
              icon: Icons.qr_code_2_rounded,
              title: 'No tests scheduled today',
              subtitle: 'Ask an admin to generate today\'s Aptitude/Technical/Communication test.',
            );
          }
          return RefreshIndicator(
            color: AppColors.faculty,
            // See student_home_screen.dart's onRefresh for why this
            // needs to actually await the refetch, not just invalidate.
            onRefresh: onRefresh,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _Header(onRefresh: onRefresh),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: Column(
                    children: [
                      for (int i = 0; i < tests.length; i++) ...[
                        if (i > 0) const SizedBox(height: 28),
                        TestQrCard(test: tests[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _Header({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 16, 24, 22),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.faculty, AppColors.facultyDark],
          ),
        ),
        child: Stack(
          children: [
            Positioned(top: -40, right: -30, child: _blob(120, 0.10)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('TODAY\'S QRs', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                    ),
                    RefreshIconButton(onRefresh: onRefresh, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Show these to your class',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Each subject has its own QR below — students scan the one for the test they\'re taking.',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
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

