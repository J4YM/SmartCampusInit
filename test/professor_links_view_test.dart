import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Professor Accounts on the app-wide table-card layout: a searchable table
/// with status badges and row icon actions, the waiting sign-ins in a side
/// card, and every dialog on the shared popup design.
void main() {
  const signedIn = ProfessorLinkRow(
    id: 'p1',
    fullName: 'Reyes, Ana',
    isStub: false,
    employeeId: 'E-100',
    email: 'ana.reyes@baliuag.sti.edu.ph',
    nameKey: 'ana reyes',
    classCount: 4,
  );
  const waiting = ProfessorLinkRow(
    id: 'p2',
    fullName: 'Cruz, Ben',
    isStub: true,
    claimedEmail: 'ben.cruz@baliuag.sti.edu.ph',
    nameKey: 'ben cruz',
    classCount: 2,
  );
  const noEmail = ProfessorLinkRow(
    id: 'p3',
    fullName: 'Lim, Carla',
    isStub: true,
    nameKey: 'carla lim',
    classCount: 1,
  );
  const dupA = ProfessorLinkRow(
    id: 'p4',
    fullName: 'Santos, Dino',
    isStub: true,
    nameKey: 'dino santos',
  );
  const dupB = ProfessorLinkRow(
    id: 'p5',
    fullName: 'Dino Santos',
    isStub: true,
    nameKey: 'dino santos',
  );
  const login = PendingLoginRow(
    id: 'l1',
    email: 'carla.lim@baliuag.sti.edu.ph',
    fullName: 'Carla Lim',
  );

  Future<void> pumpView(
    WidgetTester tester,
    ProfessorLinksView view, {
    double width = 1500,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: view)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists professors with status badges and the waiting sign-ins',
      (tester) async {
    await pumpView(
      tester,
      const ProfessorLinksView(
        professors: [signedIn, waiting, noEmail],
        pendingLogins: [login],
      ),
    );

    expect(find.text('Professor Accounts'), findsOneWidget);
    expect(find.text('3 professors | 1 signed in | 1 waiting'), findsOneWidget);
    expect(find.text('Reyes, Ana'), findsOneWidget);
    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('No email'), findsOneWidget);
    expect(find.text('ana.reyes@baliuag.sti.edu.ph'), findsOneWidget);
    expect(find.text('ben.cruz@baliuag.sti.edu.ph'), findsOneWidget);

    // The side card.
    expect(find.text('Waiting Sign-ins'), findsOneWidget);
    expect(find.text('carla.lim@baliuag.sti.edu.ph'), findsOneWidget);
  });

  testWidgets('the card title uses the shared card-title size', (tester) async {
    await pumpView(
      tester,
      const ProfessorLinksView(professors: [signedIn], pendingLogins: []),
    );
    final title = tester.widget<Text>(find.text('Professor Accounts'));
    expect(title.style!.fontSize, kCardTitleFontSizeDesktop);
    expect(title.style!.fontWeight, FontWeight.w600);
  });

  testWidgets('search narrows the table', (tester) async {
    await pumpView(
      tester,
      const ProfessorLinksView(
        professors: [signedIn, waiting, noEmail],
        pendingLogins: [],
      ),
    );

    await tester.enterText(
        find.descendant(
            of: find.byKey(const Key('professor-search')),
            matching: find.byType(TextField)),
        'cruz');
    await tester.pumpAndSettle();

    expect(find.text('Cruz, Ben'), findsOneWidget);
    expect(find.text('Reyes, Ana'), findsNothing);
    expect(find.text('Lim, Carla'), findsNothing);
  });

  testWidgets('Connect email opens the shared popup and sends what was typed',
      (tester) async {
    ProfessorLinkRow? target;
    String? sent;
    await pumpView(
      tester,
      ProfessorLinksView(
        professors: const [noEmail],
        pendingLogins: const [],
        onConnectEmail: (p, email) async {
          target = p;
          sent = email;
          return 'stored';
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('connect-p3')));
    await tester.pumpAndSettle();
    expect(find.text('Connect login email'), findsOneWidget);
    expect(find.text('Lim, Carla'), findsWidgets);

    await tester.enterText(
        find.descendant(
            of: find.byType(AppPopup), matching: find.byType(TextField)),
        'carla.lim@baliuag.sti.edu.ph');
    await tester.tap(find.byKey(const Key('connect-save')));
    await tester.pumpAndSettle();

    expect(target?.id, 'p3');
    expect(sent, 'carla.lim@baliuag.sti.edu.ph');
    expect(find.textContaining('will be linked on first sign-in'),
        findsOneWidget);
  });

  testWidgets('a waiting sign-in is linked through the picker, likely match '
      'first', (tester) async {
    PendingLoginRow? linked;
    ProfessorLinkRow? to;
    await pumpView(
      tester,
      ProfessorLinksView(
        professors: const [waiting, noEmail],
        pendingLogins: const [login],
        onLinkLogin: (l, p) async {
          linked = l;
          to = p;
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('link-l1')));
    await tester.pumpAndSettle();
    expect(find.text('Link to a professor'), findsOneWidget);
    expect(find.text('Likely match'), findsOneWidget);

    // The likely match (Lim, Carla) is listed before Cruz, Ben.
    final lim = tester.getTopLeft(find.text('Lim, Carla').last).dy;
    final cruz = tester.getTopLeft(find.text('Cruz, Ben').last).dy;
    expect(lim, lessThan(cruz));

    await tester.tap(find.text('Lim, Carla').last);
    await tester.pumpAndSettle();

    expect(linked?.id, 'l1');
    expect(to?.id, 'p3');
  });

  testWidgets('duplicates are flagged and can be merged after a confirmation',
      (tester) async {
    final calls = <bool>[];
    await pumpView(
      tester,
      ProfessorLinksView(
        professors: const [dupA, dupB, signedIn],
        pendingLogins: const [],
        onMergeDuplicates: ({required dryRun}) async {
          calls.add(dryRun);
          return 1;
        },
      ),
    );

    expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('merge-duplicates')));
    await tester.pumpAndSettle();
    expect(find.text('Merge duplicate professors?'), findsOneWidget);
    expect(calls, [true], reason: 'a dry run first, nothing merged yet');

    await tester.tap(find.byKey(const Key('merge-confirm')));
    await tester.pumpAndSettle();
    expect(calls, [true, false]);
  });

  testWidgets('no callbacks: no row actions and no Link buttons',
      (tester) async {
    await pumpView(
      tester,
      const ProfessorLinksView(
        professors: [waiting],
        pendingLogins: [login],
      ),
    );

    expect(find.byKey(const ValueKey('connect-p2')), findsNothing);
    expect(find.byKey(const ValueKey('merge-p2')), findsNothing);
    expect(find.byKey(const ValueKey('link-l1')), findsNothing);
  });

  testWidgets('empty state, and the side card stacks below on a phone',
      (tester) async {
    await pumpView(
      tester,
      const ProfessorLinksView(professors: [], pendingLogins: []),
      width: 380,
    );

    expect(find.text('No professor records found'), findsOneWidget);
    expect(find.text('No sign-ins are waiting.'), findsOneWidget);
    final table = tester.getTopLeft(find.text('Professor Accounts')).dy;
    final side = tester.getTopLeft(find.text('Waiting Sign-ins')).dy;
    expect(side, greaterThan(table));
    expect(tester.takeException(), isNull);
  });
}
