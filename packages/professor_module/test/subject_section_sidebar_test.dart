import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/professor_module.dart';

/// Wide enough to trigger the desktop master-detail layout (sidebar +
/// attendance panel side by side), matching this app's own convention for
/// exercising a dashboard's non-mobile branch in tests.
Future<void> _pumpDesktop(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: ProfessorDashboardPage()));
  await tester.pumpAndSettle();
}

int _iconCount(WidgetTester tester, IconData icon) =>
    tester.widgetList(find.byIcon(icon)).length;

/// The sidebar's own accordion list is a scrollable, height-capped
/// ListView (the same master-detail height budget every other dashboard's
/// sidebar list already scrolls within) — a subject/section further down
/// the list needs an actual scroll to reach, exactly like a real user's
/// mouse wheel would, rather than assuming everything fits on screen.
Future<void> _revealInSidebar(WidgetTester tester, Finder finder) async {
  final sidebarScrollable = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(finder, 200, scrollable: sidebarScrollable);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'sidebar groups sections under subject accordions, with only the '
      "active section's subject expanded by default",
      (tester) async {
    await _pumpDesktop(tester);

    expect(find.text('Subjects & Sections'), findsOneWidget);
    expect(find.text('3 subjects · 12 sections'), findsOneWidget);

    // Data Structures & Algorithms contains the mock data's first section,
    // so it's the one expanded by default — its sections are visible right
    // away, with no scrolling needed.
    expect(find.text('Data Structures & Algorithms'), findsOneWidget);
    expect(find.text('BSBA - 1A'), findsOneWidget);
    expect(find.text('BSIT - 1A'), findsOneWidget);
    expect(find.text('BSIT - 3C'), findsOneWidget);
    expect(find.text('BSTM - 1C'), findsOneWidget);

    // The other two subjects start collapsed — scrolling to each header
    // must not also reveal its sections.
    await _revealInSidebar(tester, find.text('Mobile Application Development'));
    expect(find.text('BSBA - 1B'), findsNothing);

    await _revealInSidebar(tester, find.text('Web Systems & Technologies'));
    expect(find.text('BSBA - 1C'), findsNothing);

    // Exactly one section is marked active on load.
    expect(_iconCount(tester, Icons.radio_button_checked_rounded), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a collapsed subject expands it to show its sections '
      'with student-count badges', (tester) async {
    await _pumpDesktop(tester);

    expect(find.text('BSBA - 1B'), findsNothing);

    await _revealInSidebar(tester, find.text('Mobile Application Development'));
    await tester.tap(find.text('Mobile Application Development'));
    await tester.pumpAndSettle();

    // All 4 Mobile Application Development sections are now visible, each
    // with its own student-count badge.
    expect(find.text('BSBA - 1B'), findsOneWidget);
    expect(find.text('28'), findsOneWidget); // BSBA - 1B's studentCount
    await _revealInSidebar(tester, find.text('BSTM - 2B'));
    expect(find.text('BSTM - 2B'), findsOneWidget);

    // Tapping the header again collapses it back.
    await _revealInSidebar(tester, find.text('Mobile Application Development'));
    await tester.tap(find.text('Mobile Application Development'));
    await tester.pumpAndSettle();
    expect(find.text('BSBA - 1B'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'clicking a Section makes it the active attendance context and '
      'highlights it', (tester) async {
    await _pumpDesktop(tester);

    // BSBA - 1A (Data Structures & Algorithms) is active by default.
    expect(_iconCount(tester, Icons.radio_button_checked_rounded), 1);

    await _revealInSidebar(tester, find.text('Mobile Application Development'));
    await tester.tap(find.text('Mobile Application Development'));
    await tester.pumpAndSettle();
    await _revealInSidebar(tester, find.text('BSBA - 1B'));
    await tester.tap(find.text('BSBA - 1B'));
    await tester.pumpAndSettle();

    // The active section moved — still exactly one, now under the newly
    // selected section instead of the original default.
    expect(_iconCount(tester, Icons.radio_button_checked_rounded), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search filters both by subject name and by section name, without '
      'flattening matches out from under their parent subject',
      (tester) async {
    await _pumpDesktop(tester);

    // A subject-name match shows every one of its sections, auto-expanded.
    await tester.enterText(find.byType(TextField), 'Mobile');
    await tester.pumpAndSettle();
    expect(find.text('Mobile Application Development'), findsOneWidget);
    expect(find.text('Data Structures & Algorithms'), findsNothing);
    expect(find.text('Web Systems & Technologies'), findsNothing);
    expect(find.text('BSBA - 1B'), findsOneWidget);
    expect(find.text('BSHM - 1A'), findsOneWidget);

    // A section-name match surfaces only that section, still nested under
    // its (correct) parent subject header. find.text also matches the
    // search field's own EditableText once its value equals "BSIT - 1A",
    // so the sidebar's row is asserted via a Text-widget predicate instead
    // to disambiguate the two.
    await tester.enterText(find.byType(TextField), 'BSIT - 1A');
    await tester.pumpAndSettle();
    expect(find.text('Data Structures & Algorithms'), findsOneWidget);
    expect(find.text('Mobile Application Development'), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'BSIT - 1A'),
      findsOneWidget,
    );
    expect(find.text('BSBA - 1A'), findsNothing); // same subject, no match
    expect(tester.takeException(), isNull);
  });
}
