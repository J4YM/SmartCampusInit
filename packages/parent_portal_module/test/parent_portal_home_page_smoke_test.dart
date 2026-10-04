import 'package:dashboard_layout/dashboard_layout.dart' show AppBottomNavBar;
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationsPopover;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_portal_module/parent_portal_module.dart';
import 'package:parent_portal_module/widgets/month_preview_card.dart';
import 'package:parent_portal_module/widgets/parent_overview_widgets.dart' show AttendanceSummaryCard, DisciplineSummaryCard, InterventionsCard, TodayStatusCard;
import 'package:parent_portal_module/widgets/portal_header_bar.dart';

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(home: ParentPortalHomePage()));
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
/// own chrome ("Notifications" title, timestamps, etc.) can share
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
    testWidgets('parent dashboard renders with no overflow at ${entry.key}',
        (tester) async {
      await _pumpAt(tester, entry.value);

      // Greets the parent, introduces the child, and shows every section.
      expect(
        find.textContaining(RegExp(r'^Good (morning|afternoon|evening), Demo')),
        findsOneWidget,
      );
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      for (final title in [
        'Today',
        'This month at a glance',
        'This Month',
        'Conduct & discipline',
        'Student\'s Document',
      ]) {
        expect(find.text(title), findsWidgets, reason: title);
      }

      // Tap a past day on the calendar — opens its details. Day 1 is always
      // today or in the past, so it is never disabled.
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

      // Tap a violation row — opens its detail sheet.
      final violationTitle = find.text('Improper uniform (no ID lace)').last;
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

    final dayOne = find.descendant(
      of: find.byType(MonthPreviewCard),
      matching: find.text('1'),
    );
    await tester.ensureVisible(dayOne);
    await tester.pumpAndSettle();
    await tester.tap(dayOne);
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

    final dayOne = find.descendant(
      of: find.byType(MonthPreviewCard),
      matching: find.text('1'),
    );
    await tester.ensureVisible(dayOne);
    await tester.pumpAndSettle();
    await tester.tap(dayOne);
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

    final dayOne = find.descendant(
      of: find.byType(MonthPreviewCard),
      matching: find.text('1'),
    );
    await tester.ensureVisible(dayOne);
    await tester.pumpAndSettle();
    await tester.tap(dayOne);
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
    // The Conduct & discipline card's "View all" opens the full list.
    final seeAll = find.descendant(
      of: find.byType(DisciplineSummaryCard),
      matching: find.text('View all'),
    );
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

  testWidgets('hub-preview variant shows a back button, not sign-out',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var poppedToHub = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ParentPortalHomePage(onReturnToHub: () => poppedToHub = true),
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
      'direct-login header (no back button, no standalone sign-out icon) fits at narrow width',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var signedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ParentPortalHomePage(onSignOut: () => signedOut = true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    // The standalone header sign-out icon is gone — Sign Out now lives only
    // inside the profile dropdown, same as every other dashboard.
    expect(find.byIcon(Icons.logout_rounded), findsNothing);
    // Notification/profile live in the bottom nav bar on mobile now
    // (matching every other dashboard), not the header — only Good Moral
    // Request stays in the compact header.
    expect(find.byType(AppBottomNavBar), findsOneWidget);
    expect(find.byIcon(Icons.mail_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsNothing);
    // Profile (and Sign Out within it) is reached via the bottom nav's
    // Profile tab now that the avatar is no longer in the compact header.
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Sign Out'), findsOneWidget);

    // Sign Out opens a confirmation dialog first — tapping it alone must
    // not sign out immediately.
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    expect(signedOut, isFalse);
    expect(find.text('Logout Confirmation'), findsOneWidget);

    await tester.tap(find.text('Yes, logout'));
    await tester.pump();
    expect(signedOut, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'header background stays navy in both light and dark mode, matching '
      'every staff dashboard\'s AppHeaderNavBar', (tester) async {
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
      return container.color;
    }

    expect(headerColor(), const Color(0xFF15253F));

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

  testWidgets('dark mode toggle renders the parent dashboard with no overflow',
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
    expect(find.text('Conduct & discipline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('content stays capped at 1440px on an ultra-wide viewport',
      (tester) async {
    await _pumpAt(tester, const Size(1920, 1080));

    // Conduct & discipline heads the right-hand column.
    final cardFinder = find.text('Conduct & discipline');
    expect(cardFinder, findsOneWidget);
    final topLeft = tester.getTopLeft(cardFinder).dx;
    expect(topLeft, lessThan(1440));
    expect(topLeft, greaterThan(200));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Today card View all opens the complete class schedule, and the'
      ' page no longer has Class schedule or Needs your attention cards',
      (tester) async {
    await _pumpAt(tester, const Size(1440, 900));

    expect(find.text('Needs your attention'), findsNothing);
    expect(find.text('Class schedule'), findsNothing);
    expect(find.text('Attendance by week'), findsNothing);

    await tester.tap(find.descendant(
      of: find.byType(TodayStatusCard),
      matching: find.text('View all'),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Class schedule'), findsOneWidget);
    // The whole week, not just today: every demo subject is listed.
    expect(find.text('Data Structures & Algorithms'), findsWidgets);
    expect(find.text('Mobile Application Development'), findsWidgets);
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Tuesday'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Interventions card lists school messages, flags unread and action'
      ' needed, and opening one marks it read', (tester) async {
    await _pumpAt(tester, const Size(1440, 1000));

    expect(find.text('Interventions'), findsOneWidget);
    // Conduct-card layout: no count badge in the header; a one-line standing
    // and a count line instead.
    expect(find.text('2 new'), findsNothing);
    expect(find.text('2 unread messages from the school.'), findsOneWidget);
    expect(find.text('3 on record  ·  1 need action  ·  1 read'), findsOneWidget);
    expect(find.text('Parent conference requested'), findsOneWidget);
    expect(find.text('Action needed'), findsOneWidget);

    // The card is compact: the message body is only in the popup.
    expect(find.textContaining('Guidance Office this week'), findsNothing);

    await tester.tap(find.text('Parent conference requested'));
    await tester.pumpAndSettle();

    // Opened in a detail popup with just that message, now counted as read.
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.textContaining('Guidance Office this week'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(Dialog), matching: find.text('Tutoring available')),
      findsNothing,
      reason: 'only this message',
    );
    expect(find.text('1 unread message from the school.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Interventions card shows an empty state with no messages',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: ParentPortalHomePage(initialInterventions: []),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No messages from the school right now.'), findsOneWidget);
    expect(find.textContaining('unread'), findsNothing);
    expect(find.text('View all'), findsNWidgets(2), reason: 'Today + Conduct only');
  });

  testWidgets('Interventions View all opens the full list page with folder tabs',
      (tester) async {
    await _pumpAt(tester, const Size(1440, 1000));

    await tester.tap(find.descendant(
      of: find.byType(InterventionsCard),
      matching: find.text('View all'),
    ));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Interventions'), findsOneWidget);
    for (final tab in ['All', 'Action needed', 'Unread', 'Read']) {
      expect(find.text(tab), findsWidgets, reason: tab);
    }
    expect(find.text('Tutoring available'), findsOneWidget);

    // Unread tab narrows the list.
    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    expect(find.text('Tutoring available'), findsNothing);
    expect(find.text('Parent conference requested'), findsOneWidget);

    await tester.tap(find.text('Parent conference requested'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today and This month at a glance are the same height when '
      'side by side', (tester) async {
    for (final size in const [
      Size(1440, 1000), // 4 count tiles per row
      Size(1100, 900), // 2 per row (a narrow violation row once overflowed here)
      Size(1000, 900),
      Size(820, 900), // narrowest two-up layout
    ]) {
      await _pumpAt(tester, size);
      final today = tester.getSize(find.byType(TodayStatusCard));
      final summary = tester.getSize(find.byType(AttendanceSummaryCard));
      expect(today.height, summary.height, reason: '$size');
      expect(tester.getTopLeft(find.byType(TodayStatusCard)).dy,
          tester.getTopLeft(find.byType(AttendanceSummaryCard)).dy,
          reason: '$size: same row');
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('tapping the "unread messages" banner opens the Interventions '
      'page on the Unread tab', (tester) async {
    await _pumpAt(tester, const Size(1440, 1000));

    await tester.tap(find.text('2 unread messages from the school.'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Interventions'), findsOneWidget);
    // Already on Unread: the read message is hidden without touching a tab.
    expect(find.text('Parent conference requested'), findsOneWidget);
    expect(find.text('Tutoring available'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the Conduct banner opens the Violations page on the '
      'tab it describes', (tester) async {
    await _pumpAt(tester, const Size(1440, 1000));

    final banner = find.descendant(
      of: find.byType(DisciplineSummaryCard),
      matching: find.textContaining(RegExp(r'under review|resolved and recorded')),
    );
    final pending = (tester.widget<Text>(banner).data ?? '').contains('review');
    await tester.tap(banner);
    await tester.pumpAndSettle();

    expect(
        find.widgetWithText(AppBar, 'Violations & Offenses'), findsOneWidget);
    // The tab matching the banner is the selected one: its rows are the only
    // ones listed, so every row's status badge agrees with it.
    expect(find.text(pending ? 'Recorded' : 'Pending'), findsWidgets,
        reason: 'tab label itself');
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text(pending ? 'Recorded' : 'Pending'),
      ),
      findsNothing,
      reason: 'no rows from the other status',
    );
    expect(tester.takeException(), isNull);
  });
}
