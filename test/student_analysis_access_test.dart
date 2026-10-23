import 'package:capstone_dashboard/ui/guidance_counselor_connected_page.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _size(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('the analysis workspace Student Affairs opens', () {
    Future<void> pump(WidgetTester tester) async {
      _size(tester, const Size(1600, 1000));
      await tester.pumpWidget(const MaterialApp(
        home: GuidanceCounselorConnectedPage(analysisOnly: true),
      ));
      await tester.pumpAndSettle();
      tester.takeException();
    }

    testWidgets('has the three analysis tabs and nothing else', (tester) async {
      await pump(tester);

      expect(find.text('ML Overview'), findsOneWidget);
      expect(find.text('Single Student Analysis'), findsOneWidget);
      expect(find.text('Batch Student Analysis'), findsOneWidget);
      expect(find.text('Endorsement Approvals'), findsNothing);
      expect(find.text('Intervention Logs'), findsNothing);
      expect(find.text('Overview'), findsNothing,
          reason: 'the system overview stays with Guidance and Admin');
    });

    testWidgets('is titled for what it is and lands on the ML Overview',
        (tester) async {
      await pump(tester);
      expect(find.text('Student Analysis'), findsOneWidget);
      expect(find.text('Guidance Associate Dashboard'), findsNothing);
    });

    testWidgets('the other analysis tabs open', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Single Student Analysis'));
      await tester.pumpAndSettle();
      tester.takeException();
      expect(find.text('Single Student Analysis'), findsWidgets);
    });
  });

  group('the Guidance dashboard itself', () {
    testWidgets('keeps its own tabs and title and no longer has the system '
        'overview', (tester) async {
      _size(tester, const Size(1800, 1000));
      await tester.pumpWidget(
          const MaterialApp(home: GuidanceCounselorConnectedPage()));
      await tester.pumpAndSettle();
      tester.takeException();

      expect(find.text('Guidance Associate Dashboard'), findsOneWidget);
      expect(find.text('ML Overview'), findsOneWidget);
      expect(find.text('Endorsement Approvals'), findsOneWidget);
      expect(find.text('Intervention Logs'), findsOneWidget);
      expect(find.text('Overview'), findsNothing,
          reason: 'its discipline cards read violations Guidance no longer sees');
    });
  });

  group('the Discipline Officer dashboard', () {
    testWidgets('has an Analysis entry that opens the workspace',
        (tester) async {
      _size(tester, const Size(1800, 1000));
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        home: DisciplineOfficerDashboardPage(onOpenAnalysis: () => opened++),
      ));
      await tester.pumpAndSettle();
      tester.takeException();

      await tester.ensureVisible(find.text('Analysis'));
      await tester.tap(find.text('Analysis'));
      await tester.pumpAndSettle();
      tester.takeException();

      expect(opened, 1);
    });

    testWidgets('without a host callback there is no Analysis entry',
        (tester) async {
      _size(tester, const Size(1800, 1000));
      await tester.pumpWidget(
          const MaterialApp(home: DisciplineOfficerDashboardPage()));
      await tester.pumpAndSettle();
      tester.takeException();
      expect(find.text('Analysis'), findsNothing);
    });
  });
}
