import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

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

  Future<void> _initCamera() async {
    setState(() => _error = null);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this computer.');
        return;
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
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
      final message = e.toString().contains('cameraNotReadable')
          ? 'Could not open the camera — it looks like another app or '
              'browser tab (Zoom, Teams, the Camera app, another tab) is '
              'already using it. Close that, then try again.'
          : 'Could not open the camera: $e';
      if (mounted) setState(() => _error = message);
    }
  }

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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 480,
        height: 420,
        child: BentoCard(
          backgroundColor: ItTechnicianColors.card(context),
          borderColor: ItTechnicianColors.cardBorder(context),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Capture Student Photo',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: ItTechnicianColors.rowText(context),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildBody(context)),
              const SizedBox(height: 12),
              _buildActions(context),
            ],
          ),
        ),
      ),
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

  static TextStyle _buttonTextStyle() =>
      GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600);

  Widget _buildActions(BuildContext context) {
    if (_error != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: _buttonTextStyle()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => setState(() {
                _initializeFuture = _initCamera();
              }),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              style: FilledButton.styleFrom(
                backgroundColor: ItTechnicianColors.azureBlue,
              ),
              label: Text('Retry', style: _buttonTextStyle()),
            ),
          ),
        ],
      );
    }

    if (_capturedBytes != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _retake,
              child: Text('Retake', style: _buttonTextStyle()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_capturedBytes),
              style: FilledButton.styleFrom(
                backgroundColor: ItTechnicianColors.azureBlue,
              ),
              child: Text('Use Photo', style: _buttonTextStyle()),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: _buttonTextStyle()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: _controller == null ? null : _capture,
            style: FilledButton.styleFrom(
              backgroundColor: ItTechnicianColors.azureBlue,
            ),
            child: Text('Capture', style: _buttonTextStyle()),
          ),
        ),
      ],
    );
  }
}
