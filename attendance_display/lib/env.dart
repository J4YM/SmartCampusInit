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
  }

  static String _pick(String key, String defineFallback) {
    final raw = dotenv.env[key];
    if (raw != null && raw.trim().isNotEmpty) return raw.trim();
    return defineFallback;
  }

  static bool get configured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      serviceEmail.isNotEmpty &&
      servicePassword.isNotEmpty &&
      readerUsbSerial.isNotEmpty;
}
