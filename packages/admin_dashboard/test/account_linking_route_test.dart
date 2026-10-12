import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Account Linking" is a tab under User Management (beside Staff Accounts),
/// where the Professor Accounts feature now lives instead of at the bottom of
/// the Staff Accounts page.
void main() {
  Future<void> pump(WidgetTester tester, {WidgetBuilder? accountLinking}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: AdminDashboardPage(accountLinkingPageBuilder: accountLinking),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openAccountLinking(WidgetTester tester) async {
    if (find.text('Account Linking').evaluate().isEmpty) {
      await tester.tap(find.text('User Management'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Account Linking'));
    await tester.pumpAndSettle();
  }

  testWidgets('it sits in the User Management group, after Staff Accounts',
      (tester) async {
    await pump(tester);
    if (find.text('Account Linking').evaluate().isEmpty) {
      await tester.tap(find.text('User Management'));
      await tester.pumpAndSettle();
    }

    final staff = tester.getTopLeft(find.text('Staff Accounts')).dy;
    final linking = tester.getTopLeft(find.text('Account Linking')).dy;
    final rfid = tester.getTopLeft(find.text('RFID Mapping')).dy;
    expect(linking, greaterThan(staff));
    expect(linking, lessThan(rfid));
  });

  testWidgets('opening it shows the supplied panel under the page title',
      (tester) async {
    await pump(tester, accountLinking: (_) => const Text('PROFESSOR PANEL'));

    await openAccountLinking(tester);

    expect(find.text('PROFESSOR PANEL'), findsOneWidget);
    // Sidebar entry + the page's own heading.
    expect(find.text('Account Linking'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a builder the page says it needs a connection',
      (tester) async {
    await pump(tester);

    await openAccountLinking(tester);

    expect(find.text('Account linking needs a Supabase connection.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the page scrolls as a whole, title included, like the other '
      'tabs (no inner scroll region under a pinned heading)', (tester) async {
    await pump(
      tester,
      accountLinking: (_) => const SizedBox(height: 3000, child: Text('TALL')),
    );
    await openAccountLinking(tester);

    final heading = find.byWidgetPredicate(
      (w) => w is Text && w.data == 'Account Linking' && w.style?.fontSize == 28,
    );
    expect(heading, findsOneWidget);
    final before = tester.getTopLeft(heading).dy;

    final pageScroll = find
        .ancestor(of: heading, matching: find.byType(SingleChildScrollView))
        .first;
    await tester.drag(pageScroll, const Offset(0, -300));
    await tester.pumpAndSettle();

    // The heading moved up with the content — it is not pinned.
    expect(tester.getTopLeft(heading).dy, lessThan(before - 200));
    // And the content's own scroll view is the same one: the heading and the
    // body share a single vertical scrollable.
    expect(
      find.descendant(of: pageScroll, matching: find.text('TALL')),
      findsOneWidget,
    );
  });

  testWidgets('the Staff Accounts page no longer carries the professor panel',
      (tester) async {
    await pump(tester, accountLinking: (_) => const Text('PROFESSOR PANEL'));

    if (find.text('Staff Accounts').evaluate().isEmpty) {
      await tester.tap(find.text('User Management'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Staff Accounts'));
    await tester.pumpAndSettle();

    expect(find.text('PROFESSOR PANEL'), findsNothing);
    expect(find.text('Professor Accounts'), findsNothing);
  });
}
