import 'package:dashboard_layout/dashboard_layout.dart' show ThemeModeStore;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/student_portal_module.dart';
import 'package:student_portal_module/widgets/portal_surface_card.dart';

/// In dark mode the My Documents and Referral rows must be readable:
/// the page's theme used to be the app's light one with only `brightness`
/// flipped, so any text without its own color kept the LIGHT theme's dark
/// default and vanished on the dark card.
void main() {
  Future<void> pumpDark(WidgetTester tester) async {
    final previous = ThemeModeStore.current;
    ThemeModeStore.current = ThemeMode.dark;
    addTearDown(() => ThemeModeStore.current = previous);
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: StudentPortalHomePage(
        initialGoodMoralRequests: [
          GoodMoralRequestStatus(
            id: 'g1',
            documentType: 'Good Moral Certificate',
            purpose: 'Scholarship',
            status: 'Pending',
            requestDate: DateTime(2026, 10, 1),
          ),
        ],
        initialReferrals: [
          ReferralRequestStatus(
            id: 'r1',
            concern: ReferralConcern.academic,
            urgency: 'Normal',
            status: 'Closed',
            createdAt: DateTime(2026, 10, 2),
            counselorNote: 'Please drop by the office.',
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The color [finder]'s text is actually painted with: its own style over the
  /// default text style it inherits.
  Color paintedColor(WidgetTester tester, Finder finder) {
    final text = tester.widget<Text>(finder);
    final inherited = DefaultTextStyle.of(tester.element(finder)).style;
    return inherited.merge(text.style).color!;
  }

  testWidgets('the Documents and Referral rows are light on the dark cards',
      (tester) async {
    await pumpDark(tester);

    const darkCard = Color(0xFF191A1F);
    // Scoped to each card, since a status word like "Pending" appears elsewhere.
    Finder inCard(String cardTitle, String text) => find.descendant(
          of: find
              .ancestor(
                  of: find.text(cardTitle), matching: find.byType(PortalSurfaceCard))
              .first,
          matching: find.text(text),
        );
    for (final (card, label) in [
      ('My Documents', 'Good Moral Certificate — Scholarship'),
      ('Referral', 'Academic difficulties'),
      ('Referral', 'Guidance: Please drop by the office.'),
    ]) {
      final color = paintedColor(tester, inCard(card, label));
      final contrast =
          (color.computeLuminance() + 0.05) / (darkCard.computeLuminance() + 0.05);
      expect(contrast, greaterThan(4.5),
          reason: '"$label" is painted $color on the dark card');
    }
    // The status badges (explicit portal colors) read too.
    for (final (card, label) in [
      ('My Documents', 'Pending'),
      ('Referral', 'Closed'),
    ]) {
      final color = paintedColor(tester, inCard(card, label));
      final contrast =
          (color.computeLuminance() + 0.05) / (darkCard.computeLuminance() + 0.05);
      expect(contrast, greaterThan(4.5),
          reason: 'badge "$label" is painted $color on the dark card');
    }
  });

  testWidgets('the page theme is a real dark theme, so uncolored text defaults light',
      (tester) async {
    await pumpDark(tester);
    final theme = Theme.of(tester.element(find.text('My Documents')));
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.textTheme.bodyMedium!.color!.computeLuminance(), greaterThan(0.5));
  });
}
