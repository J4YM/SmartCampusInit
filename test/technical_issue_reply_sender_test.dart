import 'package:capstone_dashboard/app/technical_issue_reply.dart';
import 'package:capstone_dashboard/auth/app_role.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter_test/flutter_test.dart';

/// The reply sender every dashboard's notification popup uses: it finds the
/// report a technical-issue message is about and adds the person's reply to
/// it as that person.
void main() {
  NotificationItemModel note({String? reportId, String message = 'okay na?'}) =>
      NotificationItemModel(
        id: 'n1',
        title: 'Update on your technical issue report',
        message: message,
        timestamp: DateTime(2026, 10, 12, 10, 7),
        reportId: reportId,
      );

  late List<Map<String, Object?>> added;
  late List<Map<String, Object?>> lookups;

  setUp(() {
    added = [];
    lookups = [];
  });

  Future<String?> find({required String message, String? reporterId}) async {
    lookups.add({'message': message, 'reporterId': reporterId});
    return 'rep-found';
  }

  Future<void> add({
    required String reportId,
    required String message,
    required String authorId,
    required String authorRole,
  }) async {
    added.add({
      'reportId': reportId,
      'message': message,
      'authorId': authorId,
      'authorRole': authorRole,
    });
  }

  test('a linked notification is answered on its own report, no lookup',
      () async {
    final send = buildTechnicalIssueReplySender(
      role: AppRole.teacher,
      userId: 'real-uuid',
      findReportId: find,
      addComment: add,
    );

    await send(note(reportId: 'rep-9'), 'Salamat po');

    expect(lookups, isEmpty);
    expect(added.single, {
      'reportId': 'rep-9',
      'message': 'Salamat po',
      'authorId': 'real-uuid',
      'authorRole': 'Teacher',
    });
  });

  test('an unlinked one is looked up by what it quotes, among the '
      'reporter\'s own reports', () async {
    final send = buildTechnicalIssueReplySender(
      role: AppRole.registrar,
      userId: 'real-registrar',
      findReportId: find,
      addComment: add,
    );

    await send(note(), 'Opo, okay na');

    expect(lookups.single, {'message': 'okay na?', 'reporterId': 'real-registrar'});
    expect(added.single['reportId'], 'rep-found');
    expect(added.single['authorRole'], 'Registrar');
  });

  test('IT looks up by wording alone and replies as IT_Technician', () async {
    final send = buildTechnicalIssueReplySender(
      role: AppRole.itTechnician,
      userId: 'real-it',
      findReportId: find,
      addComment: add,
    );

    await send(note(), 'Checking now');

    expect(lookups.single['reporterId'], isNull);
    expect(added.single['authorRole'], 'IT_Technician');
    expect(added.single['authorId'], 'real-it');
  });

  test('a demo account replies as its role\'s system profile', () async {
    final cases = {
      AppRole.administrator: ('Admin', '00000000-0000-4000-8000-000000000001'),
      AppRole.teacher: ('Teacher', '00000000-0000-4000-8000-000000000002'),
      AppRole.registrar: ('Registrar', '00000000-0000-4000-8000-000000000003'),
      AppRole.itTechnician:
          ('IT_Technician', '00000000-0000-4000-8000-000000000099'),
    };
    for (final entry in cases.entries) {
      added.clear();
      final send = buildTechnicalIssueReplySender(
        role: entry.key,
        userId: 'u_demo',
        findReportId: find,
        addComment: add,
      );
      await send(note(reportId: 'rep-1'), 'Hi');
      expect(added.single['authorRole'], entry.value.$1, reason: '${entry.key}');
      expect(added.single['authorId'], entry.value.$2, reason: '${entry.key}');
    }
  });

  test('a demo account of a role with no system profile cannot reply',
      () async {
    final send = buildTechnicalIssueReplySender(
      role: AppRole.guidanceCounselor,
      userId: 'u_guidance',
      findReportId: find,
      addComment: add,
    );

    await expectLater(send(note(reportId: 'rep-1'), 'Hi'), throwsStateError);
    expect(added, isEmpty);
  });

  test('a message whose report cannot be found fails clearly, nothing sent',
      () async {
    final send = buildTechnicalIssueReplySender(
      role: AppRole.teacher,
      userId: 'real-uuid',
      findReportId: ({required message, reporterId}) async => null,
      addComment: add,
    );

    await expectLater(send(note(), 'Hi'), throwsStateError);
    expect(added, isEmpty);
  });
}
