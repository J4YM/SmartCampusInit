import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/pages/dashboard/registrar_dashboard_page.dart';

void main() {
  testWidgets('the overview shows Newly Enrolled Students, not Average GPA',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: RegistrarDashboardPage(
        initialOverviewStats: OverviewStatsModel(
          totalStudents: 120,
          newlyEnrolled: 37,
          rfidPending: 5,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();

    expect(find.text('Newly Enrolled Students'), findsOneWidget);
    expect(find.text('37'), findsOneWidget);
    expect(find.text('Average GPA'), findsNothing);
    // The other two cards are untouched.
    expect(find.text('Total Students'), findsOneWidget);
    expect(find.text('RFID Pending'), findsOneWidget);
  });

  test('the stats model carries the newly-enrolled count through JSON', () {
    const stats = OverviewStatsModel(totalStudents: 9, newlyEnrolled: 4);
    expect(stats.toJson()['newly_enrolled'], 4);
    expect(OverviewStatsModel.fromJson(stats.toJson()).newlyEnrolled, 4);
    // Nothing recorded yet reads as zero, not a blank.
    expect(OverviewStatsModel.fromJson(const {}).newlyEnrolled, 0);
  });
}
