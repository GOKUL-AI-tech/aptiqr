import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/daily_test.dart';
import '../../../models/test_category.dart';
import '../../../providers/admin_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/refresh_icon_button.dart';

/// Deck slide 07 — "Auto or manual publish, department/year/overall
/// rankings, top 10 students."
class ResultsManagementScreen extends ConsumerWidget {
  const ResultsManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testsAsync = ref.watch(recentTestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            ref.invalidate(recentTestsProvider);
            await ref.read(recentTestsProvider.future);
          }),
        ],
      ),
      body: AsyncValueWidget<List<DailyTest>>(
        value: testsAsync,
        data: (tests) {
          if (tests.isEmpty) return const EmptyState(icon: Icons.emoji_events_outlined, title: 'No tests yet');
          return RefreshIndicator(
            color: AppColors.admin,
            onRefresh: () {
              ref.invalidate(recentTestsProvider);
              return ref.read(recentTestsProvider.future);
            },
            child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: tests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = tests[i];
              final published = t.status == DailyTestStatus.published;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(DateFormat('MMM d, yyyy').format(t.testDate), style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.adminLight, borderRadius: BorderRadius.circular(20)),
                                child: Text(t.category.label, style: const TextStyle(color: AppColors.admin, fontSize: 10.5, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          Text(published ? 'Results published' : 'Awaiting publish', style: TextStyle(color: published ? AppColors.success : AppColors.warning, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (!published)
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.admin),
                        onPressed: () async {
                          try {
                            await ref.read(adminServiceProvider).publishResults(t.id);
                            ref.invalidate(recentTestsProvider);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Results published')));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                            }
                          }
                        },
                        child: const Text('Publish'),
                      )
                    else
                      const Icon(Icons.check_circle_rounded, color: AppColors.success),
                  ],
                ),
              );
            },
          ),
          );
        },
      ),
    );
  }
}
