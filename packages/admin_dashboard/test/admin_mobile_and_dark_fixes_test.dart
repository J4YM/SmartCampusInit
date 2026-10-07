import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Audit & Privacy Logs keeps a usable table height on a phone',
      (tester) async {
    // Regression test: on a phone the filters wrap into a tall block, and the
    // table (an Expanded child of a fixed-height column) was left with a few
    // pixels. The page now scrolls instead, giving the table a minimum height.
    setSize(tester, const Size(390, 700));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AuditLogsPage.empty()),
    ));
    await tester.pumpAndSettle();
    tester.takeException();

    final card = find.ancestor(
        of: find.byType(DashboardTableHeader), matching: find.byType(BentoCard));
    expect(card, findsWidgets);
    expect(tester.getSize(card.first).height, greaterThanOrEqualTo(400),
        reason: 'the table card was squeezed');

    // The rest of the page is reachable by scrolling.
    expect(
        find.descendant(
            of: find.byType(AuditLogsPage),
            matching: find.byType(SingleChildScrollView)),
        findsWidgets);
  });

  testWidgets('Audit & Privacy Logs still fills the screen on desktop',
      (tester) async {
    setSize(tester, const Size(1400, 900));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AuditLogsPage.empty()),
    ));
    await tester.pumpAndSettle();
    tester.takeException();

    final card = find.ancestor(
        of: find.byType(DashboardTableHeader), matching: find.byType(BentoCard));
    // Title + filters take the top; the table card takes everything left.
    expect(tester.getSize(card.first).height, greaterThan(450));
    expect(tester.getRect(card.first).bottom, greaterThan(800));
  });

  group('Early Warning Triggers cards follow the theme', () {
    const student = AtRiskStudentModel(
      avatarInitials: 'JD',
      name: 'Juan Dela Cruz',
      courseYear: 'BSIT · 2nd Year',
      riskPercentage: 82,
      riskColor: Color(0xFFDC2626),
      riskTags: ['High absences'],
      lastSeen: 'Today',
      assignedCounselor: 'Ms. Reyes',
      avatarColor: Color(0xFF345892),
    );

    Future<Set<Color?>> cardColors(WidgetTester tester, Brightness b) async {
      setSize(tester, const Size(1400, 1600));
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        theme: ThemeData(brightness: b),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SystemOverviewPage(
              stats: defaultOverviewStats,
              hotzones: defaultViolationHotzones,
              rfidLogs: defaultRfidLogs,
              atRiskStudents: const [student],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      tester.takeException();
      final inner = find.ancestor(
          of: find.text('Juan Dela Cruz'), matching: find.byType(BentoCard));
      return {
        for (final e in inner.evaluate()) (e.widget as BentoCard).backgroundColor,
      };
    }

    testWidgets('light: pale inset card', (tester) async {
      expect(await cardColors(tester, Brightness.light),
          contains(const Color(0xFFF8FAFC)));
    });

    testWidgets('dark: no light card left behind', (tester) async {
      final colors = await cardColors(tester, Brightness.dark);
      expect(colors, isNot(contains(const Color(0xFFF8FAFC))));
      expect(colors, contains(const Color(0xFF22242B)));
    });
  });
}
