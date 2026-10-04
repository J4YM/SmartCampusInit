import 'package:capstone_dashboard/kiosk/supabase_kiosk_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  bool permanent(String? code) => SupabaseKioskRemote.isPermanentPostgrestError(
        PostgrestException(message: 'm', code: code),
      );

  test('raise exception from record_rfid_tap (P0001) is a permanent rejection', () {
    expect(permanent('P0001'), isTrue);
  });

  test('permission and data errors are permanent', () {
    expect(permanent('42501'), isTrue);
    expect(permanent('22P02'), isTrue);
    expect(permanent('23503'), isTrue);
  });

  test('server/gateway errors are transient', () {
    expect(permanent('500'), isFalse);
    expect(permanent('502'), isFalse);
    expect(permanent('503'), isFalse);
    expect(permanent('504'), isFalse);
    expect(permanent(null), isFalse);
  });

  test('PostgREST connection errors are transient, request errors permanent', () {
    expect(permanent('PGRST000'), isFalse);
    expect(permanent('PGRST002'), isFalse);
    expect(permanent('PGRST202'), isTrue);
  });
}
