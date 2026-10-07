import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';


/// Full-screen signature capture — draws with mouse/touch/stylus rather
/// than streaming a camera, but otherwise structurally mirrors
/// [WebcamCaptureDialog] exactly (Clear/Retake, "Use Signature" button).
/// Pops with the captured PNG bytes, or `null` if closed without
/// capturing anything.
class SignatureCaptureDialog extends StatefulWidget {
  const SignatureCaptureDialog({super.key});

  @override
  State<SignatureCaptureDialog> createState() =>
      _SignatureCaptureDialogState();
}

class _SignatureCaptureDialogState extends State<SignatureCaptureDialog> {
  final _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  Uint8List? _capturedBytes;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_controller.isEmpty) {
      setState(() => _error = 'Draw a signature before continuing.');
      return;
    }
    try {
      final bytes = await _controller.toPngBytes();
      if (bytes == null) {
        setState(() => _error = 'Could not capture the signature.');
        return;
      }
      setState(() {
        _capturedBytes = bytes;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not capture the signature: $e');
    }
  }

  void _retake() {
    _controller.clear();
    setState(() => _capturedBytes = null);
  }

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: 'Capture Signature',
      width: 480,
      // The drawing pad needs a fixed height of its own, not a scroll view.
      scrollBody: false,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 260, child: _buildBody(context)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            AppPopupError(_error!),
          ],
        ],
      ),
      actions: _buildActions(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_capturedBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(_capturedBytes!, fit: BoxFit.contain),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: Colors.white,
        child: Signature(controller: _controller, backgroundColor: Colors.white),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_capturedBytes != null) {
      return [
        AppPopupSecondaryButton(label: 'Retake', onPressed: _retake),
        AppPopupPrimaryButton(
          label: 'Use Signature',
          onPressed: () => Navigator.of(context).pop(_capturedBytes),
        ),
      ];
    }
    return [
      AppPopupSecondaryButton(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(),
      ),
      AppPopupSecondaryButton(
        label: 'Clear',
        onPressed: () => _controller.clear(),
      ),
      AppPopupPrimaryButton(label: 'Done', onPressed: _capture),
    ];
  }
}
