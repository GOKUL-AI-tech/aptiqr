import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/constants/app_colors.dart';

/// Full-screen QR scanner. Pops with the decoded string on first match,
/// or null if the user backs out.
Future<String?> showQrScanner(BuildContext context,
    {String title = 'Scan QR code'}) async {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan on a mobile device'),
        content: const Text(
          'QR scanning is not supported in this desktop build. '
          'Go back and use Enter code to enter the code displayed by your faculty, '
          'or scan with AptiQR on Android or iOS.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return null;
  }
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => _QrScannerScreen(title: title)),
  );
}

class _QrScannerScreen extends StatefulWidget {
  final String title;
  const _QrScannerScreen({required this.title});

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  bool _analyzingGalleryImage = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  /// Stop before start, not just start() again. mobile_scanner 5.2.3 (the
  /// version this was originally pinned to) had an open bug where calling
  /// start() on a controller that had errored out — rather than a clean,
  /// never-started one — could itself throw a fresh genericError instead
  /// of actually retrying. stop() is safe to call even if the controller
  /// never successfully started.
  Future<void> _retry() async {
    try {
      await _controller.stop();
    } catch (_) {
      // Ignore — it may never have started in the first place.
    }
    if (!mounted) return;
    try {
      await _controller.start();
    } catch (e) {
      _showSnack('Could not restart the camera: $e');
    }
  }

  /// Fallback for students who don't have a live QR to point a camera
  /// at (a screenshot of the faculty's QR shared in a group chat, a
  /// photo taken earlier, a device with no working camera at all) —
  /// picks an image and decodes it with the same MobileScannerController
  /// via `analyzeImage`, rather than requiring a live camera scan.
  /// file_picker (already a dependency — see question_upload_screen.dart)
  /// is used instead of adding image_picker as a second, overlapping
  /// dependency; FileType.image routes to the system photo picker on
  /// both Android and iOS, which needs no extra runtime permission.
  Future<void> _pickFromGallery() async {
    if (_analyzingGalleryImage || _handled) return;
    setState(() => _analyzingGalleryImage = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) {
        _showSnack('Could not read that image.');
        return;
      }

      final capture = await _controller.analyzeImage(path);
      final value = capture?.barcodes.firstOrNull?.rawValue;
      if (value == null) {
        _showSnack('No QR code found in that image. Try a clearer photo.');
        return;
      }
      if (_handled) return;
      _handled = true;
      if (mounted) Navigator.of(context).pop(value);
    } catch (e) {
      _showSnack('Could not read that image: $e');
    } finally {
      if (mounted) setState(() => _analyzingGalleryImage = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // The global theme (see app_theme.dart's `iconButtonTheme`) sets
        // every IconButton's color to AppColors.textPrimary — a near-
        // black navy meant for icons on light surfaces app-wide. That
        // style resolution wins over this AppBar's own `foregroundColor:
        // Colors.white` for any IconButton specifically (AppBar's
        // foreground/iconTheme only governs plain Icons, not
        // IconButton's own ButtonStyle), so on this black scanner
        // screen both the auto-generated back arrow and the gallery
        // button below rendered near-invisible — present and tappable,
        // just impossible to see against the black app bar. Explicit
        // `leading` + `style` here bypass the global theme instead of
        // relying on ambient color inheritance.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          style: IconButton.styleFrom(foregroundColor: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Choose from gallery',
            style: IconButton.styleFrom(foregroundColor: Colors.white),
            icon: _analyzingGalleryImage
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : const Icon(Icons.photo_library_outlined),
            onPressed: _analyzingGalleryImage ? null : _pickFromGallery,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            // Without this, a failed camera start (permission denied, no
            // camera hardware, camera in use by another app) fell through
            // to mobile_scanner's bare default error widget: a black
            // screen with a tiny "!" icon and zero explanation — which is
            // exactly what made this look broken rather than "needs a
            // permission you haven't granted yet".
            // mobile_scanner 7.x's errorBuilder signature dropped the
            // third `Widget? child` argument that 5.x had — (context,
            // error) now, not (context, error, child).
            errorBuilder: (context, error) => _ScannerError(
              error: error,
              onRetry: _retry,
              onPickFromGallery: _pickFromGallery,
              pickingFromGallery: _analyzingGalleryImage,
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primaryOrange, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: const Text(
              'Point the camera at the QR code displayed by your faculty, '
              'or use the gallery icon above to scan a photo of it instead',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _ScannerError extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onRetry;
  final VoidCallback onPickFromGallery;
  final bool pickingFromGallery;
  const _ScannerError({
    required this.error,
    required this.onRetry,
    required this.onPickFromGallery,
    required this.pickingFromGallery,
  });

  @override
  Widget build(BuildContext context) {
    final isPermission =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    // errorDetails.message carries the actual native platform exception
    // text (e.g. what CameraX/Camera2 actually threw) — errorCode alone
    // is just a coarse bucket ('genericError' covers everything mobile_scanner
    // doesn't recognize as permission/unsupported/etc.), so showing only
    // the code name gave a dead end with no way to diagnose *why* the
    // camera didn't start. Falls back to just the code if the platform
    // didn't attach details.
    final detail = error.errorDetails?.message;
    final message = isPermission
        ? 'Camera permission is off for AptiQR. Enable it in your phone\'s '
            'Settings > Apps > AptiQR > Permissions > Camera, then come back and try again.'
        : 'Could not start the camera (${error.errorCode.name})'
            '${detail != null && detail.isNotEmpty ? ':\n$detail' : ''}\n'
            'Make sure no other app is using it, then try again.';

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded,
                color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54)),
              child: const Text('Try again'),
            ),
            const SizedBox(height: 12),
            // No working camera (permission denied, no hardware, a
            // single-emulator dev setup with no configured virtual
            // camera) previously meant this screen was a dead end — a
            // photo of the QR (or a screenshot shared by faculty) gets
            // decoded the same way a live scan would.
            TextButton.icon(
              onPressed: pickingFromGallery ? null : onPickFromGallery,
              icon: pickingFromGallery
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white70),
                    )
                  : const Icon(Icons.photo_library_outlined,
                      color: Colors.white70, size: 18),
              label: const Text('Choose from gallery instead',
                  style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}
