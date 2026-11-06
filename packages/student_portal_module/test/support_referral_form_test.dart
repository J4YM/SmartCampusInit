import 'package:dashboard_layout/dashboard_layout.dart'
    show
        AppPopupChoicePill,
        AppPopupDropdown,
        AppPopupPrimaryButton,
        AppPopupTextField,
        GoodMoralFormData,
        ReferralFormData,
        ReferralFormDocument;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/student_portal_module.dart';

Future<void> _pumpAt(
  WidgetTester tester,
  Size size, {
  void Function({
    required ReferralConcern concern,
    required String details,
    required bool urgent,
    required ReferralFormData form,
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
  testWidgets('Request Support sits at the far right of the Referral card',
      (tester) async {
    await _pumpAt(tester, const Size(1440, 900));

    final title = find.text('Referral');
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
      var sentUrgent = false;
      ReferralFormData? sentForm;
      await _pumpAt(tester, size, onSubmitReferral: ({
        required concern,
        required details,
        required urgent,
        required form,
      }) {
        sentConcern = concern;
        sentDetails = details;
        sentUrgent = urgent;
        sentForm = form;
      });

      await tester.ensureVisible(find.text('Request Support'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request Support'));
      await tester.pumpAndSettle();

      // A popup (not a pushed page): the shared field kit, no app bar.
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(AppPopupDropdown<ReferralConcern>), findsOneWidget);
      expect(find.widgetWithText(AppPopupTextField, 'Tell us what is going on'),
          findsOneWidget);

      // Too-short details are rejected, with the message under the field.
      await tester.tap(find.byKey(const Key('referral-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Please write at least a sentence'), findsOneWidget);
      expect(sentConcern, isNull);

      await tester.enterText(
          find.widgetWithText(AppPopupTextField, 'Tell us what is going on'),
          'I have been feeling very anxious.');
      await tester.pump();
      expect(find.text('Please write at least a sentence'), findsNothing);

      final submit = find.byType(AppPopupPrimaryButton);
      await tester.ensureVisible(submit);
      await tester.tap(find.byKey(const Key('referral-submit')));
      await tester.pumpAndSettle();

      expect(sentConcern, ReferralConcern.emotional);
      expect(sentDetails, 'I have been feeling very anxious.');
      expect(sentUrgent, isFalse);
      // The popup closed itself.
      expect(find.byType(AppPopupTextField), findsNothing);
      expect(sentForm, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the referral form is for the student only: no classmate option',
      (tester) async {
    await _pumpAt(tester, const Size(1440, 900));
    await tester.ensureVisible(find.text('Request Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request Support'));
    await tester.pumpAndSettle();

    expect(find.byType(AppPopupDropdown<bool>), findsNothing);
    expect(find.text('Their student number'), findsNothing);
    expect(find.text('Someone else'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the External Referral Form fields are sent with the referral, '
      'prefilled from the account', (tester) async {
    ReferralFormData? sentForm;
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: StudentPortalHomePage(
        studentName: 'Juan Dela Cruz',
        programLine: 'BS Information Technology · 3rd Year · Section A',
        goodMoralPrefill: const GoodMoralFormData(
          firstName: 'Juan',
          lastName: 'Dela Cruz',
          studentNumber: '2023-0001',
          section: 'BSIT 3A',
          contactNumber: '09171234567',
        ),
        onSubmitReferral: ({
          required concern,
          required details,
          required urgent,
          required form,
        }) =>
            sentForm = form,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Request Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request Support'));
    await tester.pumpAndSettle();

    // What the account knows is shown, not asked again.
    expect(find.textContaining('2023-0001'), findsOneWidget);
    expect(find.textContaining('BSIT 3A'), findsOneWidget);
    expect(find.textContaining('09171234567'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(AppPopupTextField, 'Tell us what is going on'),
        'I cannot focus on my exams.');
    await tester.enterText(find.byKey(const Key('referral-address')),
        '12 Rizal St, Baliuag');
    await tester.enterText(
        find.byKey(const Key('referral-birthdate')), '05/14/2004');
    // Tapped out of the form's order, sent in the form's order.
    for (final key in const [
      'concern-personal-Anxiety',
      'concern-academic-Test anxiety',
      'concern-academic-Absenteeism',
      'referral-to-Psychologist',
    ]) {
      final pill = find.byKey(Key(key));
      await tester.ensureVisible(pill);
      await tester.pumpAndSettle();
      await tester.tap(pill);
      await tester.pump();
    }
    final other = find.byKey(const Key('referral-other-career'));
    await tester.ensureVisible(other);
    await tester.enterText(other, 'Switching course');

    final submit = find.byKey(const Key('referral-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final form = sentForm!;
    expect(form.studentName, 'Juan Dela Cruz');
    expect(form.studentNumber, '2023-0001');
    expect(form.section, 'BSIT 3A');
    expect(form.contactNumber, '09171234567');
    expect(form.program, 'BS Information Technology');
    expect(form.address, '12 Rizal St, Baliuag');
    expect(form.birthdate, '05/14/2004');
    expect(form.referralTo, ['Guidance Counselor', 'Psychologist']);
    expect(form.academic, ['Absenteeism', 'Test anxiety']);
    expect(form.personal, ['Anxiety']);
    expect(form.otherCareer, 'Switching course');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sent referral can be opened again as a printable form',
      (tester) async {
    ReferralFormDocument? opened;
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: StudentPortalHomePage(
        initialReferrals: [
          ReferralRequestStatus(
            id: 'r1',
            concern: ReferralConcern.academic,
            urgency: 'Normal',
            status: 'Pending',
            createdAt: DateTime(2026, 11, 6),
            details: 'Exams are overwhelming.',
            form: const ReferralFormData(
                studentName: 'Juan Dela Cruz', academic: ['Test anxiety']),
          ),
        ],
        onViewReferralForm: (d) => opened = d,
      ),
    ));
    await tester.pumpAndSettle();
    final view = find.byKey(const Key('referral-form-r1'));
    await tester.ensureVisible(view);
    await tester.pumpAndSettle();
    await tester.tap(view);

    expect(opened!.form.studentName, 'Juan Dela Cruz');
    expect(opened!.form.academic, ['Test anxiety']);
    expect(opened!.details, 'Exams are overwhelming.');
    expect(opened!.concernLabel, 'Academic difficulties');
    expect(opened!.schoolYear, '2026 - 2027');
  });

  testWidgets('only self-referral concerns are offered', (tester) async {
    expect(ReferralConcern.selfReferralChoices, [
      ReferralConcern.emotional,
      ReferralConcern.family,
      ReferralConcern.academic,
      ReferralConcern.other,
    ]);
  });
}
