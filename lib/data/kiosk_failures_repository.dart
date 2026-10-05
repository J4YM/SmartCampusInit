import 'package:dashboard_layout/dashboard_layout.dart' show KioskSyncFailure;
import 'package:supabase_flutter/supabase_flutter.dart';

class KioskFailuresRepositoryException implements Exception {
  KioskFailuresRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Reads and dismisses the offline-sync failures the kiosk reports to
/// `kiosk_sync_failures` (supabase/add_kiosk_sync_failures.sql). Shared by the
/// IT Technician and Admin dashboards.
class KioskFailuresRepository {
  KioskFailuresRepository(this._client);

  final SupabaseClient _client;

  static const _columns = 'id, reader_usb_serial, kind, rfid_uid, student_name, '
      'occurred_at, reason, status, reported_at, dismissed_at, dismissed_by, '
      'dismiss_note';

  /// Open and dismissed items, newest report first. Capped so a long history
  /// can't make the panel slow; open items are always the most recent.
  Future<List<KioskSyncFailure>> fetch({int limit = 300}) async {
    try {
      final rows = await _client
          .from('kiosk_sync_failures')
          .select(_columns)
          .order('reported_at', ascending: false)
          .limit(limit);
      return [
        for (final raw in rows as List<dynamic>)
          KioskSyncFailure.fromJson(raw as Map<String, dynamic>),
      ];
    } on PostgrestException catch (e) {
      throw KioskFailuresRepositoryException(e.message);
    }
  }

  /// Dismisses [ids]. Goes through `dismiss_kiosk_sync_failures`, the only
  /// write path — it rejects signed-in accounts that aren't Admin or
  /// IT_Technician. [dismissedBy] is only used for demo accounts (which have
  /// no Supabase session); real accounts are recorded by their profile name.
  /// Returns how many open items were dismissed.
  Future<int> dismiss(
    List<String> ids, {
    String? note,
    String? dismissedBy,
  }) async {
    if (ids.isEmpty) return 0;
    try {
      final n = await _client.rpc('dismiss_kiosk_sync_failures', params: {
        'p_ids': ids,
        'p_note': note,
        'p_dismissed_by': dismissedBy,
      });
      return (n as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      throw KioskFailuresRepositoryException(e.message);
    }
  }
}
