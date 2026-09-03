import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

/// Invisible, permanently-focused capture field for a USB keyboard-wedge
/// RFID reader — the reader "types" the UID followed by Enter. Calls
/// `record_rfid_tap` directly. Temporary: Task 7 replaces this with a
/// device-filtered Raw Input capture that doesn't depend on window focus.
class ReaderInputCapture extends StatefulWidget {
  const ReaderInputCapture({super.key, required this.child});

  final Widget child;

  @override
  State<ReaderInputCapture> createState() => _ReaderInputCaptureState();
}

class _ReaderInputCaptureState extends State<ReaderInputCapture> {
  final _focusNode = FocusNode();
  final _controller = TextEditingController();

  Future<void> _handleSubmit(String value) async {
    final uid = value.trim();
    _controller.clear();
    _focusNode.requestFocus();
    if (uid.isEmpty) return;
    try {
      await Supabase.instance.client.rpc('record_rfid_tap', params: {
        'p_reader_usb_serial': AttendanceEnv.readerUsbSerial,
        'p_rfid_uid': uid,
      });
    } catch (_) {
      // A misread/unknown card is a data-quality signal server-side
      // (record_rfid_tap logs it with student_id null), not something
      // this unattended display can act on — nothing to surface here.
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          width: 0,
          height: 0,
          child: Offstage(
            child: TextField(
              focusNode: _focusNode,
              controller: _controller,
              autofocus: true,
              onSubmitted: _handleSubmit,
              onTapOutside: (_) => _focusNode.requestFocus(),
              inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
            ),
          ),
        ),
      ],
    );
  }
}
