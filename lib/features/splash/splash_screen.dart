import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../widgets/app_logo.dart';

/// Branded launch screen (deck slide 02 — "First impression, branded to
/// the college"). Router `redirect` takes over as soon as auth state is
/// known; this just holds the splash for a beat and falls back to
/// role-select if no session is found.
///
/// Redesigned from a flat orange background + static logo into a real
/// hero moment: a two-stop gradient, soft decorative blobs for depth, and
/// a staged fade/scale entrance — the first thing anyone installing the
/// app sees, so it's worth it not looking like a placeholder screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween(begin: 0.88, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) context.go('/role-select');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryOrange, AppColors.primaryOrangeDark],
          ),
        ),
        child: Stack(
          children: [
            // Decorative depth — large soft blobs, not full opaque shapes,
            // so the gradient still reads through and nothing competes
            // with the logo for attention.
            Positioned(
              top: -70,
              right: -60,
              child: _Blob(size: 240, opacity: 0.10),
            ),
            Positioned(
              bottom: -100,
              left: -80,
              child: _Blob(size: 300, opacity: 0.08),
            ),
            Positioned(
              top: 140,
              left: -40,
              child: _Blob(size: 100, opacity: 0.12),
            ),
            SafeArea(
              child: Center(
                child: FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: _scale,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppLogo(size: 100),
                        const SizedBox(height: 30),
                        Text(
                          AppConstants.collegeName.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          AppConstants.appName,
                          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Daily aptitude, made effortless',
                          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 40),
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        ),
                      ],
                    ),
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

class _Blob extends StatelessWidget {
  final double size;
  final double opacity;
  const _Blob({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(opacity)),
    );
  }
}
