import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every table header in every dashboard is a [DashboardTableHeader] (or the
/// Professor matrix, which reads the same token), so the header's fill is one
/// decision: the dashboard's MAIN background — not the card's — so the band
/// reads as the page behind the card, above the card-colored rows.
void main() {
  for (final brightness in Brightness.values) {
    testWidgets('table header uses the main background in ${brightness.name} '
        'mode', (tester) async {
      late BuildContext inner;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              inner = context;
              return const DashboardTableHeader(
                columns: [
                  DashboardTableColumn('Name'),
                  DashboardTableColumn('Status'),
                ],
              );
            },
          ),
        ),
      ));

      final page = DashboardTableColors.pageBackground(inner);
      expect(page, brightness == Brightness.dark
          ? const Color(0xFF0E0E0E)
          : const Color(0xFFF0F5F8));
      expect(DashboardTableColors.headerBackground(inner), page);
      expect(page, isNot(DashboardTableColors.card(inner)));

      final header = tester.widget<Container>(find
          .descendant(
            of: find.byType(DashboardTableHeader),
            matching: find.byType(Container),
          )
          .first);
      expect((header.decoration! as BoxDecoration).color, page);
    });
  }
}
