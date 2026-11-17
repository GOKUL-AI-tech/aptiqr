import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/ranking.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/department_provider.dart';
import '../../../providers/faculty_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/category_selector.dart';
import '../../../widgets/home_back_button.dart';
import '../../../widgets/refresh_icon_button.dart';

/// Deck slide 05 — "Top 10 leaderboards by department, year, and overall."
class FacultyRankingScreen extends ConsumerStatefulWidget {
  const FacultyRankingScreen({super.key});

  @override
  ConsumerState<FacultyRankingScreen> createState() => _FacultyRankingScreenState();
}

class _FacultyRankingScreenState extends ConsumerState<FacultyRankingScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  // Each leaderboard tab fetches with a plain imperative `fetchTop10`
  // call in its own State (see _LeaderboardTabState._load), not through
  // a cached provider — so there's nothing at this outer level to
  // `ref.invalidate`. Bumping this and folding it into the TabBarView's
  // key (below) forces the whole tab subtree to be torn down and
  // recreated on refresh, the same "fresh key -> fresh initState -> fresh
  // fetch" idiom already used for the Year/Department pickers in this
  // file, which reliably re-runs every tab's fetch.
  int _refreshTick = 0;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ranking is per-test, and a day can now have up to 3 tests (one per
    // category) — CategorySelector picks which one this screen shows;
    // selectedFacultyTestProvider resolves that to an actual DailyTest
    // (or null if that category's test hasn't been generated yet today).
    final testAsync = ref.watch(selectedFacultyTestProvider);
    final facultyAsync = ref.watch(currentFacultyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranking'),
        leading: const HomeBackButton(homeRoute: '/faculty'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            ref.invalidate(selectedFacultyTestProvider);
            setState(() => _refreshTick++);
            await ref.read(selectedFacultyTestProvider.future);
          }),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.faculty,
          tabs: const [Tab(text: 'Overall'), Tab(text: 'Department'), Tab(text: 'Year')],
        ),
      ),
      body: Column(
        children: [
          const CategorySelector(),
          Expanded(
            child: testAsync.when(
              data: (test) {
                if (test == null) return const EmptyState(icon: Icons.leaderboard_outlined, title: 'No test today in this category');
                return TabBarView(
                  key: ValueKey('ranking-tabs-$_refreshTick'),
                  controller: _tabController,
                  children: [
                    _LeaderboardTab(dailyTestId: test.id, scope: 'overall'),
                    facultyAsync.when(
                      // Previously hardcoded to the signed-in faculty's own
                      // department with no way to change it — this tab now
                      // starts there (still the most likely thing they want)
                      // but lets them switch to any department, same as the
                      // Year tab already lets them pick any year.
                      data: (f) => _DepartmentLeaderboardTab(dailyTestId: test.id, initialDepartmentId: f?.departmentId),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, st) => Center(child: Text('$e')),
                    ),
                    _YearLeaderboardTab(dailyTestId: test.id),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('$e', style: const TextStyle(color: AppColors.error))),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps [_LeaderboardTab] with a year picker — previously this tab was
/// hardcoded to `year: 1`, so faculty could never actually see years 2-4
/// no matter what they clicked.
class _YearLeaderboardTab extends StatefulWidget {
  final String dailyTestId;
  const _YearLeaderboardTab({required this.dailyTestId});

  @override
  State<_YearLeaderboardTab> createState() => _YearLeaderboardTabState();
}

class _YearLeaderboardTabState extends State<_YearLeaderboardTab> {
  int _year = AppConstants.years.first;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: DropdownButton<int>(
              value: _year,
              items: AppConstants.years.map((y) => DropdownMenuItem(value: y, child: Text('Year $y'))).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _year = v);
              },
            ),
          ),
        ),
        Expanded(
          // Keyed on the selected year so picking a new one creates a
          // fresh _LeaderboardTab (fresh initState -> fresh fetch)
          // instead of reusing the old State, which previously kept
          // showing the first year's results no matter what was picked
          // (_load() only ever ran once, in initState).
          child: _LeaderboardTab(key: ValueKey('year-$_year'), dailyTestId: widget.dailyTestId, scope: 'year', year: _year),
        ),
      ],
    );
  }
}

