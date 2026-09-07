import 'package:dashboard_layout/dashboard_layout.dart' show AppBottomNavBar;
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show EmailPopover, NotificationsPopover;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/student_portal_module.dart';
import 'package:student_portal_module/widgets/month_preview_card.dart';
import 'package:student_portal_module/widgets/portal_header_bar.dart';

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(home: StudentPortalHomePage()));
  await tester.pumpAndSettle();
}

/// Dismisses the currently-open modal bottom sheet/dialog by tapping its
/// scrim/barrier, rather than a raw screen-coordinate tap (which can land
/// on an in-flight overscroll/transition transform mid-animation and
/// throw). Works for both `showResponsiveSheet` branches: the bottom
/// sheet's scrim covers everywhere above the sheet, and a centered
/// dialog's barrier is dismissible by tapping outside it — (200, 40) sits
/// outside either at every viewport size these tests use.
Future<void> _dismissSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(200, 40));
  await tester.pumpAndSettle();
}

/// `showResponsiveSheet` renders a `BottomSheet` below the mobile-width
/// breakpoint and a `Dialog` at or above it — mirrors
/// `dashboard_layout`'s `kDashboardMobileBreakpoint` (800).
Finder _responsiveSheetFinder(Size viewport) =>
    find.byType(viewport.width < 800 ? BottomSheet : Dialog);

/// Dismisses the currently-open header popover (a `showMenu` route) by
/// tapping its barrier, well outside the popover card's own bounds.
Future<void> _dismissPopover(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 850));
  await tester.pumpAndSettle();
}

/// Scopes a text finder to a specific popover card, since the popover's
/// own chrome ("Notifications"/"Email" title, timestamps, etc.) can share
/// text with other parts of the page.
Finder _inPopover(Type popoverType, String text) => find.descendant(
      of: find.byType(popoverType),
      matching: find.text(text),
    );

