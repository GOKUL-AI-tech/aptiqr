import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/daily_test.dart';
import '../../../models/test_category.dart';
import '../../../providers/student_provider.dart';
import '../../../services/student_service.dart' show StartAttemptException;
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/loading_button.dart';
import '../../../widgets/qr_scanner_sheet.dart';

/// Deck slide 09/11 — read instructions, then scan the faculty's QR to
/// gate test access to students who are physically present, then start
/// answering (one attempt per day).
class TestInstructionsScreen extends ConsumerStatefulWidget {
  final String testId;
  const TestInstructionsScreen({super.key, required this.testId});

  @override
  ConsumerState<TestInstructionsScreen> createState() => _TestInstructionsScreenState();
}

class _TestInstructionsScreenState extends ConsumerState<TestInstructionsScreen> {
  bool _starting = false;
  String? _error;

  Future<void> _scanAndStart() async {
    // Previously silent no-ops (test == null, or an exception from
    // showQrScanner/Navigator itself) meant tapping this button could
    // fail with zero visible feedback — no camera screen, no error, no
    // loading state, indistinguishable from the button not responding to
    // taps at all. Both paths now surface something.
    final testAsync = ref.read(testByIdProvider(widget.testId));
    final test = testAsync.valueOrNull;
    if (test == null) {
      setState(() => _error = 'Today\'s test details aren\'t loaded yet. Go back to Home and try again.');
      return;
    }

    try {
      final scanned = await showQrScanner(context, title: 'Scan today\'s ${test.category.label} QR');
      if (scanned == null) return;
      await _validateAndStart(test, scanned);
    } catch (e) {
      setState(() => _error = 'Could not open the scanner. $e');
    }
  }

  /// Fallback for when the camera can't be used — no working/permitted
  /// camera, a device without one, or (very commonly during development)
  /// testing on a single emulator with no second device or configured
  /// virtual camera to actually show a QR code to itself. Faculty's
  /// Today's QR screen displays the same code as plain text specifically
  /// so it can be read out or typed here instead of scanned. This goes
  /// through the exact same validateQr/startAttempt path as a real scan
  /// — it's a different input method, not a weaker check.
  Future<void> _enterCodeManually() async {
    final testAsync = ref.read(testByIdProvider(widget.testId));
    final test = testAsync.valueOrNull;
    if (test == null) return;

    final controller = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter today\'s code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: '8-character code on faculty\'s screen'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text('Continue')),
        ],
      ),
    );
    if (entered == null || entered.trim().isEmpty) return;
    await _validateAndStart(test, entered);
  }

  Future<void> _validateAndStart(DailyTest test, String scannedOrTyped) async {
    final service = ref.read(studentServiceProvider);
    final code = scannedOrTyped.trim();
    if (code.isEmpty) {
      setState(() => _error = 'That code is empty. Try scanning again.');
      return;
    }

    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      // The server checks the code against the live rotating token, this
      // phone's device binding, and the geofence — so a stale screenshot,
      // a shared phone or a student outside the room is refused here.
      await service.startAttempt(test, code);
      if (mounted) context.pushReplacement('/student/test/${widget.testId}/question');
    } on StartAttemptException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not start the test. $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final testAsync = ref.watch(testByIdProvider(widget.testId));

    return Scaffold(
      appBar: AppBar(title: const Text('Test Instructions')),
      body: AsyncValueWidget(
        value: testAsync,
        data: (test) {
          if (test == null) return const Center(child: Text('Test not found'));
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Before you begin — ${test.category.label}', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                const _InstructionRow(icon: Icons.help_outline_rounded, text: 'The test has 20 questions — read each carefully.'),
                const _InstructionRow(icon: Icons.timer_outlined, text: 'You have a fixed duration once you start; the timer cannot be paused.'),
                const _InstructionRow(icon: Icons.rule_rounded, text: 'You can review your answers before final submission.'),
                const _InstructionRow(icon: Icons.event_available_rounded, text: 'You get one attempt per day — submissions are final.'),
                const _InstructionRow(icon: Icons.wifi_off_rounded, text: 'Starting the test needs internet. If you lose connection afterwards, keep answering — progress saves on this device and syncs when you\'re back online.'),
                const _InstructionRow(icon: Icons.lock_outline_rounded, text: 'Leaving the app ends the test and submits what you have. Screenshots are blocked.'),
                const _InstructionRow(icon: Icons.qr_code_2_rounded, text: 'The QR code refreshes every 30 seconds, so scan the one currently on your faculty\'s screen.'),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrangeLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primaryOrange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ask your faculty to display today\'s ${test.category.label} QR code, then scan it to unlock the test.',
                          style: const TextStyle(color: AppColors.primaryOrangeDark),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: 24),
                LoadingButton(
                  label: 'Scan QR & Start Test',
                  loading: _starting,
                  onPressed: _scanAndStart,
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _starting ? null : _enterCodeManually,
                    child: const Text('Can\'t scan? Enter the code manually'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InstructionRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InstructionRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primaryOrange),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
