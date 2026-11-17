import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../models/daily_test.dart';
import '../../models/test_category.dart';
import '../../providers/admin_provider.dart';
import '../../providers/faculty_provider.dart';
import '../../services/insights_service.dart';
import '../../widgets/async_value_widget.dart';
import '../../widgets/category_selector.dart';

final insightsServiceProvider = Provider<InsightsService>((ref) => InsightsService());

final atRiskProvider = FutureProvider.autoDispose<List<Json>>((ref) => ref.watch(insightsServiceProvider).atRisk());
final topicHeatmapProvider = FutureProvider.autoDispose<List<Json>>((ref) => ref.watch(insightsServiceProvider).topicHeatmap());
final trendProvider = FutureProvider.autoDispose<List<Json>>((ref) => ref.watch(insightsServiceProvider).trend());
final integrityProvider =
    FutureProvider.autoDispose.family<List<Json>, String>((ref, testId) => ref.watch(insightsServiceProvider).integrity(testId));

/// Shared by faculty (their department) and admin (their category): at-risk
/// students, weak topics, score trend, integrity flags, and device resets.
/// Pass [isAdmin] so the Integrity tab knows which test to inspect.
class InsightsScreen extends ConsumerWidget {
  final bool isAdmin;
  const InsightsScreen({super.key, required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Insights'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'At risk'),
              Tab(text: 'Weak topics'),
              Tab(text: 'Trend'),
              Tab(text: 'Integrity'),
              Tab(text: 'Devices'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _AtRiskTab(),
            const _TopicsTab(),
            const _TrendTab(),
            _IntegrityTab(isAdmin: isAdmin),
            const _DevicesTab(),
          ],
        ),
      ),
    );
  }
}

String _pct(num? v) => v == null ? '—' : '${v.toStringAsFixed(0)}%';

// ------------------------------------------------------------------ At risk
class _AtRiskTab extends ConsumerWidget {
  const _AtRiskTab();

