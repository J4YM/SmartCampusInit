import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// `BentoFormDialog`'s Cancel/confirm buttons are bare Text-in-InkWell, not
/// TextButton/FilledButton/OutlinedButton — and the row's own "Assign"
/// TextButton stays in the tree (just visually covered) once the dialog is
/// open, so a bare `find.text('Assign')` would match both. Scoping to
/// descendants of the dialog itself disambiguates.
Finder _dialogButton(String label) => find.descendant(
      of: find.byType(BentoFormDialog),
      matching: find.text(label),
    );

RfidRequestRowModel _pendingRequest({
  String id = 'req-1',
  String studentId = 'student-1',
}) =>
    RfidRequestRowModel(
      id: id,
      studentId: studentId,
      studentName: 'Juan Dela Cruz',
      studentNumber: '2023-0001',
      section: 'BSIT 3A',
      requestedByLabel: 'Registrar Staff',
      requestedAtLabel: '1/1/2026',
      isFulfilled: false,
    );

RfidRequestRowModel _fulfilledRequest() => const RfidRequestRowModel(
      id: 'req-2',
      studentId: 'student-2',
      studentName: 'Maria Santos',
      studentNumber: '2023-0002',
      section: 'BSIT 3B',
      requestedByLabel: 'Registrar Staff',
      requestedAtLabel: '1/1/2026',
      isFulfilled: true,
    );

void main() {
  testWidgets('a pending request shows an Assign button; a fulfilled one does not',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RfidRequestsTab(
        requests: [_pendingRequest(), _fulfilledRequest()],
        onAssign: (_, __, ___) async {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Assign'), findsOneWidget);
    expect(find.text('Fulfilled'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('tapping Assign, entering a UID, and confirming calls onAssign',
      (tester) async {
    String? assignedRequestId;
    String? assignedStudentId;
    String? assignedUid;

    await tester.pumpWidget(MaterialApp(
      home: RfidRequestsTab(
        requests: [_pendingRequest()],
        onAssign: (requestId, studentId, uid) async {
          assignedRequestId = requestId;
          assignedStudentId = studentId;
          assignedUid = uid;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Assign'));
    await tester.pumpAndSettle();

    expect(find.text('Assign RFID Card'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'A4:F2:88:1C');
    await tester.tap(_dialogButton('Assign'));
    await tester.pumpAndSettle();

    expect(assignedRequestId, 'req-1');
    expect(assignedStudentId, 'student-1');
    expect(assignedUid, 'A4:F2:88:1C');
    expect(find.text('Assign RFID Card'), findsNothing);
  });

  testWidgets('cancelling the dialog does not call onAssign', (tester) async {
    var called = false;
    await tester.pumpWidget(MaterialApp(
      home: RfidRequestsTab(
        requests: [_pendingRequest()],
        onAssign: (_, __, ___) async => called = true,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Assign'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('Assign RFID Card'), findsNothing);
  });

  testWidgets('a failed assignment shows an error and keeps the row pending',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      // A real Scaffold ancestor is needed here (unlike the other tests
      // above) because this is the one path that reaches
      // ScaffoldMessenger.showSnackBar.
      home: Scaffold(
        body: RfidRequestsTab(
          requests: [_pendingRequest()],
          onAssign: (_, __, ___) async => throw Exception('network error'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Assign'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A4:F2:88:1C');
    await tester.tap(_dialogButton('Assign'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not assign'), findsOneWidget);
  });
}
