import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';

class NotificationsRepositoryException implements Exception {
  NotificationsRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Reads/writes the centralized `notifications` table (see
/// supabase/add_notifications_schema.sql) — backs every dashboard's bell
/// (Discipline Officer, Guidance Counselor, Professor, Admin) plus the
/// "Send Notification" buttons on the Admin Dashboard's Notifications page.
class NotificationsRepository {
  NotificationsRepository(this._client);

  final SupabaseClient _client;

  /// Every notification visible to [userId] holding [role]: broadcasts to
  /// [role] plus anything sent directly to [userId], newest first. [userId]
  /// is optional so demo/static accounts with no real Supabase Auth id can
  /// still fall back to role-only broadcasts (matches the RLS policy in
  /// add_notifications_user_targeting.sql, which does the same OR for the
  /// server-enforced authenticated case).
  Future<List<NotificationItemModel>> fetchForRole(
    AppRole role, {
    String? userId,
  }) async {
    var query = _client
        .from('notifications')
        .select('id, title, message, created_at, read_at')
        .eq('target_role', appRoleToDbValue(role));
    if (userId != null) {
      query = query.or('user_id.is.null,user_id.eq.$userId');
    } else {
      query = query.filter('user_id', 'is', null);
    }
    final rows = await query.order('created_at', ascending: false);

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return NotificationItemModel(
        id: row['id'] as String,
        title: row['title'] as String,
        message: row['message'] as String,
        timestamp: DateTime.parse(row['created_at'] as String),
        isRead: row['read_at'] != null,
      );
    }).toList();
  }

  /// Sends a notification to every dashboard for [targetRole] (a broadcast)
  /// — the action behind each "Automated Trigger Rule" button on the
  /// Notifications page — or, when [targetUserId] is supplied, to that one
  /// person only. [targetRole] is still required either way (see
  /// add_notifications_user_targeting.sql) so every role-based read/update
  /// path keeps working unchanged for direct sends too.
  Future<void> send({
    required AppRole targetRole,
    required String title,
    required String message,
    String? targetUserId,
  }) async {
    try {
      await _client.from('notifications').insert({
        'target_role': appRoleToDbValue(targetRole),
        'title': title,
        'message': message,
        if (targetUserId != null) 'user_id': targetUserId,
      });
    } on PostgrestException catch (e) {
      throw NotificationsRepositoryException(e.message);
    }
  }

  /// Marks every one of [role]'s currently-unread notifications read (both
  /// broadcasts and, when [userId] is supplied, direct messages to them) —
  /// behind each bell's "View all notifications" action.
  Future<void> markAllReadForRole(AppRole role, {String? userId}) async {
    try {
      var query = _client
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('target_role', appRoleToDbValue(role));
      if (userId != null) {
        query = query.or('user_id.is.null,user_id.eq.$userId');
      } else {
        query = query.filter('user_id', 'is', null);
      }
      await query.filter('read_at', 'is', null);
    } on PostgrestException catch (e) {
      throw NotificationsRepositoryException(e.message);
    }
  }
}
