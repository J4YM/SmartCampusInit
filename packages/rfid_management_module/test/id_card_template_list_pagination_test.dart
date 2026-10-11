import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// The ID Templates tab pages its list with the app-wide card footer: 10 a
/// page on a wide screen, 5 on a phone.
void main() {
  List<IdCardTemplateSummaryRow> templates(int n) => [
        for (var i = 1; i <= n; i++)
          IdCardTemplateSummaryRow(
            id: 't$i',
            name: 'Template $i',
            updatedAtLabel: '10/$i/2026',
          ),
      ];

  Future<void> show(
    WidgetTester tester,
    List<IdCardTemplateSummaryRow> items, {
    Size size = const Size(1400, 1400),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: IdCardTemplateListView(
            templates: items,
            isLoading: false,
            onCreate: () {},
            onOpen: (_) {},
            onRename: (_, __) {},
            onDelete: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows ten a page on a wide screen and pages through', (tester) async {
    await show(tester, templates(23));

    expect(find.text('Page 1 of 3 · 23 total'), findsOneWidget);
    expect(find.text('Template 1'), findsOneWidget);
    expect(find.text('Template 10'), findsOneWidget);
    expect(find.text('Template 11'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3 · 23 total'), findsOneWidget);
    expect(find.text('Template 11'), findsOneWidget);
    expect(find.text('Template 1'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 3 of 3 · 23 total'), findsOneWidget);
    expect(find.text('Template 23'), findsOneWidget);
    expect(find.text('Template 21'), findsOneWidget);
    expect(find.text('Template 20'), findsNothing);

    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3 · 23 total'), findsOneWidget);
  });

  testWidgets('shows five a page on a phone', (tester) async {
    await show(tester, templates(12), size: const Size(390, 1600));
    expect(find.text('Page 1 of 3 · 12 total'), findsOneWidget);
    expect(find.text('Template 5'), findsOneWidget);
    expect(find.text('Template 6'), findsNothing);
  });

  testWidgets('a short list is a single page', (tester) async {
    await show(tester, templates(3));
    expect(find.text('Page 1 of 1 · 3 total'), findsOneWidget);
    expect(find.text('Template 3'), findsOneWidget);
  });

  testWidgets('the page steps back when the list shrinks under it',
      (tester) async {
    Widget host(List<IdCardTemplateSummaryRow> items) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: IdCardTemplateListView(
                templates: items,
                isLoading: false,
                onCreate: () {},
                onOpen: (_) {},
                onRename: (_, __) {},
                onDelete: (_) {},
              ),
            ),
          ),
        );
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(templates(11)));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2 · 11 total'), findsOneWidget);

    // The only template on page 2 is deleted.
    await tester.pumpWidget(host(templates(10)));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 1 · 10 total'), findsOneWidget);
    expect(find.text('Template 10'), findsOneWidget);
  });

  testWidgets('no footer while loading or when empty', (tester) async {
    await show(tester, const []);
    expect(find.textContaining('Page '), findsNothing);
    expect(find.textContaining('No templates yet'), findsOneWidget);
  });
}
