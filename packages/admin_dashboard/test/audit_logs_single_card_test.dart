import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Audit & Privacy Logs is one card: the search, the severity / role filters,
/// the date range and the record count sit at the top of the same card as the
/// table, not in a card of their own above it.
void main() {
  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AuditLogsPage.empty())),
    );
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(1500, 1000), Size(390, 900)]) {
    testWidgets('one card holds the filters and the table at '
        '${size.width.toInt()}px', (tester) async {
      await pump(tester, size);

      // A single card on the page...
      expect(find.byType(BentoCard), findsOneWidget);
      final card = find.byType(BentoCard);

      // ...and the search, filters, record count and table header are in it.
      for (final inside in [
        find.text('Search action, user, or record ID...'),
        find.text('All Severities'),
        find.text('All Roles'),
        find.text('0 records'),
        find.byType(DashboardTableHeader),
      ]) {
        expect(
          find.descendant(of: card, matching: inside),
          findsWidgets,
          reason: 'expected inside the one card',
        );
      }

      // The filters are above the table header.
      final search = tester.getRect(find.byType(TextField).first);
      final header = tester.getRect(find.byType(DashboardTableHeader));
      expect(search.bottom, lessThan(header.top));
      expect(tester.takeException(), isNull);
    });
  }
}
