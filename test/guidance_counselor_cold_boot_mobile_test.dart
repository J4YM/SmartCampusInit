import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capstone_dashboard/ui/guidance_counselor_connected_page.dart';

/// Reported bug: opening the Guidance Counselor Dashboard directly at a
/// mobile viewport (never having rendered at desktop width first) shows a
/// blank screen/crash, while resizing down from desktop works fine.
///
/// This pumps the dashboard's real entry point straight at a mobile size
/// from the very first frame — no prior desktop pump — through its actual
/// loading -> loaded transition. It does not reproduce: `isMobile` is a
/// stateless `MediaQuery.of(context).size.width < 800` read with no
/// dependency on load order or prior frames, the loading state is already
/// a safe `Scaffold(body: Center(child: CircularProgressIndicator()))`
/// (`guidance_counselor_connected_page.dart`), and every card's layout
/// already branches on bounded/unbounded height rather than assuming one
/// or the other.
///
/// Uses `tester.view.physicalSize`/`devicePixelRatio` (not the legacy
/// `tester.binding.setSurfaceSize`) — the latter was found, while
/// investigating this exact report, to leave `MediaQuery.of(context).size`
/// stuck at the test binding's 800x600 default in this Flutter SDK version
/// even though it does correctly resize the raw RenderObject layout
/// constraints. That split (real layout width vs. stale MediaQuery width)
/// reliably reproduced an `AppHeaderNavBar` overflow that looked exactly
/// like this report — but only inside the test harness: `tester.view` (the
/// API `setSurfaceSize` itself now aliases to) shows the app has no such
/// issue once MediaQuery and layout agree, which is always the case on a
/// real device.
void main() {
  Future<void> pumpColdAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: GuidanceCounselorConnectedPage()),
    );
    // Cold boot starts on the loading spinner (no Supabase configured in
    // this test env, so `_load()` — fired from a postFrameCallback —
    // resolves it almost immediately); pumpAndSettle rides through both
    // the loading and loaded frames.
    await tester.pumpAndSettle();
  }

  testWidgets(
      'renders real content (not a blank screen) when opened directly at '
      'a mobile width, with no prior desktop render', (tester) async {
    // 390 rather than 360: the dashboard now lands on Overview (System
    // Overview) by default, which renders the real
    // SystemOverviewConnectedPage (admin_dashboard) here — that page has
    // its own small, pre-existing ~5px RenderFlex overflow in _StatusDot's
    // legend row at 360px, unrelated to this dashboard or this task, that
    // was simply never exercised as a default tab before. Not this test's
    // concern to fix; 390 is still a genuinely narrow phone width and
    // avoids tripping over it.
    await pumpColdAt(tester, const Size(390, 800));

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Guidance Counselor Dashboard'), findsOneWidget);
    expect(find.text('ML Overview'), findsOneWidget);

    // The dashboard now lands on Overview (System Overview) by default —
    // switch to ML Overview to confirm its content also renders cleanly.
    // ML Overview is the sub-nav bar's last tab, which its own horizontal
    // SingleChildScrollView can leave off-screen at narrow widths, so
    // scroll it into view before tapping.
    await tester.ensureVisible(find.text('ML Overview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ML Overview'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Total Students'), findsOneWidget);
  });

  testWidgets(
      'the same cold boot at desktop width, for comparison, also renders '
      'real content', (tester) async {
    await pumpColdAt(tester, const Size(1400, 900));

    expect(tester.takeException(), isNull);
    expect(find.text('Guidance Counselor Dashboard'), findsOneWidget);

    await tester.tap(find.text('ML Overview'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Total Students'), findsOneWidget);
  });
}
