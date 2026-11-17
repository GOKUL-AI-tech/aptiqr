import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/test_category.dart';
import '../providers/faculty_provider.dart';

/// Lets faculty pick which of today's (up to 3) category tests the
/// Ranking / Student Monitoring / Reports screens are currently showing
/// — those screens all key off a single dailyTestId under the hood, so
/// rather than redesign each one to aggregate 3 tests at once, this
/// picker sits at the top and swaps which one is "selected" (see
/// selectedFacultyCategoryProvider / selectedFacultyTestProvider).
class CategorySelector extends ConsumerWidget {
  const CategorySelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedFacultyCategoryProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: SegmentedButton<TestCategory>(
        segments: TestCategory.values
            .map((c) => ButtonSegment(value: c, label: Text(c.label), icon: Icon(c.icon, size: 16)))
            .toList(),
        selected: {selected},
        showSelectedIcon: false,
        onSelectionChanged: (s) => ref.read(selectedFacultyCategoryProvider.notifier).state = s.first,
      ),
    );
  }
}
