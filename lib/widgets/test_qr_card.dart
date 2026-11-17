import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants/app_colors.dart';
import '../core/supabase/supabase_client.dart';
import '../models/daily_test.dart';
import '../models/test_category.dart';

/// The QR card for a single daily test.
///
/// Tests with `qrRotating == true` (the default since upgrade_v2.sql) show a
/// code that changes every 30 seconds: the card asks the server for the live
/// token (`current_qr_token` RPC) and refreshes itself when the countdown
/// ends. A screenshot of such a code is useless to a student who is not in the
/// room, so Download/Share are only offered for fixed-code tests.
class TestQrCard extends StatefulWidget {
  final DailyTest test;
  const TestQrCard({super.key, required this.test});

  @override
  State<TestQrCard> createState() => _TestQrCardState();
}

class _TestQrCardState extends State<TestQrCard> {
  String? _token;
  int _secondsLeft = 0;
  String? _error;
  Timer? _ticker;
  bool _fetching = false;

  DailyTest get test => widget.test;

  @override
  void initState() {
    super.initState();
    if (test.qrRotating) {
      _fetch();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_secondsLeft > 0) {
          setState(() => _secondsLeft--);
        }
        if (_secondsLeft <= 0 && !_fetching) _fetch();
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    _fetching = true;
    try {
      final rows = await SupabaseService.client.rpc('current_qr_token', params: {'p_daily_test_id': test.id});
      final row = (rows as List).first as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _token = row['token'] as String;
        _secondsLeft = (row['seconds_left'] as int?) ?? 30;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the live code. Check your connection.';
        _secondsLeft = 5; // retry shortly
      });
    } finally {
      _fetching = false;
    }
  }

  String get _payload => test.qrRotating ? (_token ?? '') : (test.qrPayload ?? test.id);

  Future<Uint8List?> _captureQrPng(GlobalKey key) async {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  void _snack(BuildContext context, String message) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveToDevice(BuildContext context, GlobalKey key) async {
    try {
      final bytes = await _captureQrPng(key);
      if (bytes == null) {
        if (context.mounted) _snack(context, 'Could not save the QR image. Please try again.');
        return;
      }
      final xFile = XFile.fromData(
        bytes,
        name: 'aptiqr_${test.category.value}_qr.png',
        mimeType: 'image/png',
      );
      await Share.shareXFiles([xFile], text: 'QR code for ${test.category.label}');
      if (context.mounted) _snack(context, 'QR image ready');
    } catch (_) {
      if (context.mounted) _snack(context, 'Could not save the QR image. Please try again.');
    }
  }

  Future<void> _share(BuildContext context, GlobalKey key) async {
    try {
      final bytes = await _captureQrPng(key);
      if (bytes == null) {
        if (context.mounted) _snack(context, 'Could not prepare the QR image to share. Please try again.');
        return;
      }
      final xFile = XFile.fromData(
        bytes,
        name: 'aptiqr_${test.category.value}_qr.png',
        mimeType: 'image/png',
      );
      await Share.shareXFiles(
        [xFile],
        text: 'Open the AptiQR app and scan this to unlock today\'s ${test.category.label} test. '
            'Then tap Start inside the app to begin.',
      );
    } catch (_) {
      if (context.mounted) _snack(context, 'Could not share the QR image. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrKey = GlobalObjectKey('test_qr_${test.id}');
    final timeFmt = DateFormat('h:mm a');
    final accent = test.category.accent;
    final hasCode = _payload.isNotEmpty;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: accent.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(test.category.icon, size: 15, color: accent),
              const SizedBox(width: 6),
              Text(
                '${test.category.shortLabel} TEST',
                style: TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withOpacity(0.35), accent.withOpacity(0.12)],
            ),
          ),
          child: RepaintBoundary(
            key: qrKey,
            child: Container(
              width: 248,
              height: 248,
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: hasCode
                  ? QrImageView(data: _payload, size: 200, backgroundColor: Colors.white)
                  : (_error != null
                      ? Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error))
                      : const CircularProgressIndicator()),
            ),
          ),
        ),
        if (test.qrRotating) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: 248,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (_secondsLeft.clamp(0, 30)) / 30,
                minHeight: 6,
                color: accent,
                backgroundColor: accent.withOpacity(0.15),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('Refreshes in ${_secondsLeft}s', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        if (hasCode) _CodeChip(code: _payload, accent: accent),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoPill(icon: Icons.help_outline_rounded, label: '${test.questionCount} questions', accent: accent),
            _InfoPill(icon: Icons.timer_outlined, label: '${test.durationMinutes} min', accent: accent),
            _InfoPill(icon: Icons.schedule_rounded, label: '${timeFmt.format(test.openTime)} – ${timeFmt.format(test.closeTime)}', accent: accent),
            if (test.hasGeofence)
              _InfoPill(icon: Icons.location_on_outlined, label: 'Within ${test.geoRadiusM} m', accent: accent),
          ],
        ),
        const SizedBox(height: 20),
        if (test.qrRotating)
          const Text(
            'This code changes every 30 seconds. Project or hold up this screen — a screenshot will not work for students.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _saveToDevice(context, qrKey),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _share(context, qrKey),
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share'),
                  style: ElevatedButton.styleFrom(backgroundColor: accent),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _CodeChip extends StatelessWidget {
  final String code;
  final Color accent;
  const _CodeChip({required this.code, required this.accent});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                code,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: accent, fontSize: 16, fontWeight: FontWeight.w800, fontFamily: 'monospace', letterSpacing: 2),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.copy_rounded, size: 13, color: accent),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  const _InfoPill({required this.icon, required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
