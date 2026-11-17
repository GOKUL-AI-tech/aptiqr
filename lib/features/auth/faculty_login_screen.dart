import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/loading_button.dart';

/// Deck slide 04: "Faculty ID, Email, Password. Login button, Forgot
/// password? link, back link to role select."
class FacultyLoginScreen extends ConsumerStatefulWidget {
  const FacultyLoginScreen({super.key});

  @override
  ConsumerState<FacultyLoginScreen> createState() => _FacultyLoginScreenState();
}

class _FacultyLoginScreenState extends ConsumerState<FacultyLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController(); // Faculty ID or email
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInFaculty(
            identifier: _identifierCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
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
      backgroundColor: AppColors.facultyLight,
      appBar: AppBar(
        backgroundColor: AppColors.facultyLight,
        leading: BackButton(onPressed: () => context.go('/role-select')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: AppLogo(size: 64)),
                const SizedBox(height: 20),
                Text('Faculty Login', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                const Text('Monitor attendance, QR & rankings', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 28),

                const Text('Faculty ID or Email', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _identifierCtrl,
                  decoration: const InputDecoration(hintText: 'FAC1024 or you@college.edu'),
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
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Contact admin to reset your faculty password.')),
                      );
                    },
                    child: const Text('Forgot password?'),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],

                const SizedBox(height: 12),
                LoadingButton(label: 'Login', loading: _loading, onPressed: _submit, color: AppColors.faculty),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
