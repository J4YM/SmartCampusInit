import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rfid_raw_input_windows/rfid_raw_input_windows.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

/// Invisible, permanently-focused capture field for a USB keyboard-wedge
/// RFID reader — the reader "types" the UID followed by Enter. Calls
/// `record_rfid_tap` directly.
///
/// Primary capture is the Windows Raw Input API (`RfidRawInputReader`,
/// Task 7), which filters to the specific reader device by vendor/product
/// id and keeps working regardless of which window currently has OS
/// focus. The focus-based text field below (Task 6) stays wired up as a
/// documented fallback for whenever Raw Input hasn't actually delivered a
/// tap yet (e.g. the vendor/product id isn't configured in `.env`, the
/// device wasn't found, or it was found but events aren't reaching the
/// plugin for some other reason) — this keeps the display working even
/// before Raw Input is confirmed reliable in the field. The fallback is
/// only stood down once a real tap has come through Raw Input, not merely
/// once the device was found — see `_rawInputDelivering` below.
class ReaderInputCapture extends StatefulWidget {
  const ReaderInputCapture({super.key, required this.child});

  final Widget child;

  @override
  State<ReaderInputCapture> createState() => _ReaderInputCaptureState();
}

class _ReaderInputCaptureState extends State<ReaderInputCapture> {
  final _focusNode = FocusNode();
  final _controller = TextEditingController();

  StreamSubscription<String>? _rawInputSubscription;

  // True only once Raw Input has actually delivered at least one decoded
  // tap — NOT once `deviceFound` reports the device was registered.
  // `deviceFound` only confirms native-side device matching/registration
  // succeeded; it says nothing about whether WM_INPUT events are actually
  // reaching the plugin (e.g. a focus-routing issue would still leave
  // `deviceFound` true while no tap ever arrives). Gating the fallback on
  // `deviceFound` alone could silently disable the one path that works.
  bool _rawInputDelivering = false;

  @override
  void initState() {
    super.initState();
    _initRawInput();
  }

  Future<void> _initRawInput() async {
    final vendorId = AttendanceEnv.readerVendorId;
    final productId = AttendanceEnv.readerProductId;
    // Vendor/product id not configured — stay on the focus-based fallback
    // only, same as before Task 7.
    if (vendorId == 0 || productId == 0) return;

    try {
      // Only used to decide whether it's worth subscribing at all; the
      // actual fallback-suppression decision waits for a real tap below.
      await RfidRawInputReader.deviceFound(vendorId, productId);
    } catch (_) {
      // No native Raw Input support available (not running on Windows, or
      // the plugin isn't registered in this build) — fall back silently
      // to the focus-based text field, exactly like Task 6.
      return;
    }
    if (!mounted) return;

    _rawInputSubscription = RfidRawInputReader.taps(vendorId, productId).listen(
      (uid) {
        // A tap actually arrived via Raw Input: it's now proven to work,
        // so the focus-based field can stand down.
        if (mounted && !_rawInputDelivering) {
          setState(() => _rawInputDelivering = true);
        }
        _handleSubmit(uid);
      },
      onError: (_) {
        // Stream failure: drop back to the focus-based fallback rather
        // than leaving the display uncapturing.
        if (mounted) setState(() => _rawInputDelivering = false);
      },
    );
  }

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

  void _handleTextFieldSubmit(String value) {
    // Once Raw Input has actually delivered a tap, it's the proven,
    // authoritative source — ignore the focus-based field so the same
    // physical tap (whose keystrokes still land here too whenever this
    // window happens to have OS focus) isn't processed twice.
    if (_rawInputDelivering) {
      _controller.clear();
      _focusNode.requestFocus();
      return;
    }
    _handleSubmit(value);
  }

  @override
  void dispose() {
    _rawInputSubscription?.cancel();
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
              onSubmitted: _handleTextFieldSubmit,
              onTapOutside: (_) => _focusNode.requestFocus(),
              inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
            ),
          ),
        ),
      ],
    );
  }
}
