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

  /// Every notification targeted at [role], newest first.
  Future<List<NotificationItemModel>> fetchForRole(AppRole role) async {
    final rows = await _client
        .from('notifications')
        .select('id, title, message, created_at, read_at')
        .eq('target_role', appRoleToDbValue(role))
        .order('created_at', ascending: false);

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

  /// Sends a notification to every dashboard for [targetRole] — the action
  /// behind each "Automated Trigger Rule" button on the Notifications page.
  Future<void> send({
    required AppRole targetRole,
    required String title,
    required String message,
  }) async {
    try {
      await _client.from('notifications').insert({
        'target_role': appRoleToDbValue(targetRole),
        'title': title,
        'message': message,
      });
    } on PostgrestException catch (e) {
      throw NotificationsRepositoryException(e.message);
    }
  }

  /// Marks every one of [role]'s currently-unread notifications read —
  /// behind each bell's "View all notifications" action.
  Future<void> markAllReadForRole(AppRole role) async {
    try {
      await _client
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('target_role', appRoleToDbValue(role))
          .filter('read_at', 'is', null);
    } on PostgrestException catch (e) {
      throw NotificationsRepositoryException(e.message);
    }
  }
}
