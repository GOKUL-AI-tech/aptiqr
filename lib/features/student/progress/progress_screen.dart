import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/test_attempt.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/home_back_button.dart';
import '../../../widgets/refresh_icon_button.dart';

/// Deck slide 09 — "Previous results, performance report with accuracy
/// and subject-wise trends."
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(myAttemptHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
        leading: const HomeBackButton(homeRoute: '/student'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            ref.invalidate(myAttemptHistoryProvider);
            await ref.read(myAttemptHistoryProvider.future);
          }),
        ],
      ),
      body: AsyncValueWidget<List<TestAttempt>>(
        value: historyAsync,
        data: (attempts) {
          if (attempts.isEmpty) {
            return const EmptyState(
              icon: Icons.insights_outlined,
              title: 'No results yet',
              subtitle: 'Your performance trend will show up here after your first submitted test.',
            );
          }
          final ordered = attempts.reversed.toList(); // oldest -> newest for the chart
          final avgAccuracy = attempts
                  .map((a) => (a.totalQuestions ?? 0) == 0 ? 0 : (a.score ?? 0) / (a.totalQuestions ?? 1))
                  .fold<double>(0, (sum, v) => sum + v) /
              attempts.length;

          return RefreshIndicator(
            color: AppColors.primaryOrange,
            onRefresh: () {
              ref.invalidate(myAttemptHistoryProvider);
              return ref.read(myAttemptHistoryProvider.future);
            },
            child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(child: _StatCard(label: 'Tests taken', value: '${attempts.length}')),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: 'Avg. accuracy', value: '${(avgAccuracy * 100).toStringAsFixed(0)}%')),
                ],
              ),
              const SizedBox(height: 20),
              Text('Score trend', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Accuracy per test, oldest to newest',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: LineChart(
                  LineChartData(
                    // Previously plotted the raw `score` (e.g. "1 correct
                    // answer") against an auto-scaled y-axis that fl_chart
                    // derives from the data range — with only small
                    // integer scores like 0 and 1, that auto-range
                    // happened to land on 0..1 with 0.2 gridlines, which
                    // LOOKS exactly like a 0-100% accuracy chart but
                    // isn't one, and disagreed with the correctly-computed
                    // "Avg. accuracy" stat card right above it. Plotting
                    // actual per-test accuracy (score/totalQuestions*100)
                    // on a fixed, labeled 0-100 axis instead makes the
                    // chart match that stat and be self-explanatory
                    // without cross-referencing the History list below.
                    minY: 0,
                    maxY: 100,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 25,
                      getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final i = value.round();
                            if (i < 0 || i >= ordered.length) return const SizedBox.shrink();
                            final date = ordered[i].submittedAt;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                date == null ? '—' : DateFormat('M/d').format(date),
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          interval: 25,
                          getTitlesWidget: (value, meta) => Text(
                            '${value.toInt()}%',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots.map((s) {
                          final i = s.x.round();
                          final a = ordered[i];
                          return LineTooltipItem(
                            '${a.score ?? 0}/${a.totalQuestions ?? 0} · ${s.y.toStringAsFixed(0)}%',
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                          );
                        }).toList(),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (int i = 0; i < ordered.length; i++)
                            FlSpot(
                              i.toDouble(),
                              (ordered[i].totalQuestions ?? 0) == 0
                                  ? 0
                                  : (ordered[i].score ?? 0) / (ordered[i].totalQuestions ?? 1) * 100,
                            ),
                        ],
                        isCurved: true,
                        color: AppColors.primaryOrange,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(show: true, color: AppColors.primaryOrangeLight),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('History', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...attempts.map((a) => _HistoryTile(attempt: a)),
            ],
          ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final TestAttempt attempt;
  const _HistoryTile({required this.attempt});

  @override
  Widget build(BuildContext context) {
    final date = attempt.submittedAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Text(date == null ? '—' : DateFormat('MMM d, yyyy').format(date)),
            const Spacer(),
            Text('${attempt.score ?? 0}/${attempt.totalQuestions ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
