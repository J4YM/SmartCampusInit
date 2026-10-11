import 'dart:async';
import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../topaz/topaz_signature_pad.dart';

enum _PadMode { probing, pad, canvas }

/// Full-screen signature capture. When a [padClient] is supplied and the
/// hardware pad is reachable, the signature is captured on the pad; otherwise
/// (or if the user switches) it is drawn with mouse/touch/stylus on screen.
/// Structurally mirrors [WebcamCaptureDialog] (Clear/Retake, "Use Signature").
/// Pops with the captured PNG bytes, or `null` if closed without
/// capturing anything.
///
/// The dialog does not dispose [padClient]; the caller owns it.
class SignatureCaptureDialog extends StatefulWidget {
  const SignatureCaptureDialog({super.key, this.padClient});

  final SignaturePadClient? padClient;

  @override
  State<SignatureCaptureDialog> createState() =>
      _SignatureCaptureDialogState();
}

class _SignatureCaptureDialogState extends State<SignatureCaptureDialog> {
  // No export background: the PNG is the ink alone on a transparent
  // background, so it sits on the ID card's own colour.
  final _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
  );
  late _PadMode _mode =
      widget.padClient == null ? _PadMode.canvas : _PadMode.probing;
  Uint8List? _capturedBytes;
  String? _error;
  String? _notice;
  int _points = 0;
  Timer? _poll;
  bool _polling = false;

  SignaturePadClient get _pad => widget.padClient!;

  @override
  void initState() {
    super.initState();
    if (_mode == _PadMode.probing) _probe();
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (_mode == _PadMode.pad && _capturedBytes == null) {
      unawaited(_pad.endCapture().catchError((_) {}));
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    var ok = false;
    try {
      ok = await _pad.isAvailable();
      if (ok) await _pad.beginCapture();
    } catch (_) {
      ok = false;
    }
    if (!mounted) {
      if (ok) unawaited(_pad.endCapture().catchError((_) {}));
      return;
    }
    setState(() {
      _mode = ok ? _PadMode.pad : _PadMode.canvas;
      _notice = ok
          ? null
          : 'Topaz signature pad not detected — using the on-screen board.';
    });
    if (ok) _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (_polling) return;
      _polling = true;
      try {
        final count = await _pad.pointCount();
        if (mounted && _mode == _PadMode.pad && count != _points) {
          setState(() => _points = count);
        }
      } catch (_) {
        _poll?.cancel();
        if (mounted) {
          setState(() => _error = 'Lost connection to the signature pad.');
        }
      } finally {
        _polling = false;
      }
    });
  }

  Future<void> _capture() async {
    if (_mode == _PadMode.pad) return _capturePad();
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

  Future<void> _capturePad() async {
    try {
      if (await _pad.pointCount() == 0) {
        if (mounted) {
          setState(() => _error = 'Sign on the pad before continuing.');
        }
        return;
      }
      final bytes = await _pad.capturePng();
      _poll?.cancel();
      await _pad.endCapture();
      if (!mounted) return;
      setState(() {
        _capturedBytes = bytes;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not capture the signature: $e');
      }
    }
  }

  Future<void> _retake() async {
    if (_mode == _PadMode.pad) {
      try {
        await _pad.beginCapture();
        _startPolling();
      } catch (e) {
        if (mounted) {
          setState(() => _error = 'Could not restart the signature pad: $e');
        }
        return;
      }
    } else {
      _controller.clear();
    }
    if (mounted) {
      setState(() {
        _capturedBytes = null;
        _points = 0;
        _error = null;
      });
    }
  }

  Future<void> _clear() async {
    if (_mode == _PadMode.pad) {
      try {
        await _pad.clear();
      } catch (e) {
        if (mounted) setState(() => _error = 'Could not clear the pad: $e');
        return;
      }
      if (mounted) {
        setState(() {
          _points = 0;
          _error = null;
        });
      }
    } else {
      _controller.clear();
    }
  }

  Future<void> _switchToCanvas() async {
    _poll?.cancel();
    unawaited(_pad.endCapture().catchError((_) {}));
    setState(() {
      _mode = _PadMode.canvas;
      _notice = null;
      _error = null;
    });
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
          if (_notice != null) ...[
            Text(_notice!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
          ],
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
      // The signature itself is transparent; show it on paper so the ink
      // reads whatever the dialog's theme.
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: Colors.white,
          child: Image.memory(_capturedBytes!, fit: BoxFit.contain),
        ),
      );
    }
    switch (_mode) {
      case _PadMode.probing:
        return const Center(child: CircularProgressIndicator());
      case _PadMode.pad:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.draw_outlined, size: 48),
              const SizedBox(height: 12),
              Text('Sign on the Topaz pad',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(_points == 0
                  ? 'Waiting for pen input…'
                  : '$_points points captured'),
            ],
          ),
        );
      case _PadMode.canvas:
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: Colors.white,
            child:
                Signature(controller: _controller, backgroundColor: Colors.white),
          ),
        );
    }
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
    final cancel = AppPopupSecondaryButton(
      label: 'Cancel',
      onPressed: () => Navigator.of(context).pop(),
    );
    if (_mode == _PadMode.probing) return [cancel];
    return [
      cancel,
      AppPopupSecondaryButton(label: 'Clear', onPressed: _clear),
      if (_mode == _PadMode.pad)
        AppPopupSecondaryButton(
          label: 'Use On-Screen Board',
          onPressed: _switchToCanvas,
        ),
      AppPopupPrimaryButton(label: 'Done', onPressed: _capture),
    ];
  }
}
