import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

void main() {
  Widget buildPage() {
    return MaterialApp(
      home: ItTechnicianDashboardPage(
        studentRecordsTabBuilder: (_) => const Center(child: Text('Student Records Content')),
        readerDevicesTabBuilder: (_) => const Center(child: Text('Reader Devices Content')),
        technicalIssuesTabBuilder: (_) => const Center(child: Text('Technical Issues Content')),
      ),
    );
  }

  // `tester.binding.setSurfaceSize` does not propagate into `MediaQuery` on
  // this Flutter version (3.41.9) — `MediaQuery.fromView` reads
  // `tester.view.physicalSize` directly, which `setSurfaceSize` leaves
  // untouched. Setting `tester.view.physicalSize`/`devicePixelRatio`
  // directly (the replacement the Flutter SDK's own doc comment on
  // `setSurfaceSize` recommends) is what actually changes
  // `context.isMobileWidth`'s reading of `MediaQuery.of(context).size`.
  void setLogicalSurfaceSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets(
      'starts on Student Records (with its merged metric cards) and switches tabs on tap',
      (tester) async {
    setLogicalSurfaceSize(tester, const Size(1400, 900));

    await tester.pumpWidget(buildPage());

    // The Overview tab was removed — its 3 metric cards now sit above the
    // Student Records tab's own content instead, which is the default tab.
    expect(find.text('Total Students'), findsOneWidget);
    expect(find.text('Student Records Content'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);

    await tester.tap(find.text('Reader Devices'));
    await tester.pumpAndSettle();
    expect(find.text('Reader Devices Content'), findsOneWidget);
    expect(find.text('Total Students'), findsNothing);

    await tester.tap(find.text('Technical Issues'));
    await tester.pumpAndSettle();
    expect(find.text('Technical Issues Content'), findsOneWidget);
  });

  testWidgets('renders the real embedded reader page on a mobile viewport without a layout exception', (tester) async {
    // Regression test: the shell's mobile branch lays tab content out inside
    // a SingleChildScrollView (unbounded height). RfidReaderManagementPage's
    // body used an `Expanded` around its ListView unconditionally, which
    // throws "RenderFlex children have non-zero flex but incoming height
    // constraints are unbounded" there. Uses the REAL page (not a Text stub)
    // precisely because a stub can't reproduce that.
    setLogicalSurfaceSize(tester, const Size(375, 812));

    final readers = List.generate(
      6,
      (i) => RfidReaderRowModel(
        id: 'r$i',
        label: 'Floor $i Reader',
        usbSerial: 'USB-$i',
        location: 'Floor $i — Hallway',
        isKioskReader: i == 0,
        isActive: true,
        isOnline: i.isEven,
        lastSeenLabel: '${i}m ago',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ItTechnicianDashboardPage(
          studentRecordsTabBuilder: (_) => const Center(child: Text('Student Records Content')),
          readerDevicesTabBuilder: (_) => RfidReaderManagementPage(
            embedded: true,
            readers: readers,
            isBusy: false,
            onAddReader: ({required label, required usbSerial, location}) async {},
            onUpdateReader: ({required id, required label, required usbSerial, location}) async {},
            onSetActive: (_, __) async {},
          ),
          technicalIssuesTabBuilder: (_) => const Center(child: Text('Technical Issues Content')),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    // The sub-nav scrolls horizontally; at 375px the last two tabs start off
    // to the right of the viewport.
    await tester.ensureVisible(find.text('Reader Devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reader Devices'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Floor 0 Reader'), findsOneWidget);
  });

  testWidgets('switches to bottom nav below the mobile breakpoint', (tester) async {
    // A standard phone width, comfortably below both this shell's own
    // mobile breakpoint (800, kDashboardMobileBreakpoint) and the Overview
    // tab's internal stat-card grid breakpoint (560) — avoids the narrow
    // 560-620ish band where the stat-card Row's fixed-height cards render
    // too tight for their text by ~1px, a separate, pre-existing content-
    // sizing issue unrelated to what this test verifies.
    setLogicalSurfaceSize(tester, const Size(375, 812));

    await tester.pumpWidget(buildPage());

    // Proves the mobile branch actually took effect: the real bottom-nav
    // widget rendered...
    expect(find.byType(AppBottomNavBar), findsOneWidget);
    // ...and the desktop header's inline mail/notification action icons
    // (2 HeaderIconButtons when onSignOut is null, as in buildPage()) did
    // NOT render. Both assertions together would fail if `isMobile` were
    // hardcoded to false, unlike checking for Flutter's built-in
    // BottomNavigationBar (never used by this shell) or a shared icon that
    // appears on both branches.
    expect(find.byType(HeaderIconButton), findsNothing);
  });
}
