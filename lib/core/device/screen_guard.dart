import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Blocks screenshots / screen recording / recent-apps thumbnails on
/// Android while a test is on screen (FLAG_SECURE, see MainActivity.kt).
/// No-op on other platforms.
class ScreenGuard {
  ScreenGuard._();
  static const _channel = MethodChannel('aptiqr/secure');

  // Reference-counted: the question and review screens overlap briefly
  // during pushReplacement, and the flag must stay on across that hand-off.
  static int _holders = 0;

  static Future<void> enable() async {
    _holders++;
    if (_holders == 1) await _call('enable');
  }

  static Future<void> disable() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _call('disable');
  }

  static Future<void> _call(String method) async {
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
      await _channel.invokeMethod(method);
    } catch (_) {
      // Never let a guard failure break the test flow.
    }
  }
}
