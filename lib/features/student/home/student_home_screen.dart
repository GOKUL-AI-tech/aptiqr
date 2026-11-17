import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/connectivity_service.dart';
import '../../../models/daily_test.dart';
import '../../../models/student.dart';
import '../../../models/test_attempt.dart';
import '../../../models/test_category.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/refresh_icon_button.dart';

/// Deck slide 09 — "Login & Home: sign in with register number and see
/// today's test window, question count and duration."
///
/// Redesigned from a plain AppBar + stacked Text + generic Card into a
/// real hero header (gradient greeting banner) and a today's-test card
/// with an accent strip, icon-badge stats, and a pill status chip with a
/// live dot — this is the screen a student opens every single day, so
/// it's the highest-leverage place for this app to actually look cared
/// about rather than just functional.
class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);
    final testsAsync = ref.watch(todayTestsProvider);
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;

    // Shared by both the pull-to-refresh gesture below and the explicit
    // refresh button in the header — this screen has no AppBar (custom
    // gradient hero header instead), so pull-to-refresh was the only way
    // to reload it, easy to miss since nothing on screen hints it exists.
    Future<void> onRefresh() {
      ref.invalidate(todayTestsProvider);
      return ref.read(todayTestsProvider.future);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        // Was invalidate-then-return with no await — the pull-to-refresh
        // spinner disappeared the instant this ran, before the actual
        // refetch had come back, so the screen still showed stale data
        // for a beat after the spinner already stopped. That's what
        // reads as "refresh feels slow/broken": no feedback covers the
        // real wait, it just happens invisibly right after.
        onRefresh: onRefresh,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _Header(studentAsync: studentAsync, isOnline: isOnline, onRefresh: onRefresh),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: AsyncValueWidget<List<DailyTest>>(
                value: testsAsync,
                // Up to 3 tests today (Aptitude/Technical/Communication) —
                // one card per test the admins have generated so far,
                // instead of the old single "today's test" assumption.
                data: (tests) => tests.isEmpty
                    ? const _NoTestCard()
                    : Column(
                        children: [
                          for (int i = 0; i < tests.length; i++) ...[
                            if (i > 0) const SizedBox(height: 16),
                            _TodayTestCard(test: tests[i]),
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AsyncValue<StudentProfile?> studentAsync;
  final bool isOnline;
  final Future<void> Function() onRefresh;
  const _Header({required this.studentAsync, required this.isOnline, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryOrange, AppColors.primaryOrangeDark],
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
                    Expanded(
                      child: Text(greeting, style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                    if (!isOnline) ...[const _OfflineBadge(), const SizedBox(width: 4)],
                    RefreshIconButton(onRefresh: onRefresh, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 6),
                studentAsync.when(
                  data: (s) => Text(
                    '${s?.fullName.split(' ').first ?? 'Student'} 👋',
                    style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                  ),
                  loading: () => const SizedBox(height: 30),
                  error: (e, st) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 8),
                studentAsync.when(
                  data: (s) => s == null
                      ? const SizedBox.shrink()
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(20)),
                          child: Text(
                            '${s.registerNumber} · Year ${s.year}${s.section != null ? ' · Sec ${s.section}' : ''}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                  loading: () => const SizedBox.shrink(),
                  error: (e, st) => const SizedBox.shrink(),
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

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 13, color: Colors.white),
          SizedBox(width: 4),
          Text('Offline', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _NoTestCard extends StatelessWidget {
  const _NoTestCard();
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
              child: const Icon(Icons.event_busy_rounded, size: 34, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            const Text('No test scheduled for today', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            const Text(
              'Check back once your admin publishes today\'s test.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayTestCard extends ConsumerWidget {
  final DailyTest test;
  const _TodayTestCard({required this.test});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptAsync = ref.watch(myAttemptProvider(test.id));
    final now = DateTime.now();
    final timeFmt = DateFormat('h:mm a');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Accent strip — gives the card a focal point/color instead of
          // being an undifferentiated white rectangle like every other
          // card on the screen.
          Container(
            height: 6,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.primaryOrange, AppColors.primaryOrangeDark]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Today\'s ${test.category.label} Test', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    _StatusChip(test: test),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: _InfoStat(icon: Icons.help_outline_rounded, label: 'Questions', value: '${test.questionCount}')),
                    const SizedBox(width: 12),
                    Expanded(child: _InfoStat(icon: Icons.timer_outlined, label: 'Duration', value: '${test.durationMinutes} min')),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 15, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${timeFmt.format(test.openTime)} – ${timeFmt.format(test.closeTime)}  ·  Results at ${timeFmt.format(test.resultsTime)}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                attemptAsync.when(
                  data: (attempt) => _ActionButton(test: test, attempt: attempt, now: now),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, st) => Text('$e', style: const TextStyle(color: AppColors.error)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final DailyTest test;
  const _StatusChip({required this.test});

  @override
  Widget build(BuildContext context) {
    final open = test.isOpenNow;
    final color = open ? AppColors.success : AppColors.textSecondary;
    final label = open ? 'Open now' : (DateTime.now().isBefore(test.openTime) ? 'Opens soon' : 'Closed');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _InfoStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoStat({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.primaryOrangeLight, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primaryOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final DailyTest test;
  final TestAttempt? attempt;
  final DateTime now;
  const _ActionButton({required this.test, required this.attempt, required this.now});

  @override
  Widget build(BuildContext context) {
    if (attempt != null && attempt!.status == AttemptStatus.submitted) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => context.push('/student/result/${test.id}'),
          icon: const Icon(Icons.emoji_events_outlined),
          label: const Text('View Result'),
        ),
      );
    }

    if (attempt != null && attempt!.status == AttemptStatus.inProgress) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.push('/student/test/${test.id}/question'),
          child: const Text('Continue Test'),
        ),
      );
    }

    if (attempt != null && attempt!.status == AttemptStatus.absent) {
      // Reached when the student never started today's test at all and
      // results have already been published — publish_results backfills
      // a no-show 'absent' row for them (see supabase/functions.sql).
      // By the time results are published, the test's close_time has
      // long passed, so there's nothing useful "Start Test" could do here
      // anyway. (Leaving the app mid-test no longer lands here — that now
      // auto-submits whatever was answered instead; see
      // StudentService.autoSubmitOnExit.)
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.block_rounded),
          label: const Text('Attempt forfeited for today'),
        ),
      );
    }

    final canStart = test.isOpenNow;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canStart ? () => context.push('/student/test/${test.id}/instructions') : null,
        child: Text(canStart ? 'Start Test' : 'Not open yet'),
      ),
    );
  }
}
