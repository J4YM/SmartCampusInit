import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:signature/signature.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

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
                'Capture Signature',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: ItTechnicianColors.rowText(context),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildBody(context)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: ItTechnicianColors.dangerRed,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildActions(context),
            ],
          ),
        ),
      ),
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

  static TextStyle _buttonTextStyle() =>
      GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600);

  Widget _buildActions(BuildContext context) {
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
              style: FilledButton.styleFrom(backgroundColor: ItTechnicianColors.azureBlue),
              child: Text('Use Signature', style: _buttonTextStyle()),
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
          child: OutlinedButton(
            onPressed: () => _controller.clear(),
            child: Text('Clear', style: _buttonTextStyle()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: _capture,
            style: FilledButton.styleFrom(backgroundColor: ItTechnicianColors.azureBlue),
            child: Text('Done', style: _buttonTextStyle()),
          ),
        ),
      ],
    );
  }
}
