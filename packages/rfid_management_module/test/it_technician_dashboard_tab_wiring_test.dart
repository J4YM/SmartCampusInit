import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

void main() {
  Widget buildPage() {
    return MaterialApp(
      home: ItTechnicianDashboardPage(
        studentRecordsTabBuilder: (_) => const Center(child: Text('Student Records Content')),
        readerDevicesTabBuilder: (_) => const Center(child: Text('Reader Devices Content')),
        technicalIssuesTabBuilder: (_) => const Center(child: Text('Technical Issues Content')),
      ),
    );
  }

  testWidgets('starts on Overview and switches tabs on tap', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPage());

    expect(find.text('Total Students'), findsOneWidget);
    expect(find.text('Student Records Content'), findsNothing);

    await tester.tap(find.text('Student Records'));
    await tester.pumpAndSettle();
    expect(find.text('Student Records Content'), findsOneWidget);
    expect(find.text('Total Students'), findsNothing);

    await tester.tap(find.text('Reader Devices'));
    await tester.pumpAndSettle();
    expect(find.text('Reader Devices Content'), findsOneWidget);

    await tester.tap(find.text('Technical Issues'));
    await tester.pumpAndSettle();
    expect(find.text('Technical Issues Content'), findsOneWidget);
  });

  testWidgets('switches to bottom nav below the mobile breakpoint', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPage());

    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
  });
}
