import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';

/// The Grades tab's Grade column is read-only: grades are plain text (two
/// decimals), with no number field, no up/down arrows and no Save Changes.
void main() {
  GradeRecordModel record(String id, String name, double grade) =>
      GradeRecordModel(
        id: id,
        studentName: name,
        studentId: '0200$id',
        gradeSection: 'BSIT 2A',
        subject: 'Programming 1',
        grade: grade,
        remark: GradeRemark.fromGrade(grade),
      );

  testWidgets('grades render as plain 2-decimal text, not editable fields',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GradesView(
            records: [
              record('1', 'Ana Cruz', 1.25),
              record('2', 'Ben Reyes', 5),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The values are shown...
    expect(find.byKey(const ValueKey('grade-value-1')), findsOneWidget);
    // (The stat cards above also show 1.25 / 5.00, so look inside the rows.)
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('grade-1')),
          matching: find.text('1.25')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('grade-2')),
          matching: find.text('5.00')),
      findsOneWidget,
    );

    // ...but nothing in the Grade column can be typed into or stepped.
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    final fieldsInRows = find.descendant(
      of: find.byKey(const ValueKey('grade-1')),
      matching: find.byType(TextField),
    );
    expect(fieldsInRows, findsNothing);

    // And there is no Save Changes: nothing on this tab can be edited.
    expect(find.text('Save Changes'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
