import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../models/department.dart';
import '../../providers/auth_provider.dart';
import '../../providers/department_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/loading_button.dart';

/// Deck slide 04: "Register Number, Department, Password/OTP. Start
/// Test button, Forgot password? link, back to role select."
/// Department is informational here — the account already has one on
/// file — but showing it lets the student confirm they picked the
/// right register number before submitting.
class StudentLoginScreen extends ConsumerStatefulWidget {
  const StudentLoginScreen({super.key});

  @override
  ConsumerState<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends ConsumerState<StudentLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _regNoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  Department? _selectedDept;
  bool _useOtp = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _regNoCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInStudent(
            registerNumber: _regNoCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      // Router redirect takes over once the profile loads.
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
    final departmentsAsync = ref.watch(departmentsProvider);

    return Scaffold(
      appBar: AppBar(
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
                const Center(child: AppLogo(background: AppColors.primaryOrangeLight, size: 64)),
                const SizedBox(height: 20),
                Text('Student Login', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                const Text('Sign in to take today\'s aptitude test', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 28),

                const Text('Register Number', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _regNoCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'e.g. 22CS101'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Register number is required' : null,
                ),
                const SizedBox(height: 18),

                const Text('Department', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                departmentsAsync.when(
                  data: (depts) => DropdownButtonFormField<Department>(
                    value: _selectedDept,
                    isExpanded: true,
                    items: depts
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text('${d.code} — ${d.name}', overflow: TextOverflow.ellipsis, maxLines: 1),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedDept = v),
                    decoration: const InputDecoration(hintText: 'Select your department'),
                    validator: (v) => v == null ? 'Select your department' : null,
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, st) => const Text('Could not load departments', style: TextStyle(color: AppColors.error)),
                ),
                const SizedBox(height: 18),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Password', style: TextStyle(fontWeight: FontWeight.w600)),
                    TextButton(
                      onPressed: () => setState(() => _useOtp = !_useOtp),
                      child: Text(_useOtp ? 'Use password instead' : 'Use OTP instead'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: !_useOtp,
                  keyboardType: _useOtp ? TextInputType.number : TextInputType.visiblePassword,
                  decoration: InputDecoration(hintText: _useOtp ? '6-digit OTP' : 'Password'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _showForgotPasswordSheet(context),
                    child: const Text('Forgot password?'),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],

                const SizedBox(height: 12),
                LoadingButton(label: 'Start Test', loading: _loading, onPressed: _submit),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showForgotPasswordSheet(BuildContext context) {
    final emailCtrl = TextEditingController();
    bool sending = false;
    String? sheetError;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reset password', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Enter your college email — we\'ll send a reset link.', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              TextField(controller: emailCtrl, decoration: const InputDecoration(hintText: 'you@college.edu')),
              if (sheetError != null) ...[
                const SizedBox(height: 8),
                Text(sheetError!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: 16),
              LoadingButton(
                label: 'Send reset link',
                loading: sending,
                onPressed: () async {
                  final email = emailCtrl.text.trim();
                  if (email.isEmpty) {
                    // Previously a silent no-op with the field empty —
                    // tapping "Send" did nothing, no feedback at all.
                    setSheetState(() => sheetError = 'Enter your email first.');
                    return;
                  }
                  setSheetState(() {
                    sending = true;
                    sheetError = null;
                  });
                  try {
                    await ref.read(authServiceProvider).sendPasswordReset(email);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Reset link sent if that email exists — check your inbox.')),
                      );
                    }
                  } on AuthException catch (e) {
                    if (ctx.mounted) setSheetState(() => sheetError = e.message);
                  } catch (e) {
                    if (ctx.mounted) {
                      setSheetState(() => sheetError = 'Could not send the reset email. Please try again.');
                    }
                  } finally {
                    if (ctx.mounted) setSheetState(() => sending = false);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
