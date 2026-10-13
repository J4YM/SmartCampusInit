import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel, NotificationReplySender;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../data/technical_issues_repository.dart';
import '../env.dart';
import 'session_controller.dart';

/// The reply sender for the signed-in person — see
/// [buildTechnicalIssueReplySender]. Null when nobody is signed in or there is
/// no backend to write the reply to. Set on
/// `NotificationReplyHandler.current` whenever the session changes.
NotificationReplySender? replySenderFor(SessionController session) {
  final user = session.user;
  if (user == null || !AppEnv.supabaseConfigured) return null;
  final repo = TechnicalIssuesRepository(Supabase.instance.client);
  return buildTechnicalIssueReplySender(
    role: user.role,
    userId: user.id,
    findReportId: repo.findReportIdForNotification,
    addComment: ({
      required reportId,
      required message,
      required authorId,
      required authorRole,
    }) async {
      await repo.addComment(
        reportId: reportId,
        message: message,
        authorId: authorId,
        authorRole: authorRole,
      );
    },
  );
}

/// Profile ids the static demo accounts post replies as — the same system
/// profiles each dashboard already files technical-issue reports under (a
/// demo account has no real `profiles.id`, and `technical_issue_comments.
/// author_id` references `profiles`). Keep in sync with the connected pages'
/// own `_demo*ProfileId` constants.
const _demoProfileIds = <AppRole, String>{
  AppRole.administrator: '00000000-0000-4000-8000-000000000001',
  AppRole.teacher: '00000000-0000-4000-8000-000000000002',
  AppRole.registrar: '00000000-0000-4000-8000-000000000003',
  AppRole.itTechnician: '00000000-0000-4000-8000-000000000099',
};

/// What the notification popup needs from the technical-issue backend.
/// (Function types, not the repository itself, so the reply rules are
/// testable without a database.)
typedef FindReportId = Future<String?> Function({
  required String message,
  String? reporterId,
});
typedef AddReportComment = Future<void> Function({
  required String reportId,
  required String message,
  required String authorId,
  required String authorRole,
});

/// The reply sender for the person signed in as [role] with profile
/// [userId] (`u_…` for a static demo account).
///
/// It finds which report the notification is about — its own `report_id`, or
/// else a lookup by what it quotes for messages that predate that link — and
/// adds the person's reply as a comment on it. Used by every dashboard's
/// notification popup through `NotificationReplyHandler.current`.
NotificationReplySender buildTechnicalIssueReplySender({
  required AppRole role,
  required String userId,
  required FindReportId findReportId,
  required AddReportComment addComment,
}) {
  final isDemo = userId.startsWith('u_');
  final authorId = isDemo ? _demoProfileIds[role] : userId;

  return (NotificationItemModel item, String message) async {
    if (authorId == null) {
      // A demo account of a role with no system profile has nobody to post
      // the comment as.
      throw StateError('Sign in with a real account to reply.');
    }
    // IT is not the reporter, so its lookup is by wording alone; everyone
    // else is the reporter of what IT is answering.
    final reporterId = role == AppRole.itTechnician ? null : authorId;
    final reportId = item.reportId ??
        await findReportId(message: item.message, reporterId: reporterId);
    if (reportId == null) {
      throw StateError(
          'Could not find the technical issue this message is about.');
    }
    await addComment(
      reportId: reportId,
      message: message,
      authorId: authorId,
      authorRole: appRoleToDbValue(role),
    );
  };
}
