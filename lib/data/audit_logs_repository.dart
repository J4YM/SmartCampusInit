import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads `audit_logs` (see supabase/add_admin_dashboard_schema.sql) — backs
/// the Admin Dashboard's Audit & Privacy Logs page. Read-only: rows are
/// written from across the app via [AuditLogger], not from this page.
class AuditLogsRepository {
  AuditLogsRepository(this._client);

  final SupabaseClient _client;

  /// Most recent [limit] entries. The page's own search/severity/role/date
  /// filters run client-side over this batch (matching how the rest of its
  /// UI already worked before being wired up) rather than a server-side
  /// paginated query.
  Future<List<AuditLogModel>> fetchRecent({int limit = 500}) async {
    final rows = await _client
        .from('audit_logs')
        .select(
          'id, occurred_at, actor_email, actor_role, action, ip_address, record_id, severity',
        )
        .order('occurred_at', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return AuditLogModel(
        id: row['id'] as String,
        timestamp: DateTime.parse(row['occurred_at'] as String),
        userEmail: row['actor_email'] as String? ?? 'Unknown',
        userRole: row['actor_role'] as String? ?? 'Unknown',
        actionExecuted: row['action'] as String,
        ipAddress: row['ip_address'] as String? ?? '--',
        recordId: row['record_id'] as String? ?? '--',
        severity: row['severity'] as String? ?? 'INFO',
      );
    }).toList();
  }
}
