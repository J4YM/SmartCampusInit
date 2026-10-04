import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Section schedules are stored as 24-hour "HH:mm"; the screen must show the
/// 12-hour clock.
void main() {
  testWidgets('the Generated Class Schedule card shows times as 12-hour AM/PM',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SectionScheduleCard(
            sectionOptions: const [(id: 'a', name: 'BSIT-1A')],
            onSectionSelected: (id) async => const [
              SectionScheduleRowModel(
                classSectionId: '1',
                subjectTitle: 'Math',
                professorName: 'X',
                day: 'M',
                startTime: '08:00',
                endTime: '09:30',
                room: '101',
              ),
              SectionScheduleRowModel(
                classSectionId: '2',
                subjectTitle: 'Physics',
                professorName: 'Y',
                day: 'T',
                startTime: '13:00',
                endTime: '15:30',
                room: '102',
              ),
              SectionScheduleRowModel(
                classSectionId: '3',
                subjectTitle: 'Night class',
                professorName: 'Z',
                day: 'W',
                startTime: '00:30',
                endTime: '12:00',
                room: '103',
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SectionPickerField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BSIT-1A').last);
    await tester.pumpAndSettle();

    expect(find.text('8:00 AM - 9:30 AM'), findsOneWidget);
    expect(find.text('1:00 PM - 3:30 PM'), findsOneWidget);
    expect(find.text('12:30 AM - 12:00 PM'), findsOneWidget);
    // None of the raw 24-hour text is left on screen.
    expect(find.text('08:00 - 09:30'), findsNothing);
    expect(find.text('13:00 - 15:30'), findsNothing);
    expect(find.textContaining('13:00'), findsNothing);
  });
}
