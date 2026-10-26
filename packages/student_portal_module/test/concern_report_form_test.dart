import 'package:dashboard_layout/dashboard_layout.dart'
    show AppPopupDropdown, AppPopupTextField;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/student_portal_module.dart';

Future<void> _pump(
  WidgetTester tester, {
  void Function({
    required ConcernType concern,
    required String details,
    required bool urgent,
  })? onSubmitConcernReport,
  List<ConcernReportStatus>? initialConcernReports,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: StudentPortalHomePage(
      onSubmitConcernReport: onSubmitConcernReport,
      initialConcernReports: initialConcernReports,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openForm(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Report a Concern'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Report a Concern'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the Concern Report card sits beside the Referral card',
      (tester) async {
    await _pump(tester);
    await tester.ensureVisible(find.text('Concern Report'));
    expect(find.text('Concern Report'), findsOneWidget);
    expect(find.text('Referral'), findsOneWidget);
  });

  testWidgets('the concern form needs details and lists the six concern types',
      (tester) async {
    ConcernType? sentConcern;
    String? sentDetails;
    var sentUrgent = true;
    await _pump(tester, onSubmitConcernReport: ({
      required concern,
      required details,
      required urgent,
    }) {
      sentConcern = concern;
      sentDetails = details;
      sentUrgent = urgent;
    });
    await _openForm(tester);

    expect(find.byType(AppPopupDropdown<ConcernType>), findsOneWidget);
    expect(find.byType(AppPopupDropdown<bool>), findsNothing);
    expect(ConcernType.values.map((c) => c.label), [
      'Attendance',
      'Behavior',
      'Bullying',
      'Safety',
      'Academic difficulties',
      'Something else',
    ]);

    await tester.tap(find.byKey(const Key('concern-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Please write at least a sentence'), findsOneWidget);
    expect(sentConcern, isNull);

    await tester.enterText(
        find.byType(AppPopupTextField), 'Someone keeps skipping our class.');
    await tester.pump();
    await tester.tap(find.byKey(const Key('concern-submit')));
    await tester.pumpAndSettle();

    expect(sentConcern, ConcernType.attendance);
    expect(sentDetails, 'Someone keeps skipping our class.');
    expect(sentUrgent, isFalse);
    expect(find.byType(AppPopupTextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the student sees their concern reports and the reply',
      (tester) async {
    await _pump(tester, initialConcernReports: [
      ConcernReportStatus(
        id: 'c1',
        concern: ConcernType.bullying,
        urgency: 'Urgent',
        status: 'In_Progress',
        createdAt: DateTime(2026, 10, 2),
        handlerNote: 'We are looking into it.',
      ),
    ]);
    await tester.ensureVisible(find.text('Bullying'));
    expect(find.text('Bullying'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Student Affairs: We are looking into it.'), findsOneWidget);
  });
}
