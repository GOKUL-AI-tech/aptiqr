import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/loading_button.dart';

/// Deck slide 04: "Email ID, Password. Login button and back link."
class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _sendingReset = false;
  String? _error;

  Future<void> _submitCredentials() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      await auth.signInAdmin(email: _emailCtrl.text.trim(), password: _passwordCtrl.text);
      // router redirect takes the user straight into /admin
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendResetLink() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      // Previously a silent no-op — tapping "Forgot password?" with the
      // email field empty did literally nothing, which is exactly what
      // "forgot password isn't working" looks like from the outside.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email above first, then tap "Forgot password?".')),
      );
      return;
    }
    setState(() => _sendingReset = true);
    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reset link sent if that email exists — check your inbox.')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send the reset email. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.adminLight,
      appBar: AppBar(
        backgroundColor: AppColors.adminLight,
        leading: BackButton(onPressed: () => context.go('/role-select')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _credentialsForm(context),
        ),
      ),
    );
  }

  Widget _credentialsForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: AppLogo(size: 64)),
          const SizedBox(height: 20),
          Text('Admin Login', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          const Text('Manage question bank, people & tests', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 28),

          const Text('Email', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'admin@college.edu'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 18),

          const Text('Password', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Password'),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _sendingReset ? null : _sendResetLink,
              child: _sendingReset
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.admin),
                    )
                  : const Text('Forgot password?'),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],

          const SizedBox(height: 12),
          LoadingButton(label: 'Login', loading: _loading, onPressed: _submitCredentials, color: AppColors.admin),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
