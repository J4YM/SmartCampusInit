import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<MeetingFormResult?> _open(
  WidgetTester tester,
  Widget dialog, {
  Future<void> Function()? interact,
}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  MeetingFormResult? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            result = await showAppPopup<MeetingFormResult>(
                context: context, builder: (_) => dialog);
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await interact?.call();
  return result;
}

void main() {
  testWidgets('by default it offers student, parent and both', (tester) async {
    await _open(tester, const ScheduleMeetingDialog());
    await tester.tap(find.byKey(const Key('meeting-invitee')));
    await tester.pumpAndSettle();
    expect(find.text('Student & parent'), findsWidgets);
    expect(find.text('Parent'), findsWidgets);
    expect(find.text('Schedule Meeting'), findsOneWidget);
    expect(find.text('Send invitation'), findsOneWidget);
  });

  testWidgets('with the parent excluded only the student can be invited',
      (tester) async {
    MeetingFormResult? got;
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              got = await showAppPopup<MeetingFormResult>(
                  context: context,
                  builder: (_) => const ScheduleMeetingDialog(allowParent: false));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('meeting-invitee')));
    await tester.pumpAndSettle();
    expect(find.text('Parent'), findsNothing);
    expect(find.text('Student & parent'), findsNothing);
    await tester.tap(find.text('Student').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meeting-save')));
    await tester.pumpAndSettle();
    expect(got!.invitee, 'student');
  });

  testWidgets('a confirmation form starts from the proposal and keeps the '
      'invitee', (tester) async {
    final proposal = DateTime.now().add(const Duration(days: 4));
    MeetingFormResult? got;
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              got = await showAppPopup<MeetingFormResult>(
                context: context,
                builder: (_) => ScheduleMeetingDialog(
                  title: 'Confirm Meeting',
                  confirmLabel: 'Confirm and notify',
                  initialWhen: proposal,
                  initialLocation: 'Guidance Office',
                  initialInvitee: 'parent',
                  showInvitee: false,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Meeting'), findsOneWidget);
    expect(find.text('Confirm and notify'), findsOneWidget);
    expect(find.byKey(const Key('meeting-invitee')), findsNothing,
        reason: 'the DO already chose who is invited');
    expect(find.text('Guidance Office'), findsOneWidget);

    await tester.tap(find.byKey(const Key('meeting-save')));
    await tester.pumpAndSettle();
    expect(got!.invitee, 'parent');
    expect(got!.location, 'Guidance Office');
    expect(got!.scheduledAt.year, proposal.year);
    expect(got!.scheduledAt.day, proposal.day);
    expect(got!.scheduledAt.hour, proposal.hour);
  });
}
