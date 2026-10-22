import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show EndorsedViolation, EndorsementKind, EscalationReportModel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/escalation/escalation_approvals_view.dart';
import 'package:guidance_counselor_module/pages/student_archive/student_archive_models.dart';
import 'package:guidance_counselor_module/pages/student_archive/student_archive_view.dart';

/// The Endorsement Approvals and Student Archive tabs sit on the app-wide
/// table card (title + subtitle, search, table, footer) and use the shared
/// popups; this pins their behaviour and the title size.
void main() {
  EscalationReportModel report(
    String id,
    String name, {
    String status = 'Pending_GC',
    String? note,
    EndorsementKind kind = EndorsementKind.parentIntervention,
    String? studentId,
  }) =>
      EscalationReportModel(
        kind: kind,
        studentId: studentId,
        id: id,
        studentName: name,
        studentNumber: 'N-$id',
        title: 'Escalation',
        summary: 'Summary for $name',
        message: 'Message for $name',
        channels: const ['sms', 'email'],
        source: 'officer',
        status: status,
        createdAt: DateTime(2026, 10, 1, 9, 30),
        violationCount: 3,
        createdByName: 'Officer Reyes',
        decisionNote: note,
      );

  Future<void> pumpView(WidgetTester tester, Widget view,
      {double width = 1400}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: view)),
    ));
    await tester.pumpAndSettle();
  }

  group('Endorsement Approvals', () {
    final reports = [
      report('d1', 'Decided Dana', status: 'Approved', note: 'Looks right'),
      report('p1', 'Pending Pia'),
      report('p2', 'Pending Paolo'),
    ];

    testWidgets('lists every report on one card, waiting ones first',
        (tester) async {
      await pumpView(tester, EscalationApprovalsView(reports: reports));

      expect(find.text('Endorsement Approvals'), findsOneWidget);
      expect(find.text('3 endorsements | 2 awaiting your approval'), findsOneWidget);

      final pia = tester.getTopLeft(find.text('Pending Pia')).dy;
      final dana = tester.getTopLeft(find.text('Decided Dana')).dy;
      expect(pia, lessThan(dana));
    });

    testWidgets('the card title uses the shared card-title size',
        (tester) async {
      await pumpView(tester, EscalationApprovalsView(reports: reports));
      final title = tester.widget<Text>(find.text('Endorsement Approvals'));
      expect(title.style!.fontSize, kCardTitleFontSizeDesktop);
      expect(title.style!.fontWeight, FontWeight.w600);

      await pumpView(tester, EscalationApprovalsView(reports: reports),
          width: 380);
      final phone = tester.widget<Text>(find.text('Endorsement Approvals'));
      expect(phone.style!.fontSize, kCardTitleFontSizeMobile);
    });

    testWidgets('approving from the row sends the parent message',
        (tester) async {
      EscalationReportModel? decided;
      bool? approved;
      String? sentMessage;
      await pumpView(
        tester,
        EscalationApprovalsView(
          reports: reports,
          onDecide: (r, {required approve, note, message, meetingAt, meetingLocation}) async {
            decided = r;
            approved = approve;
            sentMessage = message;
          },
        ),
      );

      await tester.tap(find.byKey(const ValueKey('approve-p1')));
      await tester.pumpAndSettle();
      expect(find.text('Approve & notify parent'), findsWidgets);
      expect(find.text('Message for Pending Pia'), findsOneWidget);

      await tester.tap(find.byKey(const Key('approve-confirm')));
      await tester.pumpAndSettle();

      expect(decided?.id, 'p1');
      expect(approved, isTrue);
      expect(sentMessage, 'Message for Pending Pia');
    });

    testWidgets('approving sends no meeting unless one is scheduled',
        (tester) async {
      DateTime? gotAt = DateTime(2000);
      await pumpView(
        tester,
        EscalationApprovalsView(
          reports: reports,
          onDecide: (r, {required approve, note, message, meetingAt, meetingLocation}) async {
            gotAt = meetingAt;
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('approve-p1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('escalation-meeting-date')), findsNothing);
      await tester.tap(find.byKey(const Key('approve-confirm')));
      await tester.pumpAndSettle();
      expect(gotAt, isNull);
    });

    testWidgets('approving can schedule a meeting with the parent',
        (tester) async {
      DateTime? gotAt;
      String? where;
      await pumpView(
        tester,
        EscalationApprovalsView(
          reports: reports,
          onDecide: (r, {required approve, note, message, meetingAt, meetingLocation}) async {
            gotAt = meetingAt;
            where = meetingLocation;
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('approve-p1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('escalation-meeting-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('escalation-meeting-date')), findsOneWidget);
      expect(find.byKey(const Key('escalation-meeting-time')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('escalation-meeting-location')), 'Guidance Office');
      await tester.pump();

      await tester.tap(find.byKey(const Key('approve-confirm')));
      await tester.pumpAndSettle();

      expect(gotAt, isNotNull);
      expect(gotAt!.isAfter(DateTime.now()), isTrue);
      expect(gotAt!.hour, 9);
      expect(where, 'Guidance Office');
    });

    EscalationReportModel counseling(String id, String name,
            {String? studentId = 's1'}) =>
        EscalationReportModel(
          id: id,
          studentName: name,
          studentNumber: 'N-$id',
          title: 'Endorsement',
          summary: 'Seems withdrawn.',
          message: '',
          channels: const [],
          source: 'officer',
          status: 'Pending_GC',
          createdAt: DateTime(2026, 10, 1, 9, 30),
          createdByName: 'Officer Reyes',
          kind: EndorsementKind.counseling,
          studentId: studentId,
        );

    testWidgets('the report shows what Guidance is asked for and the reason',
        (tester) async {
      await pumpView(
        tester,
        EscalationApprovalsView(
          reports: [counseling('c1', 'Counseling Cara')],
          onDecide: (r, {required approve, note, message, meetingAt, meetingLocation}) async {},
        ),
      );
      await tester.tap(find.text('Counseling Cara'));
      await tester.pumpAndSettle();

      expect(find.text('Counseling'), findsWidgets);
      expect(find.text('Seems withdrawn.'), findsOneWidget);
      expect(find.text('Message to the parent'), findsNothing);
      expect(find.text('Approve & notify parent'), findsNothing);
      expect(find.byKey(const Key('detail-approve')), findsOneWidget);
    });

    testWidgets('the violation history lists offense, date and status only',
        (tester) async {
      String? askedFor;
      await pumpView(
        tester,
        EscalationApprovalsView(
          reports: [counseling('c1', 'Counseling Cara')],
          onLoadHistory: (r) async {
            askedFor = r.studentId;
            return [
              EndorsedViolation(
                id: 'v1',
                offense: 'Fighting',
                category: 'Major_A',
                status: 'Resolved',
                incidentAt: DateTime(2026, 9, 1, 8),
              ),
            ];
          },
        ),
      );
      await tester.tap(find.text('Counseling Cara'));
      await tester.pumpAndSettle();

      expect(askedFor, 's1');
      expect(find.text('Violation history'), findsOneWidget);
      expect(find.textContaining('Fighting'), findsOneWidget);
      expect(find.textContaining('Resolved'), findsOneWidget);
      expect(find.textContaining(RegExp('sanction', caseSensitive: false)),
          findsNothing);
    });

    testWidgets('a student with no violations says so', (tester) async {
      await pumpView(
        tester,
        EscalationApprovalsView(
          reports: [counseling('c1', 'Counseling Cara')],
          onLoadHistory: (r) async => const [],
        ),
      );
      await tester.tap(find.text('Counseling Cara'));
      await tester.pumpAndSettle();

      expect(find.text('No violations on record'), findsOneWidget);
    });

    testWidgets('a failing history load does not block the endorsement',
        (tester) async {
      await pumpView(
        tester,
        EscalationApprovalsView(
          reports: [counseling('c1', 'Counseling Cara')],
          onLoadHistory: (r) async => throw StateError('offline'),
        ),
      );
      await tester.tap(find.text('Counseling Cara'));
      await tester.pumpAndSettle();

      expect(find.text('Seems withdrawn.'), findsOneWidget);
      expect(find.text('Could not load the violation history'), findsOneWidget);
    });

    testWidgets('approving a counseling endorsement sends no message or meeting',
        (tester) async {
      String? sentMessage = 'unset';
      DateTime? sentMeeting = DateTime(2000);
      bool? approved;
      await pumpView(
        tester,
        EscalationApprovalsView(
          reports: [counseling('c1', 'Counseling Cara')],
          onDecide: (r, {required approve, note, message, meetingAt, meetingLocation}) async {
            approved = approve;
            sentMessage = message;
            sentMeeting = meetingAt;
          },
        ),
      );

      await tester.tap(find.byKey(const ValueKey('approve-c1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('escalation-meeting-toggle')), findsNothing);
      expect(find.text('Message to the parent'), findsNothing);

      await tester.tap(find.byKey(const Key('approve-confirm')));
      await tester.pumpAndSettle();

      expect(approved, isTrue);
      expect(sentMessage, isNull);
      expect(sentMeeting, isNull);
    });

    testWidgets('the status filter calls a declined endorsement Declined',
        (tester) async {
      await pumpView(tester, EscalationApprovalsView(reports: reports));
      expect(find.text('Rejected'), findsNothing);
    });

    testWidgets('rejecting needs a reason, which is sent back',
        (tester) async {
      String? sentNote;
      bool? approved;
      await pumpView(
        tester,
        EscalationApprovalsView(
          reports: reports,
          onDecide: (r, {required approve, note, message, meetingAt, meetingLocation}) async {
            approved = approve;
            sentNote = note;
          },
        ),
      );

      await tester.tap(find.byKey(const ValueKey('reject-p2')));
      await tester.pumpAndSettle();

      FilledButton confirm() => tester.widget<FilledButton>(
          find.descendant(
              of: find.byKey(const Key('reject-confirm')),
              matching: find.byType(FilledButton)));
      expect(confirm().onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'Not enough detail');
      await tester.pump();
      expect(confirm().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('reject-confirm')));
      await tester.pumpAndSettle();

      expect(approved, isFalse);
      expect(sentNote, 'Not enough detail');
    });

    testWidgets('a row opens the full report, with decide buttons only while '
        'it is waiting', (tester) async {
      await pumpView(
        tester,
        EscalationApprovalsView(
            reports: reports, onDecide: (r, {required approve, note, message, meetingAt, meetingLocation}) async {}),
      );

      await tester.tap(find.text('Decided Dana'));
      await tester.pumpAndSettle();
      expect(find.text('Summary for Decided Dana'), findsOneWidget);
      expect(find.text('Looks right'), findsOneWidget);
      expect(find.byKey(const Key('detail-approve')), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pending Pia'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail-approve')), findsOneWidget);
      expect(find.byKey(const Key('detail-reject')), findsOneWidget);
    });

    testWidgets('search narrows the list; no onDecide hides the buttons',
        (tester) async {
      await pumpView(tester, EscalationApprovalsView(reports: reports));
      expect(find.byKey(const ValueKey('approve-p1')), findsNothing);

      await tester.enterText(
          find.descendant(
              of: find.byKey(const Key('escalation-search')),
              matching: find.byType(TextField)),
          'paolo');
      await tester.pumpAndSettle();
      expect(find.text('Pending Paolo'), findsOneWidget);
      expect(find.text('Pending Pia'), findsNothing);
      expect(find.text('Decided Dana'), findsNothing);
    });

    testWidgets('an empty list shows the empty state', (tester) async {
      await pumpView(tester, const EscalationApprovalsView(reports: []));
      expect(find.text('No endorsements yet'), findsOneWidget);
    });
  });

  group('Student Archive', () {
    const maria = ArchiveStudentModel(
        id: 's1', name: 'Maria Santos', studentNumber: '2024-0001', section: 'BSIT 2-1');
    const jose = ArchiveStudentModel(
        id: 's2', name: 'Jose Cruz', studentNumber: '2024-0002');
    final log = ArchiveLogModel(
      id: 'l1',
      type: ArchiveLogType.counseling,
      occurredOn: DateTime(2026, 9, 12),
      title: 'First session',
      notes: 'Discussed attendance.',
      createdByName: 'Ms. Lim',
    );

    testWidgets('lists students on the card; logs load only when opened',
        (tester) async {
      var loads = 0;
      await pumpView(
        tester,
        StudentArchiveView(
          onSearchStudents: (_) async => [maria, jose],
          onLoadLogs: (_) async {
            loads++;
            return [log];
          },
        ),
      );

      expect(find.text('Intervention Logs'), findsOneWidget);
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.text('Jose Cruz'), findsOneWidget);
      expect(loads, 0, reason: 'listing students never reads their notes');

      await tester.tap(find.text('Maria Santos'));
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.text('First session'), findsOneWidget);
      expect(find.text('Discussed attendance.'), findsOneWidget);

      // Closing and re-opening does not read the notes again.
      await tester.tap(find.text('Maria Santos'));
      await tester.pumpAndSettle();
      expect(find.text('First session'), findsNothing);
      await tester.tap(find.text('Maria Santos'));
      await tester.pumpAndSettle();
      expect(loads, 1);
    });

    testWidgets('the card title uses the shared card-title size',
        (tester) async {
      await pumpView(
          tester, StudentArchiveView(onSearchStudents: (_) async => [maria]));
      final title = tester.widget<Text>(find.text('Intervention Logs'));
      expect(title.style!.fontSize, kCardTitleFontSizeDesktop);
      expect(title.style!.fontWeight, FontWeight.w600);
    });

    testWidgets('adding a log saves it and shows the refreshed list',
        (tester) async {
      final logs = <ArchiveLogModel>[];
      ArchiveLogDraft? saved;
      await pumpView(
        tester,
        StudentArchiveView(
          onSearchStudents: (_) async => [maria],
          onLoadLogs: (_) async => List.of(logs),
          onAddLog: (s, draft) async {
            saved = draft;
            logs.add(ArchiveLogModel(
              id: 'new',
              type: draft.type,
              occurredOn: draft.occurredOn,
              title: draft.title,
              notes: draft.notes,
            ));
          },
        ),
      );

      await tester.tap(find.byKey(const ValueKey('archive-add-s1')));
      await tester.pumpAndSettle();
      expect(find.text('Add archival log'), findsWidgets);

      // Save is off until there is a title.
      FilledButton save() => tester.widget<FilledButton>(find.descendant(
          of: find.byKey(const Key('archive-save')),
          matching: find.byType(FilledButton)));
      expect(save().onPressed, isNull);

      // The popup's own Title field (the page's search box sits behind it).
      await tester.enterText(
          find
              .descendant(
                  of: find.byType(AppPopup), matching: find.byType(TextField))
              .first,
          'Parent call');
      await tester.pump();
      await tester.tap(find.byKey(const Key('archive-save')));
      await tester.pumpAndSettle();

      expect(saved?.title, 'Parent call');
      // The row opened itself and lists the new entry.
      expect(find.text('Parent call'), findsOneWidget);
    });

    testWidgets('deleting asks first, then removes the log', (tester) async {
      ArchiveLogModel? deleted;
      await pumpView(
        tester,
        StudentArchiveView(
          onSearchStudents: (_) async => [maria],
          onLoadLogs: (_) async => [log],
          onDeleteLog: (s, l) async => deleted = l,
        ),
      );
      await tester.tap(find.text('Maria Santos'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('archive-delete-l1')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this log?'), findsOneWidget);
      expect(deleted, isNull);

      await tester.tap(find.byKey(const Key('archive-delete-confirm')));
      await tester.pumpAndSettle();
      expect(deleted?.id, 'l1');
    });

    testWidgets('typing searches the roster after a short pause',
        (tester) async {
      final queries = <String>[];
      await pumpView(
        tester,
        StudentArchiveView(onSearchStudents: (q) async {
          queries.add(q);
          return [maria];
        }),
      );
      expect(queries, ['']);

      await tester.enterText(
          find.descendant(
              of: find.byKey(const Key('archive-search')),
              matching: find.byType(TextField)),
          'mar');
      await tester.pump(const Duration(milliseconds: 100));
      expect(queries, ['']);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(queries, ['', 'mar']);
    });

    testWidgets('without a backend it says so', (tester) async {
      await pumpView(tester, const StudentArchiveView());
      expect(find.text('Student archive needs a Supabase connection.'),
          findsOneWidget);
    });

    testWidgets('read-only (no add / delete callbacks) hides those buttons',
        (tester) async {
      await pumpView(
        tester,
        StudentArchiveView(
          onSearchStudents: (_) async => [maria],
          onLoadLogs: (_) async => [log],
        ),
      );
      expect(find.byKey(const ValueKey('archive-add-s1')), findsNothing);
      await tester.tap(find.text('Maria Santos'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('archive-delete-l1')), findsNothing);
    });
  });
}
