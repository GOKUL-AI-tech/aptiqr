import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/config/env.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Env.isConfigured) await SupabaseService.init();
  runApp(const ProviderScope(child: AptiQrApp()));
}

class AptiQrApp extends ConsumerWidget {
  const AptiQrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Without this check, a build/run that forgot --dart-define(-from-file)
    // silently bakes in the placeholder 'https://YOUR-PROJECT.supabase.co'
    // URL from Env — Supabase.initialize() doesn't throw on that (it's a
    // syntactically valid URL), so the app boots normally and every screen
    // *looks* fine until something tries to actually talk to Supabase
    // (departments dropdown on the student login screen is usually the
    // first thing hit, and previously just failed silently into a small
    // red "Could not load departments" line — easy to miss, confusing to
    // debug). Catching it here instead, before the router/theme even
    // build, turns that into one unmissable screen instead of N different
    // half-broken ones.
    if (!Env.isConfigured) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _MissingConfigScreen(),
      );
    }

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}

class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF3F0),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 56, color: Color(0xFFD64545)),
                const SizedBox(height: 16),
                const Text(
                  'Supabase isn\'t configured',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'This build was compiled without SUPABASE_URL / SUPABASE_ANON_KEY, '
                  'so nothing that talks to the backend (login, departments, tests, '
                  'results...) will work.\n\n'
                  'Rebuild with:\n'
                  'flutter build apk --dart-define-from-file=env/dev.json\n\n'
                  '("flutter build apk" alone, with no --dart-define(-from-file), '
                  'produces exactly this screen.)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B6B6B), height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Re-exported so screens only need one import for routing.
typedef AppRouter = GoRouter;