  Future<void> _showReadiness(BuildContext context, WidgetRef ref, Json row) async {
    try {
      final r = await ref.read(insightsServiceProvider).readiness(row['student_id'] as String);
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('${row['full_name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Placement readiness: ${r['score']} (${r['band']})', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text('Aptitude ${_pct(r['aptitude'] as num?)}   Technical ${_pct(r['technical'] as num?)}'),
              Text('Communication ${_pct(r['communication'] as num?)}   Attendance ${_pct(r['attendance'] as num?)}'),
              const SizedBox(height: 10),
              const Text(
                'Weighted: 40% aptitude, 40% technical, 20% communication (last 10 tests each), blended with attendance.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(atRiskProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(atRiskProvider);
        await ref.read(atRiskProvider.future);
      },
      child: AsyncValueWidget<List<Json>>(
        value: async,
        data: (rows) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Rule-based flags from each student\'s last 6 published tests: 3+ absences or under 40% average is High; '
              'under 55% average or a sharp drop versus the previous 3 tests is Medium. Tap a student for their placement readiness.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No at-risk students right now.')),
              ),
            for (final r in rows)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => _showReadiness(context, ref, r),
                  title: Text('${r['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${r['register_number']} · Year ${r['year']}\n'
                    'Avg ${_pct(r['avg_pct'] as num?)} · ${r['absences']} absent · trend ${(r['trend'] as num? ?? 0) >= 0 ? '+' : ''}${r['trend']} pts',
                  ),
                  isThreeLine: true,
                  trailing: Chip(
                    label: Text('${r['risk']}'),
                    backgroundColor: r['risk'] == 'High' ? AppColors.errorLight : AppColors.warningLight,
                    labelStyle: TextStyle(
                      color: r['risk'] == 'High' ? AppColors.error : AppColors.warning,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- Topics
class _TopicsTab extends ConsumerWidget {
  const _TopicsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(topicHeatmapProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(topicHeatmapProvider);
        await ref.read(topicHeatmapProvider.future);
      },
      child: AsyncValueWidget<List<Json>>(
        value: async,
        data: (rows) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Accuracy by subject over the last 30 days, weakest first.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            const SizedBox(height: 12),
            if (rows.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No answers recorded yet.'))),
            for (final r in rows) _topicRow(r),
          ],
        ),
      ),
    );
  }

  Widget _topicRow(Json r) {
    final attempted = (r['attempted'] as num).toInt();
    final correct = (r['correct'] as num).toInt();
    final acc = attempted == 0 ? 0.0 : correct / attempted;
    final color = acc >= 0.7 ? AppColors.success : (acc >= 0.5 ? AppColors.warning : AppColors.error);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${r['subject']}', style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('${(acc * 100).round()}%  ($correct/$attempted)', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: acc, minHeight: 8, color: color, backgroundColor: color.withOpacity(0.15)),
          ),
          Text('${r['category']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- Trend
class _TrendTab extends ConsumerWidget {
  const _TrendTab();

  static const _catColors = {
    'aptitude': AppColors.primaryOrange,
    'technical': AppColors.faculty,
    'communication': AppColors.admin,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trendProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(trendProvider);
        await ref.read(trendProvider.future);
      },
      child: AsyncValueWidget<List<Json>>(
        value: async,
        data: (rows) {
          if (rows.isEmpty) {
            return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No published tests in the last 60 days.')))]);
          }
          final dates = rows.map((r) => r['test_date'] as String).toSet().toList()..sort();
          final cats = rows.map((r) => r['category'] as String).toSet().toList()..sort();
          final bars = <LineChartBarData>[];
          for (final c in cats) {
            final spots = <FlSpot>[];
            for (final r in rows.where((r) => r['category'] == c)) {
              final v = (r['avg_pct'] as num?)?.toDouble();
              if (v != null) spots.add(FlSpot(dates.indexOf(r['test_date'] as String).toDouble(), v));
            }
            bars.add(LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 3,
              color: _catColors[c] ?? AppColors.faculty,
              dotData: const FlDotData(show: true),
            ));
          }
          final fmt = DateFormat('d MMM');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Average score % per test day, by category.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                children: [
                  for (final c in cats)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: _catColors[c], shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(c),
                    ]),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 260,
                child: LineChart(LineChartData(
                  minY: 0,
                  maxY: 100,
                  lineBarsData: bars,
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: 25)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: dates.length > 6 ? (dates.length / 6).ceilToDouble() : 1,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= dates.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(fmt.format(DateTime.parse(dates[i])), style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 20),
              const Text('Attendance per test', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final r in rows.reversed.take(12))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${fmt.format(DateTime.parse(r['test_date'] as String))} · ${r['category']}'),
                  trailing: Text('${r['submitted']}/${r['total']} attended · avg ${_pct(r['avg_pct'] as num?)}'),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Integrity
class _IntegrityTab extends ConsumerWidget {
  final bool isAdmin;
  const _IntegrityTab({required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DailyTest?> testAsync = isAdmin
        ? ref.watch(recentTestsProvider).whenData((l) => l.isEmpty ? null : l.first)
        : ref.watch(selectedFacultyTestProvider);

    return Column(
      children: [
        if (!isAdmin) const CategorySelector(),
        Expanded(
          child: AsyncValueWidget<DailyTest?>(
            value: testAsync,
            data: (test) {
              if (test == null) return const Center(child: Text('No test for this category today.'));
              final rowsAsync = ref.watch(integrityProvider(test.id));
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(integrityProvider(test.id));
                  await ref.read(integrityProvider(test.id).future);
                },
                child: AsyncValueWidget<List<Json>>(
                  value: rowsAsync,
                  data: (rows) => ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Students who left the app during the ${test.category.label} test on ${DateFormat('d MMM').format(test.testDate)}. '
                        'Leaving auto-submits the attempt, so this is for review, not an accusation.',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                      const SizedBox(height: 12),
                      if (rows.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No integrity events recorded.'))),
                      for (final r in rows)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text('${r['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${r['register_number']}'),
                            trailing: Text('${r['total_events']} events\n${r['background_events']} left app',
                                textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ Devices
class _DevicesTab extends ConsumerStatefulWidget {
  const _DevicesTab();

  @override
  ConsumerState<_DevicesTab> createState() => _DevicesTabState();
}

class _DevicesTabState extends ConsumerState<_DevicesTab> {
  final _controller = TextEditingController();
  List<Json> _results = [];
  bool _busy = false;

  Future<void> _search() async {
    if (_controller.text.trim().length < 3) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(insightsServiceProvider).searchStudents(_controller.text);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset(Json s) async {
    final name = (s['profiles'] as Map?)?['full_name'] ?? s['register_number'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset $name\'s phone?'),
        content: const Text('Use this when a student changed or lost their phone. Their next test start will link the new phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(insightsServiceProvider).resetDevice(s['id'] as String);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device link cleared.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Each student account is linked to the first phone it starts a test on. Search by register number to unlink it.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'Register number',
            suffixIcon: IconButton(
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search_rounded),
              onPressed: _busy ? null : _search,
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final s in _results)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text('${(s['profiles'] as Map?)?['full_name'] ?? ''}'),
              subtitle: Text('${s['register_number']}'),
              trailing: TextButton(onPressed: () => _reset(s), child: const Text('Reset phone')),
            ),
          ),
      ],
    );
  }
}
