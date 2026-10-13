import 'package:dashboard_layout/dashboard_layout.dart'
    show AppPopupDropdown, AppPopupPrimaryButton, AppPopupTextField;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/student_portal_module.dart';

Future<void> _pumpAt(
  WidgetTester tester,
  Size size, {
  void Function({
    required ReferralConcern concern,
    required String details,
    String? aboutStudentNumber,
    required bool urgent,
  })? onSubmitReferral,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: StudentPortalHomePage(onSubmitReferral: onSubmitReferral),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'Request Support sits at the far right of the Support & Referrals card',
      (tester) async {
    await _pumpAt(tester, const Size(1440, 900));

    final title = find.text('Support & Referrals');
    final button = find.text('Request Support');
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();

    // The button is right of the title on the same row...
    expect(tester.getTopLeft(button).dx,
        greaterThan(tester.getTopRight(title).dx));
    expect((tester.getCenter(button).dy - tester.getCenter(title).dy).abs(),
        lessThan(20));

    // ...and its pill ends at the card's inner right edge, not mid-card.
    final pill = find.ancestor(of: button, matching: find.byType(InkWell)).first;
    final cardRight = tester
        .getBottomRight(find
            .ancestor(of: title, matching: find.byType(Column))
            .first)
        .dx;
    expect(tester.getBottomRight(pill).dx, closeTo(cardRight, 1.0));
  });

  for (final size in const [Size(1440, 900), Size(390, 900)]) {
    testWidgets('Request Support form opens as a popup and submits at '
        '${size.width.toInt()}px', (tester) async {
      ReferralConcern? sentConcern;
      String? sentDetails;
      String? sentAbout;
      var sentUrgent = false;
      await _pumpAt(tester, size, onSubmitReferral: ({
        required concern,
        required details,
        aboutStudentNumber,
        required urgent,
      }) {
        sentConcern = concern;
        sentDetails = details;
        sentAbout = aboutStudentNumber;
        sentUrgent = urgent;
      });

      await tester.ensureVisible(find.text('Request Support'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request Support'));
      await tester.pumpAndSettle();

      // A popup (not a pushed page): the shared field kit, no app bar.
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(AppPopupDropdown<bool>), findsOneWidget);
      expect(find.byType(AppPopupDropdown<ReferralConcern>), findsOneWidget);
      expect(find.byType(AppPopupTextField), findsOneWidget);

      // Too-short details are rejected, with the message under the field.
      await tester.tap(find.byKey(const Key('referral-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Please write at least a sentence'), findsOneWidget);
      expect(sentConcern, isNull);

      await tester.enterText(
          find.byType(AppPopupTextField), 'I have been feeling very anxious.');
      await tester.pump();
      expect(find.text('Please write at least a sentence'), findsNothing);

      final submit = find.byType(AppPopupPrimaryButton);
      await tester.ensureVisible(submit);
      await tester.tap(find.byKey(const Key('referral-submit')));
      await tester.pumpAndSettle();

      expect(sentConcern, ReferralConcern.emotional);
      expect(sentDetails, 'I have been feeling very anxious.');
      expect(sentAbout, isNull);
      expect(sentUrgent, isFalse);
      // The popup closed itself.
      expect(find.byType(AppPopupTextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('"Someone else" asks for the classmate\'s student number',
      (tester) async {
    await _pumpAt(tester, const Size(1440, 900));
    await tester.ensureVisible(find.text('Request Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request Support'));
    await tester.pumpAndSettle();

    expect(find.text('Their student number'), findsNothing);
    await tester.tap(find.byType(AppPopupDropdown<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Someone else').last);
    await tester.pumpAndSettle();
    expect(find.text('Their student number'), findsOneWidget);

    await tester.tap(find.byKey(const Key('referral-submit')));
    await tester.pumpAndSettle();
    expect(find.text("Enter your classmate's student number"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
