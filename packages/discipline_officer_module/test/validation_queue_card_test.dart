import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DisciplineCaseModel makeCase({
    required String id,
    String studentName = 'Jane Doe',
    String? admissionSlipId,
  }) {
    return DisciplineCaseModel(
      id: id,
      studentName: studentName,
      studentNumber: '2024-0001',
      programGradeSection: 'BSIT 3-A',
      violationType: 'Improper uniform',
      submittedBy: 'System',
      submitterRole: '',
      incidentDateTime: DateTime(2026, 1, 1),
      description: '',
      admissionSlipId: admissionSlipId,
    );
  }

  Widget buildCard({
    required List<DisciplineCaseModel> cases,
    required ValueChanged<DisciplineCaseModel> onSelect,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: ValidationQueueCard(
            cases: cases,
            selectedCaseId: null,
            onSelect: onSelect,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'violations sharing an admission slip collapse into one ticket row',
    (tester) async {
      final cases = [
        makeCase(id: 'v1', studentName: 'Jane Doe', admissionSlipId: 'slip-A'),
        makeCase(id: 'v2', studentName: 'Jane Doe', admissionSlipId: 'slip-A'),
        makeCase(id: 'v3', studentName: 'John Roe'),
      ];

      await tester.pumpWidget(buildCard(cases: cases, onSelect: (_) {}));

      // One row for the 2-violation ticket, one row for the standalone case.
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('John Roe'), findsOneWidget);
      expect(find.textContaining('2 violations'), findsOneWidget);
    },
  );

  testWidgets(
    'expanding a ticket reveals each violation as its own selectable row',
    (tester) async {
      DisciplineCaseModel? selected;
      final cases = [
        makeCase(id: 'v1', admissionSlipId: 'slip-A'),
        makeCase(id: 'v2', admissionSlipId: 'slip-A'),
      ];

      await tester.pumpWidget(
        buildCard(cases: cases, onSelect: (c) => selected = c),
      );

      // Sub-rows aren't shown until expanded.
      expect(find.byKey(const ValueKey('queue-row-v1')), findsNothing);
      expect(find.byKey(const ValueKey('queue-row-v2')), findsNothing);

      await tester.tap(find.textContaining('2 violations'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('queue-row-v1')), findsOneWidget);
      expect(find.byKey(const ValueKey('queue-row-v2')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('queue-row-v2')));
      await tester.pumpAndSettle();

      expect(selected?.id, 'v2');
    },
  );

  testWidgets(
    'a case with no admission slip renders as its own single row, tap selects it directly',
    (tester) async {
      DisciplineCaseModel? selected;
      final cases = [makeCase(id: 'v1', studentName: 'Solo Student')];

      await tester.pumpWidget(
        buildCard(cases: cases, onSelect: (c) => selected = c),
      );

      expect(find.byKey(const ValueKey('queue-row-v1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('queue-row-v1')));
      await tester.pumpAndSettle();

      expect(selected?.id, 'v1');
    },
  );
}
