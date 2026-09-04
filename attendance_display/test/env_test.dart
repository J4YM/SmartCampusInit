import 'package:attendance_display/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configured is false until every required value is set', () {
    AttendanceEnv.supabaseUrl = '';
    AttendanceEnv.supabaseAnonKey = '';
    AttendanceEnv.serviceEmail = '';
    AttendanceEnv.servicePassword = '';
    AttendanceEnv.readerUsbSerial = '';
    expect(AttendanceEnv.configured, isFalse);

    AttendanceEnv.supabaseUrl = 'https://example.supabase.co';
    AttendanceEnv.supabaseAnonKey = 'anon-key';
    AttendanceEnv.serviceEmail = 'attendance-display@internal.local';
    AttendanceEnv.servicePassword = 'secret';
    AttendanceEnv.readerUsbSerial = 'ATTENDANCE-ENTRANCE-001';
    expect(AttendanceEnv.configured, isTrue);
  });
}
