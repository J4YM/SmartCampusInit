import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

/// The pause before the second attempt on the same camera (see above).
/// Overridable so tests don't wait it out.
@visibleForTesting
Duration webcamRetryDelay = const Duration(milliseconds: 350);

/// The cameras in the order to try them: real webcams first, then the
/// devices that are usually not what someone means to photograph with —
/// infrared / depth sensors (Windows Hello) and virtual cameras. The
/// relative order inside each group is the system's own.
@visibleForTesting
List<CameraDescription> orderCamerasForOpening(
    List<CameraDescription> cameras) {
  const unlikely = [
    'infrared',
    ' ir ',
    'ir camera',
    'depth',
    'windows hello',
    'virtual',
    'obs',
    'droidcam',
    'snap camera',
    'manycam',
    'xsplit',
  ];
  int penalty(CameraDescription c) {
    final name = ' ${c.name.toLowerCase()} ';
    return unlikely.any(name.contains) ? 1 : 0;
  }

  final indexed = cameras.indexed.toList()
    ..sort((a, b) {
      final byPenalty = penalty(a.$2).compareTo(penalty(b.$2));
      return byPenalty != 0 ? byPenalty : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

/// Full-screen live webcam capture, used to take a student's ID photo.
/// Pops with the captured JPEG bytes on "Use Photo", or `null` if the
/// dialog is closed without capturing anything.
class WebcamCaptureDialog extends StatefulWidget {
  const WebcamCaptureDialog({super.key});

  @override
  State<WebcamCaptureDialog> createState() => _WebcamCaptureDialogState();
}

class _WebcamCaptureDialogState extends State<WebcamCaptureDialog> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  Uint8List? _capturedBytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeFuture = _initCamera();
  }

  /// Opens a camera, trying each one the computer has until one actually
  /// starts. A laptop commonly lists more than the webcam you use — a
  /// Windows Hello IR sensor, a virtual camera (OBS, Snap, a phone app) whose
  /// host app isn't running — and those fail with `cameraNotReadable` even
  /// though the real webcam is fine; taking just `cameras.first` meant the
  /// dialog gave up whenever the first device was one of them.
  Future<void> _initCamera() async {
    setState(() => _error = null);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this computer.');
        return;
      }

      Object? lastError;
      for (final camera in orderCamerasForOpening(cameras)) {
        // Twice per camera: `availableCameras()` has only just stopped its
        // own probe stream on each device, and Windows can take a moment to
        // hand the device back — an immediate open then fails with the same
        // `cameraNotReadable` a genuinely busy camera gives.
        for (var attempt = 0; attempt < 2; attempt++) {
          final controller = CameraController(
            camera,
            ResolutionPreset.medium,
            enableAudio: false,
          );
          try {
            await controller.initialize();
            if (!mounted) {
              await _releaseCamera(controller);
              return;
            }
            setState(() => _controller = controller);
            return;
          } catch (e) {
            lastError = e;
            await _releaseCamera(controller);
            if (!mounted) return;
            if (!_isNotReadable(e)) break; // a different failure: next camera
            if (attempt == 0) {
              await Future<void>.delayed(webcamRetryDelay);
            }
          }
        }
      }
      // Every camera failed — report the last failure.
      throw lastError!;
    } catch (e) {
      // On web this is almost always a `NotReadableError` surfaced as
      // `CameraException(cameraNotReadable, ...)` — the browser granted
      // camera permission, but the OS/driver refused to actually start
      // the stream because something else (another tab, Zoom, Teams,
      // the Windows Camera app) already holds it. Nothing in this app
      // can force that other holder to release the device, so the fix
      // here is a clear explanation plus a retry, not a different API
      // call — confirmed by checking camera_windows's own source, which
      // never produces this error code/text at all (this dialog also
      // runs under camera_windows in the standalone desktop build).
      final message = _isNotReadable(e)
          ? 'Could not open the camera — it looks like another app or '
              'browser tab (Zoom, Teams, the Camera app, another tab) is '
              'already using it. Close that, then try again.'
          : 'Could not open the camera: $e';
      if (mounted) setState(() => _error = message);
    }
  }

  static bool _isNotReadable(Object e) => e.toString().contains('cameraNotReadable');

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _capturedBytes = bytes);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not capture a photo: $e');
    }
  }

  void _retake() => setState(() => _capturedBytes = null);

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) unawaited(_releaseCamera(controller));
    super.dispose();
  }

  // camera_web's CameraController.dispose() is unreliable at actually
  // releasing the underlying browser media stream (flutter/flutter#126823)
  // — left unreleased, the camera hardware stays locked and the *next*
  // attempt to open it fails with CameraException(cameraNotReadable).
  // pausePreview() first, and a try/catch around both calls, gives the
  // stream its best chance to actually let go even if one step throws.
  static Future<void> _releaseCamera(CameraController controller) async {
    try {
      await controller.pausePreview();
    } catch (_) {
      // Best-effort — still attempt dispose below regardless.
    }
    try {
      await controller.dispose();
    } catch (_) {
      // Nothing more we can do if the plugin itself throws on dispose.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: 'Capture Student Photo',
      width: 480,
      // The camera preview needs a fixed height of its own.
      scrollBody: false,
      body: SizedBox(height: 280, child: _buildBody(context)),
      actions: _buildActions(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(color: ItTechnicianColors.dangerRed),
        ),
      );
    }

    if (_capturedBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(_capturedBytes!, fit: BoxFit.contain),
      );
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        final controller = _controller;
        if (snapshot.connectionState != ConnectionState.done ||
            controller == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CameraPreview(controller),
        );
      },
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_error != null) {
      return [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          label: 'Retry',
          icon: Icons.refresh_rounded,
          onPressed: () => setState(() {
            _initializeFuture = _initCamera();
          }),
        ),
      ];
    }

    if (_capturedBytes != null) {
      return [
        AppPopupSecondaryButton(label: 'Retake', onPressed: _retake),
        AppPopupPrimaryButton(
          label: 'Use Photo',
          onPressed: () => Navigator.of(context).pop(_capturedBytes),
        ),
      ];
    }

    return [
      AppPopupSecondaryButton(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(),
      ),
      AppPopupPrimaryButton(
        label: 'Capture',
        onPressed: _controller == null ? null : _capture,
      ),
    ];
  }
}
