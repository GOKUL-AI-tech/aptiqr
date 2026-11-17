import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';

class FacultyShell extends StatelessWidget {
  final Widget child;
  const FacultyShell({super.key, required this.child});

  static const _tabs = ['/faculty', '/faculty/monitoring', '/faculty/ranking', '/faculty/reports', '/faculty/profile'];

  int _indexFor(String location) {
    final i = _tabs.indexWhere((t) => location == t);
    return i == -1 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _indexFor(location);

    return Theme(
      data: AppTheme.forRole('faculty'),
      child: Scaffold(
        body: child,
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 24, offset: Offset(0, -6))],
          ),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => context.go(_tabs[i]),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.qr_code_outlined), selectedIcon: Icon(Icons.qr_code_rounded), label: 'Today\'s QR'),
              NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check_rounded), label: 'Monitoring'),
              NavigationDestination(icon: Icon(Icons.leaderboard_outlined), selectedIcon: Icon(Icons.leaderboard_rounded), label: 'Ranking'),
              NavigationDestination(icon: Icon(Icons.summarize_outlined), selectedIcon: Icon(Icons.summarize_rounded), label: 'Reports'),
              NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}
