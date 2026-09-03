import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Populated by [AttendanceEnv.resolve] after `.env` loads in `main`.
/// Mirrors the parent app's `lib/env.dart` pattern.
class AttendanceEnv {
  AttendanceEnv._();

  static String supabaseUrl = '';
  static String supabaseAnonKey = '';

  /// Credentials for the dedicated, long-lived Auth user this display
  /// signs in as on startup (needed to read the private `student-photos`
  /// bucket — see supabase/add_student_photos_storage.sql).
  static String serviceEmail = '';
  static String servicePassword = '';

  /// Must match the `usb_serial` of the `rfid_readers` row this monitor's
  /// reader is registered under (see supabase/add_attendance_display_setup.sql).
  static String readerUsbSerial = '';

  /// USB HID vendor/product id of the entrance reader, used by the Windows
  /// Raw Input capture (`RfidRawInputReader`) to filter for this specific
  /// device regardless of window focus. Read these off the physical device
  /// via Windows Device Manager's Hardware IDs tab (format
  /// `VID_xxxx&PID_xxxx`, hex). Left as 0 when unset, which makes
  /// `RfidRawInputReader.deviceFound` report false and the app falls back
  /// to the focus-based `ReaderInputCapture` text field capture.
  static int readerVendorId = 0;
  static int readerProductId = 0;

  static void resolve() {
    supabaseUrl = _pick(
      'SUPABASE_URL',
      const String.fromEnvironment('SUPABASE_URL'),
    );
    supabaseAnonKey = _pick(
      'SUPABASE_ANON_KEY',
      const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    serviceEmail = _pick(
      'SERVICE_EMAIL',
      const String.fromEnvironment('SERVICE_EMAIL'),
    );
    servicePassword = _pick(
      'SERVICE_PASSWORD',
      const String.fromEnvironment('SERVICE_PASSWORD'),
    );
    readerUsbSerial = _pick(
      'READER_USB_SERIAL',
      const String.fromEnvironment('READER_USB_SERIAL'),
    );
    readerVendorId = _pickHex(
      'READER_VENDOR_ID',
      const String.fromEnvironment('READER_VENDOR_ID'),
    );
    readerProductId = _pickHex(
      'READER_PRODUCT_ID',
      const String.fromEnvironment('READER_PRODUCT_ID'),
    );
  }

  static String _pick(String key, String defineFallback) {
    final raw = dotenv.env[key];
    if (raw != null && raw.trim().isNotEmpty) return raw.trim();
    return defineFallback;
  }

  /// Parses a hex vendor/product id, accepting an optional `0x` prefix
  /// (values are read straight off Device Manager's `VID_xxxx&PID_xxxx`).
  /// Returns 0 (unset/invalid) rather than throwing — this is an optional
  /// enhancement, not something that should block startup.
  static int _pickHex(String key, String defineFallback) {
    final raw = _pick(key, defineFallback);
    if (raw.isEmpty) return 0;
    final cleaned = raw.toLowerCase().startsWith('0x') ? raw.substring(2) : raw;
    return int.tryParse(cleaned, radix: 16) ?? 0;
  }

  static bool get configured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      serviceEmail.isNotEmpty &&
      servicePassword.isNotEmpty &&
      readerUsbSerial.isNotEmpty;
}
