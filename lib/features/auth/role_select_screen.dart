import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../widgets/app_logo.dart';

/// Deck slide 03 — "One entry point, three roles".
///
/// Redesigned from a plain white column of bordered rows into a screen
/// with real hierarchy: a gradient hero header (echoing the splash
/// screen's identity instead of abandoning it the moment splash ends),
/// and role cards with gradient icon badges + a soft shadow instead of a
/// flat 1px border — the previous version was legible but had almost no
/// visual weight anywhere, which is exactly the "looks plain" feedback.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Choose your role', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  const Text('Sign in to continue', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                  const SizedBox(height: 18),
                  _RoleCard(
                    icon: Icons.school_rounded,
                    title: 'Student',
                    subtitle: 'Take today\'s test, view results & rank',
                    role: 'student',
                    onTap: () => context.push('/login/student'),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    icon: Icons.badge_rounded,
                    title: 'Faculty',
                    subtitle: 'Monitor attendance, QR & rankings',
                    role: 'faculty',
                    onTap: () => context.push('/login/faculty'),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Admin',
                    subtitle: 'Manage question bank, people & tests',
                    role: 'admin',
                    onTap: () => context.push('/login/admin'),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: Text(
                      'v0.1.0 · ${AppConstants.collegeName}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 28, bottom: 32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryOrange, AppColors.primaryOrangeDark],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(top: -30, right: -30, child: _blob(120, 0.10)),
            Positioned(bottom: -40, left: -20, child: _blob(90, 0.10)),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 64),
                const SizedBox(height: 14),
                Text(
                  AppConstants.collegeName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4),
                ),
                const SizedBox(height: 4),
                Text(
                  AppConstants.appName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3),
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

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String role;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.role,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forRole(role);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: AppColors.gradientForRole(role),
                  ),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.3)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withOpacity(0.10), shape: BoxShape.circle),
                child: Icon(Icons.arrow_forward_rounded, color: color, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
