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
      if (mounted) setState(() => _error = 'Could not open the camera: $e');
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 480,
        height: 420,
        child: Padding(
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

  Widget _buildActions(BuildContext context) {
    if (_capturedBytes != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _retake,
              child: const Text('Retake'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_capturedBytes),
              style: FilledButton.styleFrom(
                backgroundColor: ItTechnicianColors.azureBlue,
              ),
              child: const Text('Use Photo'),
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
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: _controller == null ? null : _capture,
            style: FilledButton.styleFrom(
              backgroundColor: ItTechnicianColors.azureBlue,
            ),
            child: const Text('Capture'),
          ),
        ),
      ],
    );
  }
}
