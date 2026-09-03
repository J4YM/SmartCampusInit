import 'dart:async';
import 'package:flutter/services.dart';

/// Captures keystrokes from one specific USB HID keyboard-wedge device
/// (identified by vendor/product id) via the Windows Raw Input API,
/// regardless of which window currently has focus. Buffers characters
/// until Enter, then emits the completed string.
class RfidRawInputReader {
  RfidRawInputReader._();

  static const _methodChannel = MethodChannel('rfid_raw_input_windows/methods');
  static const _eventChannel = EventChannel('rfid_raw_input_windows/events');

  /// [vendorId]/[productId] identify the target reader (read these off the
  /// physical device — e.g. via Windows Device Manager's Hardware IDs tab,
  /// format `VID_xxxx&PID_xxxx`).
  static Stream<String> taps(int vendorId, int productId) {
    return _eventChannel
        .receiveBroadcastStream({
          'vendorId': vendorId,
          'productId': productId,
        })
        .map((event) => event as String);
  }

  /// True if the native side found and registered a matching device.
  static Future<bool> deviceFound(int vendorId, int productId) async {
    final result = await _methodChannel.invokeMethod<bool>('deviceFound', {
      'vendorId': vendorId,
      'productId': productId,
    });
    return result ?? false;
  }
}
