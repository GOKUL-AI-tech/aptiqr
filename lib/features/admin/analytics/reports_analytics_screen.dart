import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/daily_test.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/department_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/home_back_button.dart';
import '../../../widgets/refresh_icon_button.dart';

/// Deck slide 07 — "Daily, weekly, monthly and student performance
/// reports, plus attendance and score trends."
class ReportsAnalyticsScreen extends ConsumerStatefulWidget {
  const ReportsAnalyticsScreen({super.key});

  @override
  ConsumerState<ReportsAnalyticsScreen> createState() => _ReportsAnalyticsScreenState();
}

class _ReportsAnalyticsScreenState extends ConsumerState<ReportsAnalyticsScreen> {
  DailyTest? _selected;
  String? _departmentId;

  @override
  Widget build(BuildContext context) {
    final testsAsync = ref.watch(recentTestsProvider);
    final departmentsAsync = ref.watch(departmentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        leading: const HomeBackButton(homeRoute: '/admin'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            ref.invalidate(recentTestsProvider);
            ref.invalidate(departmentsProvider);
            await ref.read(recentTestsProvider.future);
          }),
        ],
      ),
      body: AsyncValueWidget<List<DailyTest>>(
        value: testsAsync,
        data: (tests) {
          if (tests.isEmpty) return const EmptyState(icon: Icons.analytics_outlined, title: 'No data yet');
          _selected ??= tests.first;
          final departments = departmentsAsync.valueOrNull ?? [];

          return RefreshIndicator(
            color: AppColors.admin,
            onRefresh: () {
              ref.invalidate(recentTestsProvider);
              ref.invalidate(departmentsProvider);
              return ref.read(recentTestsProvider.future);
            },
            child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              DropdownButtonFormField<DailyTest>(
                value: tests.contains(_selected) ? _selected : tests.first,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Test date'),
                items: tests.map((t) => DropdownMenuItem(value: t, child: Text(DateFormat('MMM d, yyyy').format(t.testDate)))).toList(),
                onChanged: (v) => setState(() => _selected = v),
              ),
              const SizedBox(height: 12),
              // Optional narrowing by department — defaults to every
              // department combined (null) so this is additive, not a
              // second required filter someone has to remember to set.
              // isExpanded: true is required here — without it a
              // DropdownButtonFormField sizes itself to its widest item
              // with no width cap, and full department names ("Artificial
              // Intelligence & Machine Learning (AI&ML)") run past the
              // field's edge, producing a RenderFlex right-overflow
              // banner instead of wrapping/truncating.
              DropdownButtonFormField<String?>(
                value: _departmentId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Department'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All departments')),
                  ...departments.map((d) => DropdownMenuItem<String?>(
                        value: d.id,
                        child: Text('${d.name} (${d.code})', overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _departmentId = v),
              ),
              const SizedBox(height: 20),
              if (_selected != null) _AnalyticsBody(test: _selected!, departmentId: _departmentId),
              const SizedBox(height: 24),
              Text('Attendance trend (last ${tests.length} tests)', style: Theme.of(context).textTheme.titleMedium),
              // With only a handful of days of data, a single skinny bar
              // surrounded by mostly empty space reads as "this is
              // broken" rather than "this is what a 1-3 day trend
              // legitimately looks like" — this caption is the
              // difference between the two, without hiding the real
              // (if sparse) data underneath it.
              if (tests.length < 4) ...[
                const SizedBox(height: 4),
                Text(
                  'Trend gets more meaningful after a few more days of tests.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(height: 220, child: _TrendChart(tests: tests, departmentId: _departmentId)),
            ],
          ),
          );
        },
      ),
    );
  }
}

class _AnalyticsBody extends ConsumerWidget {
  final DailyTest test;
  final String? departmentId;
  const _AnalyticsBody({required this.test, this.departmentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = ref.watch(adminServiceProvider).fetchAnalyticsSummary(test.id, departmentId: departmentId);
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        return Row(
          children: [
            Expanded(child: _StatBox(label: 'Submitted', value: '${data['submitted']}', color: AppColors.success)),
            const SizedBox(width: 10),
            Expanded(child: _StatBox(label: 'Absent', value: '${data['absent']}', color: AppColors.absent)),
            const SizedBox(width: 10),
            Expanded(child: _StatBox(label: 'Avg. score', value: (data['avgScore'] as double).toStringAsFixed(1), color: AppColors.admin)),
          ],
        );
      },
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBox({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

class _TrendChart extends ConsumerWidget {
  final List<DailyTest> tests;
  final String? departmentId;
  const _TrendChart({required this.tests, this.departmentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordered = tests.reversed.take(14).toList();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Future.wait(ordered.map((t) => ref.read(adminServiceProvider).fetchAnalyticsSummary(t.id, departmentId: departmentId))),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final results = snapshot.data!;

        // "Submitted" is a headcount — it should only ever show whole
        // numbers on the axis. fl_chart's default left-axis auto-scales
        // ticks off the data's max value with no notion of "this is a
        // count, not a continuous quantity", so with a small max (e.g. a
        // single test with 1 submission) it was drawing evenly-spaced
        // *fractional* ticks (0, 0.2, 0.4, 0.6, 0.8, 1) — nonsensical for
        // a metric that can't actually be 0.4 of a student. maxY/interval
        // are now computed explicitly from the real data so the axis
        // always lands on whole numbers, and getTitlesWidget below drops
        // any tick fl_chart still generates that isn't a whole number.
        final maxSubmitted = results.fold<int>(0, (m, r) => (r['submitted'] as int) > m ? r['submitted'] as int : m);
        final maxY = maxSubmitted < 1 ? 1 : maxSubmitted;
        final interval = (maxY / 5).ceil().clamp(1, maxY).toDouble();

        return BarChart(
          BarChartData(
            maxY: maxY.toDouble(),
            // A single bar surrounded by featureless white space reads as
            // "nothing rendered" rather than "a chart with one data point
            // so far". Gridlines are purely visual scaffolding — they
            // don't carry number labels (those come from leftTitles
            // below, independently) — so this can safely use a much
            // finer spacing than the label interval without reintroducing
            // the fractional-label bug. Using the *label* interval here
            // (the first attempt) was the mistake: with maxY=1 that only
            // draws a line at 0 and at 1, i.e. exactly on top of the
            // chart's own top/bottom edge — invisible, not "gone".
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (value) => FlLine(color: AppColors.border, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              // Each bar is one test date — previously unlabeled, so there
              // was no way to tell which day a given bar was without
              // cross-referencing the "Test date" dropdown above. `ordered`
              // (this chart's own reversed/take(14) list) and `results`
              // (the fetched stats) are built from the same index, so
              // `value.toInt()` safely indexes into `ordered` here too.
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= ordered.length) return const SizedBox.shrink();
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text(
                        DateFormat('MMM d\nyyyy').format(ordered[idx].testDate),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary, height: 1.2),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: interval,
                  getTitlesWidget: (value, meta) {
                    if (value != value.roundToDouble()) return const SizedBox.shrink();
                    return Text('${value.toInt()}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary));
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: [
              for (int i = 0; i < results.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(toY: (results[i]['submitted'] as int).toDouble(), color: AppColors.admin, width: 12, borderRadius: BorderRadius.circular(4)),
                ]),
            ],
          ),
        );
      },
    );
  }
}
