import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Student Directory and Staff Accounts are one card each: the search, the
/// filters and the Add button sit at the top of the same card as the table,
/// not in a bar of their own above it.
void main() {
  final pages = <String, ({Widget Function() page, List<String> inside})>{
    'Student Directory': (
      page: () => StudentDirectoryPage.empty(),
      inside: ['All Courses', 'All Years'],
    ),
    'Staff Accounts': (
      page: () => StaffAccountsPage.empty(),
      inside: ['All Roles', 'Add Staff Account'],
    ),
  };

  for (final entry in pages.entries) {
    for (final size in const [Size(1500, 1000), Size(390, 900)]) {
      testWidgets('${entry.key}: one card holds the toolbar and the table at '
          '${size.width.toInt()}px', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: entry.value.page())),
        );
        await tester.pumpAndSettle();
        tester.takeException();

        expect(find.byType(BentoCard), findsOneWidget);
        final card = find.byType(BentoCard);

        for (final label in entry.value.inside) {
          expect(find.descendant(of: card, matching: find.text(label)),
              findsWidgets,
              reason: '"$label" should be inside the one card');
        }
        expect(
          find.descendant(of: card, matching: find.byType(TextField)),
          findsOneWidget,
          reason: 'the search field is inside the card',
        );
        expect(find.descendant(
                of: card, matching: find.byType(DashboardTableHeader)),
            findsOneWidget);

        // The search sits above the table header.
        final search = tester.getRect(find.byType(TextField).first);
        final header = tester.getRect(find.byType(DashboardTableHeader));
        expect(search.bottom, lessThan(header.top));
      });
    }
  }
}
