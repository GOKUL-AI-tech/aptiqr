import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/device/screen_guard.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../local_db/app_database.dart';
import '../../../providers/student_provider.dart';

/// Deck slide 09/11 — "Read instructions, answer and navigate 20
/// questions, review before submitting." Reads from the local cache so
/// the student can keep answering with zero connectivity; every tap is
/// written to the on-device DB immediately (see StudentService.answerQuestion).
class TestQuestionScreen extends ConsumerStatefulWidget {
  final String testId;
  const TestQuestionScreen({super.key, required this.testId});

  @override
  ConsumerState<TestQuestionScreen> createState() => _TestQuestionScreenState();
}

class _TestQuestionScreenState extends ConsumerState<TestQuestionScreen> with WidgetsBindingObserver {
  List<CachedQuestion> _questions = [];
  Map<String, String> _answers = {};
  int _index = 0;
  bool _loading = true;
  Timer? _timer;
  Duration _remaining = const Duration(minutes: 30);

  // Anti-cheating guard: if the student backgrounds the app (home button,
  // app switcher, screen lock) while a test is in progress, whatever
  // they've answered so far is auto-submitted the moment it happens (see
  // didChangeAppLifecycleState / StudentService.autoSubmitOnExit) and
  // they're bounced to Home the moment they come back — they never get to
  // keep answering after having left the test screen.
  bool _autoSubmitted = false;
  bool _guarded = false;

  // Per-student seed: question order and option order are shuffled
  // deterministically (same student + same test => same layout after a
  // restart), so neighbours can't compare "question 7, option C".
  String _seed = '';
  final Map<String, List<String>> _optionOrder = {};

  static int _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  List<String> _orderFor(String questionId) => _optionOrder.putIfAbsent(
        questionId,
        () => ['A', 'B', 'C', 'D']..shuffle(Random(_fnv('$_seed:$questionId'))),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_loading && !_autoSubmitted) {
      _autoSubmitted = true;
      _timer?.cancel();
      final svc = ref.read(studentServiceProvider);
      svc.logIntegrityEvent(widget.testId, 'app_background');
      // Fire-and-forget: the app may be killed at any point after this,
      // so there's no reliable way to await it. autoSubmitOnExit writes
      // the local lock first (fast, synchronous-ish, so it's very likely
      // to land even if the process is killed a moment later), then
      // best-effort submits whatever's been answered so far.
      ref.read(studentServiceProvider).autoSubmitOnExit(widget.testId);
    } else if (state == AppLifecycleState.resumed && _autoSubmitted) {
      _returnToHomeAfterAutoSubmit();
    }
  }

  void _returnToHomeAfterAutoSubmit() {
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

  Future<void> _load() async {
    final service = ref.read(studentServiceProvider);

    // Guard against resuming an attempt already auto-submitted on this
    // device (see StudentService.autoSubmitOnExit / isAttemptLocked) —
    // covers the case where the OS killed the app before the submit RPC
    // landed, so a fresh Home screen might still have offered "Continue
    // Test" based on stale server state.
    if (await service.isAttemptLocked(widget.testId)) {
      if (mounted) context.go('/student');
      return;
    }

    final test = ref.read(testByIdProvider(widget.testId)).valueOrNull;
    final fetched = await service.questionsFor(widget.testId);
    final answers = await service.myAnswers(widget.testId);
    final startedAt = await service.attemptStartedAt(widget.testId);
    if (!mounted) return; // screen was popped (e.g. back gesture) while awaiting above
    if (test != null) {
      // Count down from when the attempt actually began, so re-entering this
      // screen never hands back a fresh full-length timer.
      final total = Duration(minutes: test.durationMinutes);
      final elapsed = startedAt == null ? Duration.zero : DateTime.now().difference(startedAt);
      final left = total - elapsed;
      _remaining = left.isNegative ? Duration.zero : left;
    }
    _seed = '${SupabaseService.currentUser?.id ?? ''}:${widget.testId}';
    final questions = [...fetched]..shuffle(Random(_fnv(_seed)));
    _guarded = true;
    ScreenGuard.enable();
    setState(() {
      _questions = questions;
      _answers = answers;
      _loading = false;
    });
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining.inSeconds <= 0) {
        t.cancel();
        _goToReview();
        return;
      }
      setState(() => _remaining -= const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (_guarded) ScreenGuard.disable();
    super.dispose();
  }

  Future<void> _select(String option) async {
    final q = _questions[_index];
    final previous = _answers[q.questionId];
    // Optimistic — the option highlights immediately rather than waiting
    // on the local DB write below.
    setState(() => _answers = {..._answers, q.questionId: option});
    try {
      await ref.read(studentServiceProvider).answerQuestion(
            dailyTestId: widget.testId,
            questionId: q.questionId,
            selectedOption: option,
          );
    } catch (e) {
      // The local (offline-first) DB write itself failed — leaving the
      // option shown as selected here would be a lie: nothing was
      // actually persisted, so review/submit wouldn't have this answer
      // either. Revert the optimistic state and say so, rather than
      // silently losing the answer.
      if (!mounted) return;
      setState(() {
        final reverted = {..._answers};
        if (previous == null) {
          reverted.remove(q.questionId);
        } else {
          reverted[q.questionId] = previous;
        }
        _answers = reverted;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save that answer — try selecting it again.')),
      );
    }
  }

  void _goToReview() {
    context.pushReplacement('/student/test/${widget.testId}/review');
  }

  String get _timerText {
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_questions.isEmpty) {
      return const Scaffold(body: Center(child: Text('No questions found for today\'s test.')));
    }

    final q = _questions[_index];
    final selected = _answers[q.questionId];
    final answeredCount = _answers.length;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Question ${_index + 1} of ${_questions.length}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 18, color: AppColors.primaryOrange),
                    const SizedBox(width: 4),
                    Text(_timerText, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryOrange)),
                  ],
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(value: (_index + 1) / _questions.length),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          // Disabled selection for the whole question body — no long-press
          // "Select all / Copy" on the question or options while a test is
          // in progress.
          child: SelectionContainer.disabled(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(q.subject.toUpperCase(), style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 8),
              Text(q.questionText, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  children: [
                    // Options are shown in a per-student shuffled order, but the
                    // answer sent to the server is always the ORIGINAL letter.
                    for (var i = 0; i < 4; i++)
                      _OptionTile(
                        label: 'ABCD'[i],
                        text: {'A': q.optionA, 'B': q.optionB, 'C': q.optionC, 'D': q.optionD}[_orderFor(q.questionId)[i]]!,
                        selected: selected == _orderFor(q.questionId)[i],
                        onTap: () => _select(_orderFor(q.questionId)[i]),
                      ),
                  ],
                ),
              ),
              Text('$answeredCount of ${_questions.length} answered', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_index > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _index--),
                        child: const Text('Previous'),
                      ),
                    ),
                  if (_index > 0) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_index < _questions.length - 1) {
                          setState(() => _index++);
                        } else {
                          _goToReview();
                        }
                      },
                      child: Text(_index < _questions.length - 1 ? 'Next' : 'Review & Submit'),
                    ),
                  ),
                ],
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({required this.label, required this.text, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryOrangeLight : Colors.white,
            border: Border.all(color: selected ? AppColors.primaryOrange : AppColors.border, width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: selected ? AppColors.primaryOrange : AppColors.background,
                child: Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }
}
