import 'package:dashboard_layout/dashboard_layout.dart' show AppPopup;
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

      // The dialog's own fields (the tab has a search field of its own).
      final fields = find.descendant(
          of: find.byType(AppPopup), matching: find.byType(TextField));
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

    CurriculumEntryModel course(
      String id,
      String program,
      int year,
      int term,
      String code, {
      String? prereq,
      num units = 3,
    }) =>
        CurriculumEntryModel(
          id: id,
          subjectId: 's$id',
          program: program,
          yearLevel: year,
          term: term,
          code: code,
          title: 'Title $code',
          units: units,
          prerequisites: prereq,
        );

    final many = [
      course('1', 'BS IT', 2, 1, 'IT201'),
      course('2', 'BS IT', 1, 2, 'IT102', prereq: 'IT101'),
      course('3', 'BS IT', 1, 1, 'IT101', units: 1.5),
      course('4', 'BS IT', 0, 0, 'ELEC1'),
      course('5', 'BS IT', 1, 1, 'IT100'),
      course('6', 'BS Business', 1, 1, 'BA101'),
    ];

    testWidgets('one program at a time, terms in order with electives last',
        (tester) async {
      await pump(tester, entries: many);

      // BS Business sorts first, so it opens first.
      expect(find.text('Title BA101'), findsOneWidget);
      expect(find.text('Title IT101'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('curriculum-program-BS IT')));
      await tester.pumpAndSettle();
      expect(find.text('Title BA101'), findsNothing);

      double top(String group) =>
          tester.getTopLeft(find.byKey(ValueKey('curriculum-group-$group'))).dy;
      expect(top('1-1'), lessThan(top('1-2')));
      expect(top('1-2'), lessThan(top('2-1')));
      expect(top('2-1'), lessThan(top('0-0')));
      expect(find.text('Electives'), findsOneWidget);

      // Units add up per term: IT101 (1.5) + IT100 (3) = 4.5, shown without
      // a trailing ".0" where whole.
      expect(find.textContaining('2 courses | 4.5 units'), findsOneWidget);
      expect(find.textContaining('1 course | 3 units'), findsNWidgets(3));
    });

    testWidgets('search narrows by code, title or prerequisite',
        (tester) async {
      await pump(tester, entries: many);
      await tester.tap(find.byKey(const ValueKey('curriculum-program-BS IT')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('curriculum-search')), 'IT101');
      await tester.pumpAndSettle();
      // IT101 itself, and IT102, which lists it as a prerequisite.
      expect(find.text('Title IT101'), findsOneWidget);
      expect(find.text('Title IT102'), findsOneWidget);
      expect(find.text('Title IT201'), findsNothing);

      await tester.enterText(find.byKey(const Key('curriculum-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No courses match your search'), findsOneWidget);
    });

    testWidgets('Add to this term pre-selects that program, year and term',
        (tester) async {
      CurriculumCourseForm? saved;
      await pump(tester, entries: many, onSave: (_, form) async => saved = form);
      await tester.tap(find.byKey(const ValueKey('curriculum-program-BS IT')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('curriculum-add-2-1')));
      await tester.pumpAndSettle();
      final fields = find.descendant(
          of: find.byType(AppPopup), matching: find.byType(TextField));
      await tester.enterText(fields.at(1), 'IT202');
      await tester.enterText(fields.at(3), 'Networking');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Course'));
      await tester.pumpAndSettle();

      expect(saved!.program, 'BS IT');
      expect([saved!.yearLevel, saved!.term], [2, 1]);
    });

    testWidgets('each term card folds up to its header and opens again',
        (tester) async {
      await pump(tester, entries: many, onSave: (_, __) async {});
      await tester.tap(find.byKey(const ValueKey('curriculum-program-BS IT')));
      await tester.pumpAndSettle();
      expect(find.text('Title IT101'), findsOneWidget);
      expect(find.text('Title IT201'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('curriculum-toggle-1-1')));
      await tester.pumpAndSettle();
      // 1st Year · 1st Term is folded: its courses and Add button are gone,
      // its title and summary stay, and other terms are untouched.
      expect(find.text('Title IT101'), findsNothing);
      expect(find.byKey(const Key('curriculum-add-1-1')), findsNothing);
      expect(find.text('1st Year · 1st Term'), findsOneWidget);
      expect(find.textContaining('2 courses | 4.5 units'), findsOneWidget);
      expect(find.text('Title IT201'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('curriculum-toggle-1-1')));
      await tester.pumpAndSettle();
      expect(find.text('Title IT101'), findsOneWidget);
    });

    testWidgets('folding and opening animate the card\'s height',
        (tester) async {
      await pump(tester, entries: many);
      await tester.tap(find.byKey(const ValueKey('curriculum-program-BS IT')));
      await tester.pumpAndSettle();

      final card = find.byKey(const ValueKey('curriculum-group-1-1'));
      final open = tester.getSize(card).height;

      await tester.tap(find.byKey(const ValueKey('curriculum-toggle-1-1')));
      await tester.pump(); // start
      await tester.pump(const Duration(milliseconds: 130)); // about halfway
      final midFold = tester.getSize(card).height;
      expect(find.text('Title IT101'), findsOneWidget); // still on its way out
      await tester.pumpAndSettle();
      final folded = tester.getSize(card).height;
      expect(find.text('Title IT101'), findsNothing);
      expect(folded, lessThan(midFold));
      expect(midFold, lessThan(open));

      await tester.tap(find.byKey(const ValueKey('curriculum-toggle-1-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      final midOpen = tester.getSize(card).height;
      expect(midOpen, greaterThan(folded));
      expect(midOpen, lessThan(open));
      await tester.pumpAndSettle();
      expect(tester.getSize(card).height, open);
    });

    testWidgets('Collapse all / Expand all, and a search opens folded cards',
        (tester) async {
      await pump(tester, entries: many);
      await tester.tap(find.byKey(const ValueKey('curriculum-program-BS IT')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('curriculum-toggle-all')));
      await tester.pumpAndSettle();
      expect(find.text('Title IT101'), findsNothing);
      expect(find.text('Title IT201'), findsNothing);
      expect(find.text('Expand all'), findsOneWidget);

      // Searching shows the matches even though their card is folded.
      await tester.enterText(find.byKey(const Key('curriculum-search')), 'IT201');
      await tester.pumpAndSettle();
      expect(find.text('Title IT201'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('curriculum-search')), '');
      await tester.pumpAndSettle();
      expect(find.text('Title IT201'), findsNothing);

      await tester.tap(find.byKey(const Key('curriculum-toggle-all')));
      await tester.pumpAndSettle();
      expect(find.text('Title IT101'), findsOneWidget);
      expect(find.text('Title IT201'), findsOneWidget);
      expect(find.text('Collapse all'), findsOneWidget);
    });

    testWidgets('empty curriculum says to upload one', (tester) async {
      await pump(tester, entries: const []);
      expect(find.text('No curriculum on file yet. Upload one above.'),
          findsOneWidget);
    });

    for (final size in [
      const Size(1400, 1800),
      const Size(800, 1800),
      const Size(360, 1800),
    ]) {
      testWidgets('lays out without overflow at ${size.width.toInt()}px',
          (tester) async {
        await pump(tester,
            entries: many, onSave: (_, __) async {}, onDelete: (_) async {});
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('curriculum-program-BS IT')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

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
