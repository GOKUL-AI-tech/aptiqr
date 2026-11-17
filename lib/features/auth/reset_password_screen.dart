import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/loading_button.dart';

/// Landed on after a student/faculty/admin taps the link from their
/// "Forgot password?" email and it deep-links back into the app (see
/// AuthService.sendPasswordReset for the redirectTo, and the Android
/// intent-filter in AndroidManifest.xml). The router forces every
/// signed-in-via-recovery session here — see
/// GoRouterRefreshStream.needsPasswordReset in app_router.dart — before
/// letting them into their normal role section, so there's no way to
/// accidentally skip past this screen into the app with the old password
/// still active.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).updatePassword(_passwordCtrl.text);
      setState(() => _done = true);
      // Sign out so they log back in through the normal role-specific
      // screen with the new password. This also flips the router's
      // needsPasswordReset flag back off (see GoRouterRefreshStream),
      // otherwise they'd be stuck bounced back to this screen forever.
      await ref.read(authServiceProvider).signOut();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                const Center(child: AppLogo(background: AppColors.primaryOrangeLight, size: 64)),
                const SizedBox(height: 20),
                Text('Set a new password', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                const Text(
                  'You\'re verified — choose a new password for your account.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 28),
                if (_done) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(14)),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppColors.success),
                        SizedBox(width: 12),
                        Expanded(child: Text('Password updated. Sign in again with your new password.')),
                      ],
                    ),
                  ),
                ] else ...[
                  const Text('New password', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'At least 6 characters'),
                    validator: (v) => (v == null || v.length < 6) ? 'Password must be at least 6 characters' : null,
                  ),
                  const SizedBox(height: 18),
                  const Text('Confirm password', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'Re-enter password'),
                    validator: (v) => v != _passwordCtrl.text ? 'Passwords don\'t match' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.error)),
                  ],
                  const SizedBox(height: 20),
                  LoadingButton(label: 'Update password', loading: _loading, onPressed: _save),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
