import 'package:dashboard_layout/dashboard_layout.dart' show AppPopupPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';

RegistrarStudentModel _student({
  String standing = 'Good',
  EnrollmentStatus status = EnrollmentStatus.inactive,
}) =>
    RegistrarStudentModel(
      id: 's1',
      name: 'Jane Doe',
      studentId: '2024-0001',
      program: 'BS Information Technology',
      section: 'BSIT 3-A',
      status: status,
      enrollmentStanding: standing,
    );

Future<void> _pumpRecords(
  WidgetTester tester,
  RegistrarStudentModel selected, {
  Future<List<StudentSanctionEntry>> Function(String studentId)? onFetchSanctions,
  Future<void> Function(String studentId, String reason)? onLiftRestriction,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: StudentRecordsView(
        students: [selected],
        selectedStudent: selected,
        onSelect: (_) {},
        onConfirmEnrollment: (_) async {},
        onFetchSanctions: onFetchSanctions,
        onLiftRestriction: onLiftRestriction,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('RegistrarStudentModel standing', () {
    test('only Non_Readmission and Dismissed are restricted', () {
      expect(_student().isRestricted, isFalse);
      expect(_student(standing: 'Non_Readmission').isRestricted, isTrue);
      expect(_student(standing: 'Dismissed').isRestricted, isTrue);
    });

    test('labels', () {
      expect(_student(standing: 'Non_Readmission').standingLabel,
          'Not for readmission');
      expect(_student(standing: 'Dismissed').standingLabel, 'Dismissed');
      expect(_student().standingLabel, 'Good standing');
    });

    test('copyWith keeps the standing', () {
      expect(_student(standing: 'Dismissed').copyWith(hasRfid: false).enrollmentStanding,
          'Dismissed');
    });
  });

  group('Student profile', () {
    testWidgets('a restricted student shows the block and cannot be re-enrolled',
        (tester) async {
      await _pumpRecords(tester, _student(standing: 'Non_Readmission'));
      expect(find.byKey(const Key('enrollment-restricted-banner')), findsOneWidget);
      expect(find.text('Not for readmission'), findsWidgets);
      expect(find.byKey(const Key('confirm-student-enrollment')), findsNothing);
    });

    testWidgets('a student in good standing can still be confirmed',
        (tester) async {
      await _pumpRecords(tester, _student());
      expect(find.byKey(const Key('enrollment-restricted-banner')), findsNothing);
      expect(find.byKey(const Key('confirm-student-enrollment')), findsOneWidget);
    });

    testWidgets('shows the disciplinary record from Student Affairs',
        (tester) async {
      await _pumpRecords(
        tester,
        _student(standing: 'Non_Readmission'),
        onFetchSanctions: (id) async => [
          StudentSanctionEntry(
            typeLabel: 'Non-readmission',
            description: 'Not to be readmitted next term',
            effectiveOn: DateTime(2026, 10, 20),
            affectsEnrollment: true,
          ),
          StudentSanctionEntry(
            typeLabel: 'Warning',
            description: 'Written warning',
            effectiveOn: DateTime(2026, 9, 1),
          ),
        ],
      );
      expect(find.text('Disciplinary record'), findsOneWidget);
      expect(find.text('Not to be readmitted next term'), findsOneWidget);
      expect(find.text('Written warning'), findsOneWidget);
    });

    testWidgets('an administrator can lift the restriction, with a reason',
        (tester) async {
      String? liftedId;
      String? liftedReason;
      await _pumpRecords(
        tester,
        _student(standing: 'Non_Readmission'),
        onLiftRestriction: (id, reason) async {
          liftedId = id;
          liftedReason = reason;
        },
      );
      await tester.tap(find.byKey(const Key('lift-restriction')));
      await tester.pumpAndSettle();

      bool confirmEnabled() => tester
              .widget<AppPopupPrimaryButton>(find.byKey(const Key('lift-confirm')))
              .onPressed !=
          null;
      expect(confirmEnabled(), isFalse);
      await tester.enterText(find.byKey(const Key('lift-reason')), '   ');
      await tester.pump();
      expect(confirmEnabled(), isFalse);
      await tester.enterText(
          find.byKey(const Key('lift-reason')), 'Appeal granted by the dean');
      await tester.pump();
      expect(confirmEnabled(), isTrue);
      await tester.tap(find.byKey(const Key('lift-confirm')));
      await tester.pumpAndSettle();

      expect(liftedId, 's1');
      expect(liftedReason, 'Appeal granted by the dean');
    });

    testWidgets('no lift button without permission, or for a student in good standing',
        (tester) async {
      await _pumpRecords(tester, _student(standing: 'Dismissed'));
      expect(find.byKey(const Key('lift-restriction')), findsNothing);
      await _pumpRecords(tester, _student(),
          onLiftRestriction: (id, reason) async {});
      expect(find.byKey(const Key('lift-restriction')), findsNothing);
    });

    testWidgets('no disciplinary record section without any sanction',
        (tester) async {
      await _pumpRecords(tester, _student(),
          onFetchSanctions: (id) async => const []);
      expect(find.text('Disciplinary record'), findsNothing);
    });
  });
}
