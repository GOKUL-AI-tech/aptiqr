import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/device/screen_guard.dart';
import '../../../local_db/app_database.dart';
import '../../../providers/student_provider.dart';
import '../../../widgets/loading_button.dart';

/// Deck slide 09/11 — "review before submitting; one attempt per day."
class TestReviewScreen extends ConsumerStatefulWidget {
  final String testId;
  const TestReviewScreen({super.key, required this.testId});

  @override
  ConsumerState<TestReviewScreen> createState() => _TestReviewScreenState();
}

class _TestReviewScreenState extends ConsumerState<TestReviewScreen> with WidgetsBindingObserver {
  List<CachedQuestion> _questions = [];
  Map<String, String> _answers = {};
  bool _loading = true;
  bool _submitting = false;

  // Same anti-cheating guard as TestQuestionScreen — the attempt isn't
  // final until Submit is actually tapped, so leaving the app while still
  // on the review screen auto-submits it too (whatever's answered so far).
  bool _autoSubmitted = false;
  bool _guarded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_guarded) ScreenGuard.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_loading && !_submitting && !_autoSubmitted) {
      _autoSubmitted = true;
      ref.read(studentServiceProvider).logIntegrityEvent(widget.testId, 'app_background');
      ref.read(studentServiceProvider).autoSubmitOnExit(widget.testId);
    } else if (state == AppLifecycleState.resumed && _autoSubmitted) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.invalidate(myAttemptProvider(widget.testId));
        context.go('/student');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You left the test, so it was submitted automatically with your answers so far.'),
          ),
        );
      });
    }
  }

  Future<void> _load() async {
    final service = ref.read(studentServiceProvider);

    // Same guard as TestQuestionScreen — don't let an already auto-
    // submitted-on-this-device attempt be reviewed/resumed just because
    // the submit RPC never made it to the server before the process was
    // killed.
    if (await service.isAttemptLocked(widget.testId)) {
      if (mounted) context.go('/student');
      return;
    }

    final questions = await service.questionsFor(widget.testId);
    final answers = await service.myAnswers(widget.testId);
    if (!mounted) return; // screen was popped (e.g. back gesture) while awaiting above
    _guarded = true;
    ScreenGuard.enable();
    setState(() {
      _questions = questions;
      _answers = answers;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final synced = await ref.read(studentServiceProvider).submitAttempt(widget.testId);
    if (!mounted) return;
    setState(() => _submitting = false);

    ref.invalidate(myAttemptProvider(widget.testId));

    if (synced) {
      // Go straight to this test's own result — a day can have up to 3
      // tests now (Aptitude/Technical/Communication), so landing on the
      // generic /student/result list would make the student re-find and
      // re-tap the one they just submitted instead of seeing it directly.
      context.go('/student/result/${widget.testId}');
    } else {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Saved — will submit when online'),
          content: const Text(
            'You\'re offline right now. Your answers are safely saved on this device and will '
            'submit automatically the moment you\'re back online. You can close the app safely.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
          ],
        ),
      );
      if (mounted) context.go('/student');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final unanswered = _questions.where((q) => !_answers.containsKey(q.questionId)).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Review Answers')),
      body: Column(
        children: [
          Expanded(
            child: SelectionContainer.disabled(
              child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _questions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final q = _questions[i];
                final answered = _answers.containsKey(q.questionId);
                return InkWell(
                  onTap: () => context.pushReplacement('/student/test/${widget.testId}/question'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: answered ? AppColors.success.withOpacity(0.15) : AppColors.warning.withOpacity(0.15),
                          child: Icon(
                            answered ? Icons.check_rounded : Icons.priority_high_rounded,
                            size: 16,
                            color: answered ? AppColors.success : AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Q${i + 1}. ${q.questionText}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        Text(answered ? _answers[q.questionId]! : '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                );
              },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                if (unanswered > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '$unanswered question${unanswered == 1 ? '' : 's'} left unanswered',
                      style: const TextStyle(color: AppColors.warning),
                    ),
                  ),
                LoadingButton(
                  label: 'Submit Test',
                  loading: _submitting,
                  onPressed: () => _confirmSubmit(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSubmit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit test?'),
        content: const Text('You get one attempt per day. You won\'t be able to change your answers after this.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed == true) _submit();
  }
}
