import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/pages/dashboard/registrar_dashboard_page.dart';

void main() {
  Future<Finder> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      home: const RegistrarDashboardPage(),
    ));
    await tester.pumpAndSettle();
    tester.takeException();
    return find
        .ancestor(
            of: find.text('New Students'), matching: find.byType(BentoCard))
        .first;
  }

  testWidgets('wide: the search bar is on the title row, left of View All',
      (tester) async {
    final card = await pumpAt(tester, const Size(1400, 1000));
    final search = tester.getRect(
        find.descendant(of: card, matching: find.byType(SearchField)));
    final title = tester.getRect(find.text('New Students'));
    final viewAll = tester.getRect(find.byKey(const Key('view-all-students')));

    // Left of the link, right of the title...
    expect(search.right, lessThan(viewAll.left));
    expect(search.left, greaterThan(title.right));
    // ...and on the same row: vertically centered with both.
    expect(search.center.dy, closeTo(title.center.dy, 2));
    expect(search.center.dy, closeTo(viewAll.center.dy, 2));
    // The link is the app's standard secondary pill button, not a text link.
    expect(tester.widget(find.byKey(const Key('view-all-students'))),
        isA<SecondaryPillButton>());
    // The title is on the card's left corner; the search and the link are
    // pushed to its right corner (card padding 20, the link ends at the edge).
    final cardRect = tester.getRect(card);
    expect(title.left, closeTo(cardRect.left + 20, 1));
    expect(viewAll.right, closeTo(cardRect.right - 20, 1));
    // The search hugs the link (a 16px gap), not the title.
    expect(viewAll.left - search.right, closeTo(16, 1));
    // It keeps its normal size (never wider than the page's search max).
    expect(search.width, lessThanOrEqualTo(kRegistrarSearchMaxWidth));
    expect(search.height, kDashboardControlHeight);
  });

  testWidgets('narrow: the search drops under the title row', (tester) async {
    final card = await pumpAt(tester, const Size(390, 1000));
    final search = tester.getRect(
        find.descendant(of: card, matching: find.byType(SearchField)));
    final title = tester.getRect(find.text('New Students'));
    final viewAll = tester.getRect(find.byKey(const Key('view-all-students')));

    expect(search.top, greaterThan(title.bottom));
    expect(search.top, greaterThan(viewAll.bottom));
    expect(tester.takeException(), isNull);
  });
  group('Student Need RFID: View All', () {
    testWidgets('is a full-width secondary button between the title and the '
        'search bar', (tester) async {
      await pumpAt(tester, const Size(1400, 1000));
      final card = tester.getRect(find
          .ancestor(
              of: find.text('Student Need RFID'),
              matching: find.byType(BentoCard))
          .first);
      final button = find.byKey(const Key('view-all-rfid'));
      expect(tester.widget(button), isA<SecondaryPillButton>());

      final title = tester.getRect(find.text('Student Need RFID'));
      final summary = tester.getRect(find.textContaining('Total students:'));
      final rect = tester.getRect(button);
      final search = tester.getRect(find.descendant(
          of: find.ancestor(
              of: find.text('Student Need RFID'),
              matching: find.byType(BentoCard)).first,
          matching: find.byType(SearchField)));

      // Under the title and its summary, above the search bar.
      expect(rect.top, greaterThan(title.bottom));
      expect(rect.top, greaterThanOrEqualTo(summary.bottom));
      expect(rect.bottom, lessThanOrEqualTo(search.top));
      // The whole width of the card, inside its 29px content inset.
      expect(rect.left, closeTo(card.left + 29, 1));
      expect(rect.right, closeTo(card.right - 29, 1));
      // The old text link left the title row: nothing shares the title's line.
      expect(find.text('View All'), findsOneWidget);
      expect(rect.center.dy, greaterThan(title.center.dy));
    });

    testWidgets('is full width on a phone too, and nothing overflows',
        (tester) async {
      await pumpAt(tester, const Size(390, 2000));
      final card = tester.getRect(find
          .ancestor(
              of: find.text('Student Need RFID'),
              matching: find.byType(BentoCard))
          .first);
      final rect = tester.getRect(find.byKey(const Key('view-all-rfid')));
      expect(rect.width, closeTo(card.width - 58, 3)); // minus the card's own border
      expect(tester.takeException(), isNull);
    });

    testWidgets('both View All buttons still open their tab', (tester) async {
      await pumpAt(tester, const Size(1400, 1400));
      await tester.tap(find.byKey(const Key('view-all-rfid')));
      await tester.pumpAndSettle();
      tester.takeException();
      // Left the overview: its cards are gone.
      expect(find.byKey(const Key('view-all-rfid')), findsNothing);

      await pumpAt(tester, const Size(1400, 1400));
      await tester.tap(find.byKey(const Key('view-all-students')));
      await tester.pumpAndSettle();
      tester.takeException();
      expect(find.byKey(const Key('view-all-students')), findsNothing);
    });
  });
  group('View All icons', () {
    Future<void> expectIconAfterLabel(
        WidgetTester tester, String key, String label) async {
      final button = find.byKey(Key(key));
      final text = tester.getRect(
          find.descendant(of: button, matching: find.text(label)));
      final icon = tester.getRect(find.descendant(
          of: button, matching: find.byIcon(Icons.arrow_forward_rounded)));
      expect(icon.left, greaterThanOrEqualTo(text.right),
          reason: '$label: the arrow sits to the right of the label');
      expect(icon.center.dy, closeTo(text.center.dy, 3));
    }

    testWidgets('the arrow is on the right of both View All buttons',
        (tester) async {
      await pumpAt(tester, const Size(1400, 1000));
      await expectIconAfterLabel(tester, 'view-all-students', 'View All Students');
      await expectIconAfterLabel(tester, 'view-all-rfid', 'View All');
    });

    testWidgets('and on a phone', (tester) async {
      await pumpAt(tester, const Size(390, 2000));
      await expectIconAfterLabel(tester, 'view-all-students', 'View All Students');
      await expectIconAfterLabel(tester, 'view-all-rfid', 'View All');
      expect(tester.takeException(), isNull);
    });

    testWidgets('other secondary pills keep their icon in front of the label',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SecondaryPillButton(
              key: const Key('plain'),
              icon: Icons.refresh_rounded,
              label: 'Refresh',
              onTap: () {},
            ),
          ),
        ),
      ));
      final text = tester.getRect(find.text('Refresh'));
      final icon = tester.getRect(find.byIcon(Icons.refresh_rounded));
      expect(icon.right, lessThanOrEqualTo(text.left));
    });
  });
}
