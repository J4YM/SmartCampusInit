import 'package:capstone_dashboard/data/academic_term_repository.dart';
import 'package:capstone_dashboard/ui/admin/academic_term_connected_page.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Academic Term page on the shared Admin page frame and the app-wide
/// cards: no raw Material cards, no theme-default fields. (Without a Supabase
/// connection it renders its empty state, which is all a widget test has.)
void main() {
  _datesTests();
  Future<void> pump(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AcademicTermConnectedPage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('desktop: page title and the three cards', (tester) async {
    await pump(tester, width: 1500);

    expect(find.text('Academic Term'), findsOneWidget);
    expect(find.text('Current Term'), findsOneWidget);
    expect(find.text('Migrate to a New Term'), findsOneWidget);
    expect(find.text('Archived Terms'), findsOneWidget);
    expect(find.text('No closed terms yet'), findsOneWidget);
    expect(find.text('No term started yet'), findsOneWidget);
    expect(find.byKey(const Key('term-school-year')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Card titles share the app-wide size.
    for (final t in ['Current Term', 'Migrate to a New Term', 'Archived Terms']) {
      final style = tester.widget<Text>(find.text(t)).style!;
      expect(style.fontSize, kCardTitleFontSizeDesktop, reason: t);
    }
  });

  testWidgets('desktop: the Current Term card sits beside the Migrate card',
      (tester) async {
    await pump(tester, width: 1500);

    final current = tester.getTopLeft(find.text('Current Term'));
    final migrate = tester.getTopLeft(find.text('Migrate to a New Term'));
    expect(migrate.dx, greaterThan(current.dx));
    expect((migrate.dy - current.dy).abs(), lessThan(8));
  });

  testWidgets('phone: the cards stack and nothing overflows', (tester) async {
    await pump(tester, width: 380);

    final current = tester.getTopLeft(find.text('Current Term')).dy;
    final migrate = tester.getTopLeft(find.text('Migrate to a New Term')).dy;
    expect(migrate, greaterThan(current));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Start New Term is off without a connection', (tester) async {
    await pump(tester, width: 1500);

    final button = tester.widget<FilledButton>(find.byKey(const Key('start-new-term')));
    expect(button.onPressed, isNull);
  });
}

/// The school-calendar dates of the current term show on its card.
void _datesTests() {
  Future<void> pumpWith(WidgetTester tester, List<AcademicTerm> terms) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AcademicTermConnectedPage(debugTerms: terms)),
    ));
    await tester.pumpAndSettle();
  }

  AcademicTerm term({DateTime? startsOn, DateTime? endsOn}) => AcademicTerm(
        id: 't1',
        schoolYear: '2026-2027',
        term: '1st Semester',
        isCurrent: true,
        startedAt: DateTime(2026, 8, 1),
        startsOn: startsOn,
        endsOn: endsOn,
      );

  testWidgets('the current term shows when the academic year starts and ends',
      (tester) async {
    await pumpWith(tester,
        [term(startsOn: DateTime(2026, 8, 4), endsOn: DateTime(2027, 5, 30))]);
    expect(find.text('Aug 4, 2026 – May 30, 2027'), findsOneWidget);
  });

  testWidgets('a term with no dates says so', (tester) async {
    await pumpWith(tester, [term()]);
    expect(find.text('Dates not set'), findsOneWidget);
  });
}
