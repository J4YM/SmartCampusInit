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
  ///
  /// [instanceHint], if non-empty, is matched as a case-insensitive
  /// substring against the device's full interface path (which includes a
  /// per-USB-port instance token Windows assigns, e.g. the segment after
  /// the second `&` in a Device Manager instance ID like
  /// `HID\VID_xxxx&PID_xxxx&MI_00\9&12e896f4&0&0000`).
  ///
  /// This disambiguates two devices sharing a vendor/product id ONLY when
  /// Windows' Raw Input device list actually contains a separate entry for
  /// each. Tested against two literally identical reader units (same
  /// model, same firmware — indistinguishable HID report descriptors):
  /// `GetRawInputDeviceList` returned just ONE entry for the pair no matter
  /// which was plugged in more recently, regardless of USB port — the
  /// other was simply absent from the list, not merely filtered out here.
  /// No instance hint (nor any other per-device filtering built on this
  /// same device list) can recover a device the OS itself isn't reporting.
  /// If your two readers are that similar, this parameter won't help; see
  /// `attendance_display/README.md`'s reader-disambiguation section for
  /// the alternatives (different reader models, separate host PCs, or the
  /// focus-based fallback plus a configured prefix). Leave blank when only
  /// one device with this vendor/product id is ever connected.
  static Stream<String> taps(
    int vendorId,
    int productId, {
    String instanceHint = '',
  }) {
    return _eventChannel
        .receiveBroadcastStream({
          'vendorId': vendorId,
          'productId': productId,
          'instanceHint': instanceHint,
        })
        .map((event) => event as String);
  }

  /// True if the native side found and registered a matching device.
  static Future<bool> deviceFound(
    int vendorId,
    int productId, {
    String instanceHint = '',
  }) async {
    final result = await _methodChannel.invokeMethod<bool>('deviceFound', {
      'vendorId': vendorId,
      'productId': productId,
      'instanceHint': instanceHint,
    });
    return result ?? false;
  }
}
