import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'tap_display_data.dart';

/// Subscribes to Realtime inserts on `rfid_tap_events` for this monitor's
/// own reader, resolves each into [TapDisplayData], and emits it — the UI
/// (Task 5) just listens to [stream].
class TapFeedController {
  TapFeedController(this._client);

  final SupabaseClient _client;
  final _controller = StreamController<TapDisplayData>.broadcast();
  RealtimeChannel? _channel;
  String? _readerId;

  Stream<TapDisplayData> get stream => _controller.stream;

  Future<void> start() async {
    final reader = await _client
        .from('rfid_readers')
        .select('id')
        .eq('usb_serial', AttendanceEnv.readerUsbSerial)
        .maybeSingle();
    _readerId = reader?['id'] as String?;
    if (_readerId == null) return;

    _channel = _client
        .channel('public:rfid_tap_events:attendance_display')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'rfid_tap_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'reader_id',
            value: _readerId,
          ),
          callback: (payload) => _handleTap(payload.newRecord),
        )
        .subscribe();
  }

  Future<void> _handleTap(Map<String, dynamic> row) async {
    final studentId = row['student_id'] as String?;
    final direction = row['tap_direction'] as String? ?? 'in';

    if (studentId == null) {
      _controller.add(formatTapDisplayData(
        firstName: '',
        lastName: '',
        sectionName: '',
        photoSignedUrl: null,
        direction: direction,
      ));
      return;
    }

    final student = await _client
        .from('students')
        .select(
          'photo_path, profiles(first_name, last_name), sections(name)',
        )
        .eq('id', studentId)
        .maybeSingle();
    if (student == null) return;

    final profile = student['profiles'] as Map<String, dynamic>?;
    final section = student['sections'] as Map<String, dynamic>?;
    final photoPath = student['photo_path'] as String?;

    String? signedUrl;
    if (photoPath != null && photoPath.isNotEmpty) {
      signedUrl = await _client.storage
          .from('student-photos')
          .createSignedUrl(photoPath, 300);
    }

    _controller.add(formatTapDisplayData(
      firstName: profile?['first_name'] as String? ?? '',
      lastName: profile?['last_name'] as String? ?? '',
      sectionName: section?['name'] as String? ?? '',
      photoSignedUrl: signedUrl,
      direction: direction,
    ));
  }

  Future<void> dispose() async {
    final channel = _channel;
    if (channel != null) await _client.removeChannel(channel);
    await _controller.close();
  }
}
