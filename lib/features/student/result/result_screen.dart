import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/daily_test.dart';
import '../../../models/test_attempt.dart';
import '../../../models/test_category.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/home_back_button.dart';
import '../../../widgets/refresh_icon_button.dart';

/// Deck slide 09 — "Instant score, then overall/department/year rank
/// once results publish at 3 PM."
///
/// A day can now have up to 3 tests (Aptitude/Technical/Communication —
/// see supabase/schema.sql), so "today's result" is no longer a single
/// thing. This screen (the bottom-nav "Result" tab) is now a list of
/// today's tests with a quick status/score per category; tapping one
/// pushes [ResultDetailScreen] — the original single-test result view,
/// now keyed by testId (see /student/result/:testId in app_router.dart).
class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testsAsync = ref.watch(todayTestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today\'s Results'),
        leading: const HomeBackButton(homeRoute: '/student'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            ref.invalidate(todayTestsProvider);
            await ref.read(todayTestsProvider.future);
          }),
        ],
      ),
      body: AsyncValueWidget<List<DailyTest>>(
        value: testsAsync,
        data: (tests) {
          if (tests.isEmpty) return const EmptyState(icon: Icons.event_busy_rounded, title: 'No test today');
          return RefreshIndicator(
            color: AppColors.primaryOrange,
            onRefresh: () {
              // See student_home_screen.dart — invalidate alone doesn't
              // wait for the refetch, so the spinner used to stop before
              // the list actually had fresh data.
              ref.invalidate(todayTestsProvider);
              return ref.read(todayTestsProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: tests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _TestResultTile(test: tests[i]),
            ),
          );
        },
      ),
    );
  }
}

class _TestResultTile extends ConsumerWidget {
  final DailyTest test;
  const _TestResultTile({required this.test});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptAsync = ref.watch(myAttemptProvider(test.id));
    final accent = test.category.accent;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/student/result/${test.id}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: accent.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(test.category.icon, color: accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(test.category.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  attemptAsync.when(
                    data: (attempt) => Text(
                      attempt == null || attempt.status != AttemptStatus.submitted
                          ? 'Not submitted yet'
                          : 'Score: ${attempt.score ?? 0} / ${attempt.totalQuestions ?? test.questionCount}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                    loading: () => const Text('Loading…', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                    error: (e, st) => const Text('—', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// The original single-test result view (score, ranking, top scores),
/// now reached at /student/result/:testId instead of assuming there was
/// only ever one test for the whole day.
class ResultDetailScreen extends ConsumerWidget {
  final String testId;
  const ResultDetailScreen({super.key, required this.testId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testAsync = ref.watch(testByIdProvider(testId));

    return Scaffold(
      // This is reached both by pushing from Home/the results list (where
      // a normal back arrow would already work) and via context.go() right
      // after submitting a test (see TestReviewScreen._submit) — .go()
      // replaces the route stack entirely, so Navigator.canPop is false
      // and Flutter's automatic back arrow never appears in that case,
      // stranding the student with no way back. HomeBackButton always
      // goes to /student regardless of how this screen was reached.
      appBar: AppBar(
        title: const Text('Result'),
        leading: const HomeBackButton(homeRoute: '/student'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            ref.invalidate(testByIdProvider(testId));
            ref.invalidate(myAttemptProvider(testId));
            ref.invalidate(myRankingProvider(testId));
            ref.invalidate(topScoresProvider(testId));
            await ref.read(testByIdProvider(testId).future);
          }),
        ],
      ),
      body: AsyncValueWidget<DailyTest?>(
        value: testAsync,
        data: (test) {
          if (test == null) return const EmptyState(icon: Icons.event_busy_rounded, title: 'Test not found');
          return _ResultBody(test: test);
        },
      ),
    );
  }
}

class _ResultBody extends ConsumerWidget {
  final DailyTest test;
  const _ResultBody({required this.test});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptAsync = ref.watch(myAttemptProvider(test.id));
    final rankingAsync = ref.watch(myRankingProvider(test.id));
    final topScoresAsync = ref.watch(topScoresProvider(test.id));

    return attemptAsync.when(
      data: (attempt) {
        if (attempt == null || attempt.status != AttemptStatus.submitted) {
          return const EmptyState(
            icon: Icons.hourglass_empty_rounded,
            title: 'No submission yet',
            subtitle: 'Take today\'s test from the Home tab to see your result here.',
          );
        }
        return RefreshIndicator(
          color: AppColors.primaryOrange,
          onRefresh: () async {
            ref.invalidate(myAttemptProvider(test.id));
            ref.invalidate(myRankingProvider(test.id));
            ref.invalidate(topScoresProvider(test.id));
            // Previously only awaited myAttemptProvider — the spinner
            // stopped as soon as that one came back even though ranking/
            // topScores could still be mid-fetch, so the rank/top-score
            // section on screen could visibly pop in a moment after the
            // pull-to-refresh gesture had already finished.
            await Future.wait([
              ref.read(myAttemptProvider(test.id).future),
              ref.read(myRankingProvider(test.id).future),
              ref.read(topScoresProvider(test.id).future),
            ]);
          },
          child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(test.category.label, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text('Your Score', style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Text(
                      '${attempt.score ?? 0} / ${attempt.totalQuestions ?? test.questionCount}',
                      style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: AppColors.primaryOrange),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Ranking', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            rankingAsync.when(
              data: (rank) {
                if (!test.resultsPublished || rank == null) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: const [
                          Icon(Icons.schedule_rounded, color: AppColors.textSecondary),
                          SizedBox(width: 12),
                          Expanded(child: Text('Rankings publish once results go live. Check back soon.')),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _RankTile(label: 'Overall', value: rank.rankOverall)),
                        const SizedBox(width: 10),
                        Expanded(child: _RankTile(label: 'Department', value: rank.rankDepartment)),
                        const SizedBox(width: 10),
                        Expanded(child: _RankTile(label: 'Year', value: rank.rankYear)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('Top scores', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    topScoresAsync.when(
                      data: (top) => Row(
                        children: [
                          Expanded(
                            child: _TopScoreTile(
                              label: 'Overall top',
                              score: top['overallTop'],
                              total: test.questionCount,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _TopScoreTile(
                              label: 'Department top',
                              score: top['departmentTop'],
                              total: test.questionCount,
                            ),
                          ),
                        ],
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (e, st) => Text('$e', style: const TextStyle(color: AppColors.error)),
                    ),
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, st) => Text('$e', style: const TextStyle(color: AppColors.error)),
            ),
          ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('$e', style: const TextStyle(color: AppColors.error))),
    );
  }
}

class _RankTile extends StatelessWidget {
  final String label;
  final int? value;
  const _RankTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Text(value == null ? '—' : '#$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// The highest score achieved on this test — overall, or within the
/// student's own department. `score` is null only if rankings for this
/// test haven't been generated yet (shouldn't normally happen here since
/// this is only shown once `test.resultsPublished` is true, but a dash
/// is safer than a crash if publish_results hasn't run for some reason).
class _TopScoreTile extends StatelessWidget {
  final String label;
  final int? score;
  final int total;
  const _TopScoreTile({required this.label, required this.score, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(color: AppColors.primaryOrangeLight, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          const Icon(Icons.emoji_events_rounded, color: AppColors.primaryOrange, size: 20),
          const SizedBox(height: 6),
          Text(
            score == null ? '—' : '$score / $total',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primaryOrangeDark),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppColors.primaryOrangeDark, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