/// Wraps [_LeaderboardTab] with a department picker — previously this tab
/// was hardcoded to the signed-in faculty's own department via
/// `f?.departmentId`, with no way to see any other department's ranking.
class _DepartmentLeaderboardTab extends ConsumerStatefulWidget {
  final String dailyTestId;
  final String? initialDepartmentId;
  const _DepartmentLeaderboardTab({required this.dailyTestId, this.initialDepartmentId});

  @override
  ConsumerState<_DepartmentLeaderboardTab> createState() => _DepartmentLeaderboardTabState();
}

class _DepartmentLeaderboardTabState extends ConsumerState<_DepartmentLeaderboardTab> {
  String? _departmentId;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final departmentsAsync = ref.watch(departmentsProvider);
    return departmentsAsync.when(
      data: (departments) {
        if (!_initialized) {
          // Default to the faculty's own department (most useful first
          // view) if it's in the active list, otherwise just the first
          // department — either way, only ever set this once so it
          // doesn't snap back after the user picks a different one.
          final ownDeptValid = departments.any((d) => d.id == widget.initialDepartmentId);
          _departmentId = ownDeptValid ? widget.initialDepartmentId : (departments.isNotEmpty ? departments.first.id : null);
          _initialized = true;
        }
        if (departments.isEmpty) {
          return const EmptyState(icon: Icons.apartment_outlined, title: 'No departments found');
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              // Department names ("Artificial Intelligence & Machine
              // Learning (AI&ML)") are far longer than a year number —
              // a bare DropdownButton sizes itself to its widest item with
              // no width limit, which pushed past the screen edge and
              // triggered a RenderFlex overflow banner. isExpanded: true
              // constrains it to the available width instead, and the
              // ellipsis below truncates anything still too long to fit.
              child: DropdownButtonFormField<String>(
                value: _departmentId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Department', isDense: true),
                items: departments
                    .map((d) => DropdownMenuItem(
                          value: d.id,
                          child: Text('${d.name} (${d.code})', overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _departmentId = v);
                },
              ),
            ),
            Expanded(
              // Same fresh-State-per-selection fix as the Year tab above.
              child: _LeaderboardTab(
                key: ValueKey('dept-$_departmentId'),
                dailyTestId: widget.dailyTestId,
                scope: 'department',
                departmentId: _departmentId,
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('$e', style: const TextStyle(color: AppColors.error))),
    );
  }
}

class _LeaderboardTab extends ConsumerStatefulWidget {
  final String dailyTestId;
  final String scope;
  final String? departmentId;
  final int? year;

  const _LeaderboardTab({super.key, required this.dailyTestId, required this.scope, this.departmentId, this.year});

  @override
  ConsumerState<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends ConsumerState<_LeaderboardTab> {
  late Future<List<RankingEntry>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // fetchTop10 is called directly (not through a cached FutureProvider),
  // so pull-to-refresh here means literally re-invoking it and swapping
  // in a new Future — a plain `await future` on the old one would just
  // hand back the same already-resolved result.
  void _load() {
    _future = ref.read(facultyServiceProvider).fetchTop10(
          widget.dailyTestId,
          scope: widget.scope,
          departmentId: widget.departmentId,
          year: widget.year,
        );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RankingEntry>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data ?? [];
        if (entries.isEmpty) {
          return RefreshIndicator(
            color: AppColors.faculty,
            onRefresh: _refresh,
            child: ListView(
              children: const [
                SizedBox(height: 120),
                EmptyState(icon: Icons.emoji_events_outlined, title: 'Rankings publish after results go live'),
              ],
            ),
          );
        }
        return RefreshIndicator(
          color: AppColors.faculty,
          onRefresh: _refresh,
          child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final e = entries[i];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: i < 3 ? AppColors.faculty.withOpacity(0.15) : AppColors.background,
                    child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.studentName ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(e.registerNumber ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text('${e.score}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            );
          },
          ),
        );
      },
    );
  }
}
