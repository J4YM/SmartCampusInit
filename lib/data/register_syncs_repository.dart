import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads `registration_sync_events` (see
/// supabase/add_registration_sync_log_schema.sql) — backs the Admin
/// Dashboard's Register Syncs page. Read-only: every row is written from
/// inside the relevant Postgres RPC/trigger (staff approval, RFID linking,
/// student self-registration/claim), never directly from the app.
class RegisterSyncsRepository {
  RegisterSyncsRepository(this._client);

  final SupabaseClient _client;

  Future<List<RegisterSyncEventModel>> fetchRecent({int limit = 100}) async {
    final rows = await _client
        .from('registration_sync_events')
        .select('id, event_type, detail, occurred_at')
        .order('occurred_at', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .map((row) {
          final type =
              registerSyncEventTypeFromDbValue(row['event_type'] as String?);
          return type == null
              ? null
              : RegisterSyncEventModel(
                  id: row['id'] as String,
                  eventType: type,
                  detail: row['detail'] as String,
                  occurredAt: DateTime.parse(row['occurred_at'] as String),
                );
        })
        .whereType<RegisterSyncEventModel>()
        .toList();
  }
}
