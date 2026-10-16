import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';

void main() {
  group('CurriculumView', () {
    const entry = CurriculumEntryModel(
      id: 'e1',
      subjectId: 's1',
      program: 'BS Information Technology',
      yearLevel: 1,
      term: 1,
      code: 'CITE1003',
      title: 'Computer Programming 1',
      units: 3,
    );

    Future<void> pump(
      WidgetTester tester, {
      Future<void> Function(CurriculumEntryModel?, CurriculumCourseForm)? onSave,
      Future<void> Function(CurriculumEntryModel)? onDelete,
      List<CurriculumEntryModel> entries = const [entry],
    }) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CurriculumView(
              entries: entries,
              onSaveCourse: onSave,
              onDeleteCourse: onDelete,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('has no editing controls when nothing can be saved (demo)',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('BS Information Technology'));
      await tester.pumpAndSettle();
      expect(find.text('Add Course'), findsNothing);
      expect(find.byTooltip('Edit course'), findsNothing);
      expect(find.byTooltip('Remove course'), findsNothing);
    });

    testWidgets('Edit opens a prefilled dialog and saves the changes',
        (tester) async {
      CurriculumEntryModel? savedFor;
      CurriculumCourseForm? saved;
      await pump(tester, onSave: (existing, form) async {
        savedFor = existing;
        saved = form;
      }, onDelete: (_) async {});

      await tester.tap(find.text('BS Information Technology'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit course'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Course'), findsOneWidget);
      expect(find.text('CITE1003'), findsWidgets);

      await tester.enterText(
          find.widgetWithText(TextField, 'Computer Programming 1'),
          'Programming Fundamentals');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(savedFor, same(entry));
      expect(saved!.title, 'Programming Fundamentals');
      expect(saved!.code, 'CITE1003');
      expect([saved!.yearLevel, saved!.term, saved!.units], [1, 1, 3]);
      expect(find.text('Edit Course'), findsNothing); // closed
    });

    testWidgets('a save error is shown and the dialog stays open',
        (tester) async {
      await pump(tester,
          onSave: (_, __) async => throw Exception('code already used'));

      await tester.tap(find.text('BS Information Technology'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit course'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.textContaining('code already used'), findsOneWidget);
      expect(find.text('Edit Course'), findsOneWidget); // still open
    });

    testWidgets('an empty form is refused before saving', (tester) async {
      var saves = 0;
      await pump(tester, onSave: (_, __) async => saves++);

      await tester.tap(find.text('Add Course').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add Course'));
      await tester.pumpAndSettle();

      expect(find.text('Program, Code and Title are required.'), findsOneWidget);
      expect(saves, 0);
    });

    testWidgets('Add Course from a program pre-selects that program',
        (tester) async {
      CurriculumCourseForm? saved;
      CurriculumEntryModel? savedFor = entry;
      await pump(tester, onSave: (existing, form) async {
        savedFor = existing;
        saved = form;
      });

      await tester.tap(find.text('BS Information Technology'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add course to BS Information Technology'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      // Program (prefilled), Code, Units, Title, Prerequisites.
      await tester.enterText(fields.at(1), 'cite 2000');
      await tester.enterText(fields.at(3), 'Data Structures');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Course'));
      await tester.pumpAndSettle();

      expect(savedFor, isNull);
      expect(saved!.program, 'BS Information Technology');
      expect(saved!.code, 'cite 2000');
      expect(saved!.title, 'Data Structures');
      expect(saved!.units, 3);
    });

    testWidgets('Remove asks first, then deletes', (tester) async {
      final deleted = <String>[];
      await pump(tester,
          onSave: (_, __) async {}, onDelete: (e) async => deleted.add(e.code));

      await tester.tap(find.text('BS Information Technology'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove course'));
      await tester.pumpAndSettle();
      expect(find.text('Remove course?'), findsOneWidget);
      expect(deleted, isEmpty);

      await tester.tap(find.byKey(const Key('archive-delete-confirm')));
      await tester.pumpAndSettle();
      expect(deleted, ['CITE1003']);
    });
  });
}
