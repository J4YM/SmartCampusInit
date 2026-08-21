import 'package:supabase_flutter/supabase_flutter.dart';

class RfidReaderRepositoryException implements Exception {
  RfidReaderRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One row of `rfid_readers` — see add_rfid_reader_network_schema.sql.
class RfidReaderRecord {
  const RfidReaderRecord({
    required this.id,
    required this.label,
    required this.usbSerial,
    required this.location,
    required this.isKioskReader,
    required this.isActive,
    required this.lastSeenAt,
  });

  final String id;
  final String label;
  final String usbSerial;
  final String? location;
  final bool isKioskReader;
  final bool isActive;
  final DateTime? lastSeenAt;

  /// Matches the offline threshold a real health-check would use — no
  /// heartbeat (a tap or an explicit ping) in the last 5 minutes.
  bool get isOnline =>
      lastSeenAt != null &&
      DateTime.now().difference(lastSeenAt!) < const Duration(minutes: 5);

  factory RfidReaderRecord.fromSupabase(Map<String, dynamic> row) {
    return RfidReaderRecord(
      id: row['id'] as String,
      label: row['label'] as String,
      usbSerial: row['usb_serial'] as String,
      location: row['location'] as String?,
      isKioskReader: row['is_kiosk_reader'] as bool? ?? false,
      isActive: row['is_active'] as bool? ?? true,
      lastSeenAt: row['last_seen_at'] == null
          ? null
          : DateTime.parse(row['last_seen_at'] as String),
    );
  }
}

/// What `record_rfid_tap` hands back — see that function's doc comment for
/// the in/out toggle logic this reflects.
class RfidTapResult {
  const RfidTapResult({
    required this.tapId,
    required this.readerId,
    required this.studentId,
    required this.tapDirection,
    required this.tappedAt,
  });

  final String tapId;
  final String readerId;

  /// Null when the tapped card doesn't match any `students.rfid_uid` — the
  /// tap is still logged (see the RPC's doc comment) rather than dropped.
  final String? studentId;

  /// `'in'` or `'out'`.
  final String tapDirection;
  final DateTime tappedAt;

  factory RfidTapResult.fromSupabase(Map<String, dynamic> row) {
    return RfidTapResult(
      tapId: row['tap_id'] as String,
      readerId: row['reader_id'] as String,
      studentId: row['student_id'] as String?,
      tapDirection: row['tap_direction'] as String,
      tappedAt: DateTime.parse(row['tapped_at'] as String),
    );
  }
}

/// Reads/writes the floor-reader network (`rfid_readers`, `rfid_tap_events`)
/// — see add_rfid_reader_network_schema.sql. Both the real central
/// reader-service (tools/rfid_reader_service) and the in-app dev simulator
/// call [recordTap], which is a thin wrapper over the `record_rfid_tap` RPC
/// — the RPC, not this repository, owns the in/out toggle and heartbeat
/// logic, so every caller (Python service, simulator, any future client)
/// gets identical behavior.
class RfidReaderRepository {
  RfidReaderRepository(this._client);

  final SupabaseClient _client;

  static const _readerSelect =
      'id, label, usb_serial, location, is_kiosk_reader, is_active, last_seen_at';

  Future<List<RfidReaderRecord>> fetchReaders({
    bool includeInactive = false,
  }) async {
    var query = _client.from('rfid_readers').select(_readerSelect);
    if (!includeInactive) {
      query = query.eq('is_active', true);
    }
    final rows = await query
        .order('is_kiosk_reader', ascending: false)
        .order('label');
    return (rows as List<dynamic>)
        .map((e) => RfidReaderRecord.fromSupabase(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addReader({
    required String label,
    required String usbSerial,
    String? location,
  }) async {
    try {
      await _client.from('rfid_readers').insert({
        'label': label,
        'usb_serial': usbSerial,
        'location': location,
      });
    } on PostgrestException catch (e) {
      throw RfidReaderRepositoryException(e.message);
    }
  }

  Future<void> updateReader({
    required String id,
    required String label,
    required String usbSerial,
    String? location,
  }) async {
    try {
      await _client.from('rfid_readers').update({
        'label': label,
        'usb_serial': usbSerial,
        'location': location,
      }).eq('id', id);
    } on PostgrestException catch (e) {
      throw RfidReaderRepositoryException(e.message);
    }
  }

  /// Deactivating (never hard-deleting) a reader — see
  /// add_rfid_readers_soft_delete.sql — keeps its `rfid_tap_events` history
  /// intact and stops it from being able to record new taps.
  Future<void> setReaderActive(String id, bool isActive) async {
    try {
      await _client
          .from('rfid_readers')
          .update({'is_active': isActive}).eq('id', id);
    } on PostgrestException catch (e) {
      throw RfidReaderRepositoryException(e.message);
    }
  }

  Future<RfidTapResult> recordTap({
    required String readerUsbSerial,
    required String rfidUid,
    DateTime? tappedAt,
  }) async {
    try {
      final rows = await _client.rpc('record_rfid_tap', params: {
        'p_reader_usb_serial': readerUsbSerial,
        'p_rfid_uid': rfidUid,
        if (tappedAt != null) 'p_tapped_at': tappedAt.toIso8601String(),
      });
      final row = (rows as List<dynamic>).first as Map<String, dynamic>;
      return RfidTapResult.fromSupabase(row);
    } on PostgrestException catch (e) {
      throw RfidReaderRepositoryException(e.message);
    }
  }
}
