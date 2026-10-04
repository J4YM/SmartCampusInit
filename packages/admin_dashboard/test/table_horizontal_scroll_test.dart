import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every Admin table scrolls sideways once its card is too narrow for its
/// columns (instead of crumpling its text), and does nothing special when it
/// fits.
void main() {
  Map<DashboardTableHeader, bool> headers(WidgetTester tester) => {
        for (final e in find.byType(DashboardTableHeader).evaluate())
          e.widget as DashboardTableHeader: find
              .ancestor(
                  of: find.byWidget(e.widget),
                  matching: find.byWidgetPredicate((w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.right))
              .evaluate()
              .isNotEmpty,
      };

  final pages = <String, Widget Function()>{
    'Student Directory': () => StudentDirectoryPage.empty(),
    'Staff Accounts': () => StaffAccountsPage.empty(),
    'RFID Mapping': () => RfidMappingPage.empty(),
    'Audit Logs': () => AuditLogsPage.empty(),
  };

  for (final entry in pages.entries) {
    testWidgets('${entry.key}: sideways scroll on a phone, none on a wide '
        'screen', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<void> show(Size size, Object key) async {
        tester.view.physicalSize = size;
        await tester.pumpWidget(MaterialApp(
          key: ValueKey(key),
          home: Scaffold(body: entry.value()),
        ));
        await tester.pumpAndSettle();
        tester.takeException();
      }

      await show(const Size(1600, 1000), 'wide');
      final wide = headers(tester);
      expect(wide, isNotEmpty, reason: '${entry.key} has a table header');
      expect(wide.values, everyElement(isFalse));

      await show(const Size(390, 900), 'phone');
      final phone = headers(tester);
      expect(phone.values, everyElement(isTrue),
          reason: '${entry.key}: not scrolling on a phone');
      for (final header in phone.keys) {
        expect(tester.getSize(find.byWidget(header)).width,
            greaterThanOrEqualTo(dashboardTableMinWidth(header.columns)),
            reason: 'crumpled: ${header.columns.map((c) => c.label)}');
      }
    });
  }
}
