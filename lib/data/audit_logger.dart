import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';

/// Writes to `audit_logs` (see supabase/add_admin_dashboard_schema.sql) —
/// the "sensitive data access" trail named in lib/admin/admin_module_scope.dart
/// (RA 10173). One instance per signed-in actor; construct with whatever
/// identity the calling connected page already has (static demo accounts
/// and real Microsoft-authenticated accounts both work — see [actorId]).
///
/// Best-effort by design: a logging failure is swallowed (and printed in
/// debug builds) rather than surfaced, since the audit trail must never be
/// the reason a real action — resolving a violation, approving a staff
/// account — fails to go through.
class AuditLogger {
  const AuditLogger(
    this._client, {
    required this.actorId,
    required this.actorEmail,
    required this.actorRole,
  });

  final SupabaseClient _client;

  /// `profiles.id` of the signed-in user, or `null` for a static demo
  /// account (lib/auth/static_demo_accounts.dart) — those have no real
  /// Supabase Auth identity, so there's no valid uuid to record here
  /// (`audit_logs.actor_id` is nullable for exactly this reason).
  final String? actorId;

  /// Best available human-readable identifier — the real email for a
  /// Microsoft-authenticated account, or the demo username (e.g. `admin`)
  /// otherwise.
  final String actorEmail;

  final AppRole actorRole;

  Future<void> log({
    required String action,
    String? recordId,
    String severity = 'INFO',
  }) async {
    try {
      await _client.from('audit_logs').insert({
        'actor_id': actorId,
        'actor_email': actorEmail,
        'actor_role': appRoleToDbValue(actorRole),
        'action': action,
        'record_id': recordId,
        'severity': severity,
      });
    } catch (e) {
      debugPrint('Could not write audit log ("$action"): $e');
    }
  }
}