void main() {
  final sizes = <String, Size>{
    'narrow phone': const Size(320, 900),
    'phone': const Size(390, 900),
    'tablet': const Size(834, 1194),
    'desktop': const Size(1440, 900),
  };

  for (final entry in sizes.entries) {
    testWidgets('bento dashboard renders with no overflow at ${entry.key}',
        (tester) async {
      await _pumpAt(tester, entry.value);

      // Hero, month, and violations tiles all present.
      expect(
        find.textContaining(RegExp(r'^Good (morning|afternoon|evening),')),
        findsOneWidget,
      );
      expect(find.text('This Month'), findsOneWidget);
      expect(find.text('Violations & Offenses'), findsOneWidget);

      // Tap a past day cell in the month grid — opens the day-detail sheet.
      // Day 1 is always either today or in the past, so it's never disabled.
      final dayOne = find.descendant(
        of: find.byType(MonthPreviewCard),
        matching: find.text('1'),
      );
      await tester.ensureVisible(dayOne);
      await tester.pumpAndSettle();
      await tester.tap(dayOne);
      await tester.pumpAndSettle();
      final daySheet = _responsiveSheetFinder(entry.value);
      expect(daySheet, findsOneWidget);
      await _dismissSheet(tester);
      expect(daySheet, findsNothing);

      // Tap a violation row — opens its detail sheet. The month grid above
      // it can push it below the fold, so scroll it into view first.
      final violationTitle = find.text('Improper uniform (no ID lace)');
      if (tester.any(violationTitle)) {
        await tester.ensureVisible(violationTitle);
        await tester.pumpAndSettle();
        await tester.tap(violationTitle);
        await tester.pumpAndSettle();
        final violationSheet = _responsiveSheetFinder(entry.value);
        expect(violationSheet, findsOneWidget);
        await _dismissSheet(tester);
        expect(violationSheet, findsNothing);
      }

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'day-detail sheet is a top-rounded bottom sheet with a drag handle '
      'on mobile', (tester) async {
    await _pumpAt(tester, const Size(390, 900));

    await tester.tap(
      find.descendant(
        of: find.byType(MonthPreviewCard),
        matching: find.text('1'),
      ),
    );
    await tester.pumpAndSettle();

    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    final shape = sheet.shape as RoundedRectangleBorder;
    expect(shape.borderRadius, const BorderRadius.vertical(top: Radius.circular(24)));

    // The drag handle is a small pill-shaped Container above the content —
    // identified by its fixed 40x4 size, distinct from any content sizing.
    final handles = tester.widgetList<Container>(find.byType(Container)).where(
        (c) => c.constraints == const BoxConstraints.tightFor(width: 40, height: 4));
    expect(handles, isNotEmpty);
  });

  testWidgets(
      'day-detail sheet is a centered, max-width dialog with no drag '
      'handle on desktop', (tester) async {
    await _pumpAt(tester, const Size(1440, 900));

    await tester.tap(
      find.descendant(
        of: find.byType(MonthPreviewCard),
        matching: find.text('1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    final shape = dialog.shape as RoundedRectangleBorder;
    // All four corners rounded (not top-only, like the mobile sheet).
    expect(shape.borderRadius, BorderRadius.circular(20));

    // Dialog wraps its own content in several ConstrainedBoxes internally
    // (for its default sizing) — look for the specific 480px cap
    // showResponsiveSheet applies rather than assuming there's only one.
    final maxWidthBoxes = tester.widgetList<ConstrainedBox>(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(ConstrainedBox),
      ),
    ).where((box) => box.constraints.maxWidth == 480);
    expect(maxWidthBoxes, hasLength(1));

    // No mobile drag handle on the desktop dialog path.
    final handles = tester.widgetList<Container>(find.byType(Container)).where(
        (c) => c.constraints == const BoxConstraints.tightFor(width: 40, height: 4));
    expect(handles, isEmpty);
  });

  testWidgets('day-detail sheet closes when the close (X) button is tapped',
      (tester) async {
    await _pumpAt(tester, const Size(1440, 900));

    await tester.tap(
      find.descendant(
        of: find.byType(MonthPreviewCard),
        matching: find.text('1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('View all on Violations opens the full Violations page',
      (tester) async {
    await _pumpAt(tester, const Size(390, 900));
    // The Violations card is the dashboard's only remaining "View all" link
    // now that the month card shows the whole month directly and the
    // Communications panel is gone. The month grid pushes it well below
    // the fold, so scroll it into view before tapping.
    final seeAll = find.text('View all').first;
    await tester.ensureVisible(seeAll);
    await tester.pumpAndSettle();
    await tester.tap(seeAll);
    await tester.pumpAndSettle();
    expect(
        find.widgetWithText(AppBar, 'Violations & Offenses'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Violations & Offenses'), findsNothing);
  });

  testWidgets(
      'notifications bell opens the shared NotificationsPopover, unfiltered',
      (tester) async {
    await _pumpAt(tester, const Size(390, 900));
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();

    // Same component every staff dashboard's bell opens — and unlike the
    // old sender-filtered popover, it shows every notification regardless
    // of who sent it.
    expect(find.byType(NotificationsPopover), findsOneWidget);
    expect(_inPopover(NotificationsPopover, 'Notifications'), findsOneWidget);
    expect(_inPopover(NotificationsPopover, 'Violation report received'),
        findsOneWidget);
    expect(
        _inPopover(
            NotificationsPopover, 'Mobile App Dev — project deadline moved'),
        findsOneWidget);

    await tester.tap(_inPopover(NotificationsPopover, 'Mark all as read'));
    await tester.pumpAndSettle();

    // Popover closes itself on "Mark all as read".
    expect(find.byType(NotificationsPopover), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mail icon opens the shared EmailPopover, empty by design',
      (tester) async {
    await _pumpAt(tester, const Size(390, 900));
    await tester.tap(find.byIcon(Icons.mail_outline_rounded));
    await tester.pumpAndSettle();

    // Same component every staff dashboard's mail icon opens — no inbox
    // backend exists anywhere in this app yet, so it always shows the
    // shared empty state.
    expect(find.byType(EmailPopover), findsOneWidget);
    expect(_inPopover(EmailPopover, 'Email'), findsOneWidget);
    expect(_inPopover(EmailPopover, 'No Email'), findsOneWidget);

    await _dismissPopover(tester);
    expect(find.byType(EmailPopover), findsNothing);
  });

  testWidgets(
      "notifications popover's View all swaps in the Notifications list, "
      'in place (no new page)', (tester) async {
    await _pumpAt(tester, const Size(390, 900));
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();

    await tester.tap(
        _inPopover(NotificationsPopover, 'View all notifications'));
    await tester.pumpAndSettle();

    // Swapped in place — no pushed route/AppBar, and the bento tiles are
    // replaced rather than left underneath.
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('This Month'), findsNothing);
    expect(find.byType(AppBar), findsNothing);

    // The back arrow returns to the bento dashboard.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('This Month'), findsOneWidget);
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets(
      "email popover's View all swaps in the Email list, in place "
      '(no new page)', (tester) async {
    await _pumpAt(tester, const Size(390, 900));
    await tester.tap(find.byIcon(Icons.mail_outline_rounded));
    await tester.pumpAndSettle();

    await tester.tap(_inPopover(EmailPopover, 'View all emails'));
    await tester.pumpAndSettle();

    // Scoped to the scrollable body content, since the bottom nav bar's own
    // "Email" tab label (outside the scroll view) now also matches
    // find.text('Email') at this compact width.
    Finder inBody(String text) => find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.text(text),
        );

    expect(inBody('Email'), findsOneWidget);
    expect(find.text('This Month'), findsNothing);
    expect(find.byType(AppBar), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('This Month'), findsOneWidget);
    expect(inBody('Email'), findsNothing);
  });

  testWidgets('month card steps back a month and re-enables next',
      (tester) async {
    await _pumpAt(tester, const Size(390, 900));

    // Scoped to the month card — the violation rows on the same page also
    // use a chevron-right icon (their "open detail" affordance).
    Finder monthNavIcon(IconData icon) => find.descendant(
          of: find.byType(MonthPreviewCard),
          matching: find.byIcon(icon),
        );

    await tester.tap(monthNavIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();

    // Still on the month card, no exception, and the next-month arrow
    // (disabled at the current month) becomes usable again.
    expect(find.text('This Month'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(monthNavIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hub-preview variant shows a back button, not sign-out',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var poppedToHub = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StudentPortalHomePage(onReturnToHub: () => poppedToHub = true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.logout_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    expect(poppedToHub, isTrue);
  });

  testWidgets(
      'direct-login header (sign-out, no back button) fits at narrow width',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var signedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StudentPortalHomePage(onSignOut: () => signedOut = true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    // Mail/notification/profile live in the bottom nav bar on mobile now
    // (matching every other dashboard), not the header — only sign-out
    // stays in the compact header.
    expect(find.byType(AppBottomNavBar), findsOneWidget);
    expect(find.byIcon(Icons.mail_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    // Dark Mode lives in the profile dropdown, opened via the bottom nav's
    // Profile tab now that the avatar is no longer in the compact header.
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.logout_rounded));
    await tester.pump();
    expect(signedOut, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header background is white in light mode, navy in dark mode',
      (tester) async {
    await _pumpAt(tester, const Size(390, 900));

    Color? headerColor() {
      final container = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(PortalHeaderBar),
              matching: find.byType(Container),
            ),
          )
          .first;
      return (container.decoration as BoxDecoration?)?.color;
    }

    expect(headerColor(), Colors.white);

    // Dark Mode lives in the profile dropdown, opened via the bottom nav's
    // Profile tab at this compact width — the header avatar only shows at
    // desktop widths now.
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark Mode'));
    await tester.pumpAndSettle();

    expect(headerColor(), const Color(0xFF15253F));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mode toggle renders the bento dashboard with no overflow',
      (tester) async {
    await _pumpAt(tester, const Size(390, 900));

    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark Mode'));
    await tester.pumpAndSettle();
    // Toggling doesn't close the dropdown — its own row label flips to
    // confirm the new state, same as every staff dashboard's menu.
    expect(find.text('Light Mode'), findsOneWidget);
    await _dismissPopover(tester);

    // Every tile still present and legible after the theme flip.
    expect(find.text('This Month'), findsOneWidget);
    expect(find.text('Violations & Offenses'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('content stays capped at 1440px on an ultra-wide viewport',
      (tester) async {
    await _pumpAt(tester, const Size(1920, 1080));

    // Violations & Offenses is now the right-hand tile (Communications was
    // removed and Violations took its place).
    final cardFinder = find.text('Violations & Offenses');
    expect(cardFinder, findsOneWidget);
    final topLeft = tester.getTopLeft(cardFinder).dx;
    expect(topLeft, lessThan(1440));
    expect(topLeft, greaterThan(200));

    expect(tester.takeException(), isNull);
  });
}
