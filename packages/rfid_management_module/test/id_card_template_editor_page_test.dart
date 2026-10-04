// packages/rfid_management_module/test/id_card_template_editor_page_test.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';
import 'package:rfid_management_module/ui/shared_form_widgets.dart'
    show PillButton;

/// `find.text` matches both `Text` and `EditableText` widgets. Now that the
/// properties panel's Content field mirrors a selected staticText element's
/// text, a plain `find.text` call is ambiguous whenever that element is
/// selected (it also matches the panel's TextFormField). This restricts the
/// match to the canvas's own `Text` widget.
Finder _canvasText(String text) =>
    find.byWidgetPredicate((widget) => widget is Text && widget.data == text);

void main() {
  _snapGuideTests();
  _newShapeDefaultTests();

  testWidgets('adding a text element from the toolbox shows it on the canvas',
      (tester) async {
    List<IdCardTemplateElement>? savedFront;
    List<IdCardTemplateElement>? savedBack;

    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [],
        initialBackLayout: const [],
        onSave: (front, back, orientation, backgroundColor) async {
          savedFront = front;
          savedBack = back;
        },
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
        onRename: (newName) async {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Test Template'), findsOneWidget);
    expect(find.text('Static Text', skipOffstage: false), findsNothing);

    // Simulate a toolbox drag-and-drop onto the canvas.
    final textTool = find.text('Text');
    final canvas = find.byType(DragTarget<IdCardElementType>);
    await tester.drag(
        textTool, tester.getCenter(canvas) - tester.getCenter(textTool));
    await tester.pumpAndSettle();

    // The newly added element is auto-selected, so the properties panel's
    // Content field now also shows "Static Text" — use _canvasText to check
    // specifically for the canvas rendering (see _canvasText's doc comment).
    expect(_canvasText('Static Text'), findsOneWidget);

    // Save persists the current in-memory layout.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(savedFront, isNotNull);
    expect(savedFront, hasLength(1));
    expect(savedFront!.single.type, IdCardElementType.staticText);
    expect(savedBack, isNotNull);
    expect(savedBack, isEmpty);
  });

  testWidgets('deleting the selected element removes it from the canvas',
      (tester) async {
    const element = IdCardTemplateElement(
      id: 'existing-1',
      type: IdCardElementType.staticText,
      x: 10,
      y: 10,
      width: 80,
      height: 20,
      textContent: 'Existing Text',
    );

    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [element],
        initialBackLayout: const [],
        onSave: (front, back, orientation, backgroundColor) async {},
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
        onRename: (newName) async {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Existing Text'), findsOneWidget);

    await tester.tap(find.text('Existing Text'));
    await tester.pumpAndSettle();
    // The Position & Size fields now stack their labels above each field
    // (see _numberField), pushing Delete Element below the fold in this
    // test's default viewport — scroll it into view before tapping.
    final deleteButton = find.widgetWithText(PillButton, 'Delete Element');
    await tester.ensureVisible(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('Existing Text'), findsNothing);
  });

  testWidgets('undo restores the layout after adding an element',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [],
        initialBackLayout: const [],
        onSave: (front, back, orientation, backgroundColor) async {},
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
        onRename: (newName) async {},
      ),
    ));
    await tester.pumpAndSettle();

    final textTool = find.text('Text');
    final canvas = find.byType(DragTarget<IdCardElementType>);
    await tester.drag(
        textTool, tester.getCenter(canvas) - tester.getCenter(textTool));
    await tester.pumpAndSettle();
    expect(_canvasText('Static Text'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Static Text'), findsNothing);
  });

  testWidgets('copy then paste duplicates the selected element',
      (tester) async {
    const element = IdCardTemplateElement(
      id: 'existing-1',
      type: IdCardElementType.staticText,
      x: 10,
      y: 10,
      width: 80,
      height: 20,
      textContent: 'Existing Text',
    );

    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [element],
        initialBackLayout: const [],
        onSave: (front, back, orientation, backgroundColor) async {},
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
        onRename: (newName) async {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Existing Text'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(_canvasText('Existing Text'), findsNWidgets(2));
  });

  testWidgets('editing a static text element\'s content updates the canvas',
      (tester) async {
    const element = IdCardTemplateElement(
      id: 'existing-1',
      type: IdCardElementType.staticText,
      x: 10,
      y: 10,
      width: 80,
      height: 20,
      textContent: 'Original',
    );

    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [element],
        initialBackLayout: const [],
        onSave: (front, back, orientation, backgroundColor) async {},
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
        onRename: (newName) async {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();

    // The Content field is not the first TextFormField in the panel — the
    // X/Y/W/H position-and-size fields precede it — so target it by its key
    // rather than by position.
    await tester.enterText(
        find.byKey(const ValueKey('existing-1_content')), 'Updated');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(_canvasText('Updated'), findsOneWidget);
    expect(find.text('Original'), findsNothing);
  });

  testWidgets('tapping the header title renames the template inline',
      (tester) async {
    String? renamedTo;

    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [],
        initialBackLayout: const [],
        onSave: (front, back, orientation, backgroundColor) async {},
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
        onRename: (newName) async => renamedTo = newName,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Test Template'), findsOneWidget);

    await tester.tap(find.text('Test Template'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Renamed Template');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(renamedTo, 'Renamed Template');
    expect(find.text('Renamed Template'), findsOneWidget);
    expect(find.text('Test Template'), findsNothing);
  });

  testWidgets('pressing Escape while renaming cancels without calling onRename',
      (tester) async {
    var renameCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [],
        initialBackLayout: const [],
        onSave: (front, back, orientation, backgroundColor) async {},
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
        onRename: (newName) async => renameCalled = true,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test Template'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Should Not Save');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(renameCalled, isFalse);
    expect(find.text('Test Template'), findsOneWidget);
    expect(find.text('Should Not Save'), findsNothing);
  });

  group('selecting the card itself', () {
    const element = IdCardTemplateElement(
      id: 'existing-1',
      type: IdCardElementType.staticText,
      x: 10,
      y: 10,
      width: 80,
      height: 20,
      textContent: 'Existing Text',
    );

    Future<int?> pumpEditor(
      WidgetTester tester, {
      List<IdCardTemplateElement> front = const [],
      void Function(int backgroundColor)? onSaved,
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: IdCardTemplateEditorPage(
          templateName: 'Test Template',
          initialFrontLayout: front,
          initialBackLayout: const [],
          onSave: (f, b, orientation, backgroundColor) async =>
              onSaved?.call(backgroundColor),
          onUploadImage: (bytes, fileName) async => 'fake/path.png',
          onRename: (newName) async {},
        ),
      ));
      await tester.pumpAndSettle();
      return null;
    }

    // The editable card: the one tight-sized container casting a shadow. Its
    // outline is painted as a foreground border (so it never shifts content).
    final editableCard = find.byWidgetPredicate((w) =>
        w is Container &&
        (w.constraints?.hasTightWidth ?? false) &&
        w.decoration is BoxDecoration &&
        ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false));
    // The card has no border at all until it is clicked; then a 3px blue ring
    // is drawn just outside it (so it shows on a card of any color).
    final cardRing = find.byKey(const ValueKey('card-selection-ring'));
    bool hasAnyBorder(WidgetTester tester) {
      final card = tester.widget<Container>(editableCard);
      return card.foregroundDecoration != null ||
          (card.decoration as BoxDecoration).border != null ||
          cardRing.evaluate().isNotEmpty;
    }

    bool highlighted(WidgetTester tester) => cardRing.evaluate().isNotEmpty;
    // The "Background" option, with every color listed under it.
    final backgroundOptions = find.text('Background');
    const swatchNames = ['Black', 'White', 'Blue', 'Red', 'Green', 'Yellow'];

    Future<void> tapCard(WidgetTester tester) async {
      await tester
          .tapAt(tester.getCenter(find.byType(DragTarget<IdCardElementType>)));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'clicking the card highlights its border and lists every background '
        'color in the properties panel (and not in the header)',
        (tester) async {
      await pumpEditor(tester);

      // Nothing selected: a strong grey outline, no color options anywhere.
      expect(highlighted(tester), isFalse);
      expect(backgroundOptions, findsNothing);
      expect(find.text('Select an element to edit its properties.'),
          findsOneWidget);

      await tapCard(tester);

      expect(highlighted(tester), isTrue);
      expect(find.text('Select an element to edit its properties.'),
          findsNothing);
      expect(backgroundOptions, findsOneWidget);
      // Every color is already on screen — nothing to open — in the panel at
      // the right, not the header.
      for (final name in swatchNames) {
        final swatch = find.byTooltip(name);
        expect(swatch, findsOneWidget, reason: name);
        expect(tester.getTopLeft(swatch).dx,
            greaterThan(tester.getTopRight(find.byType(DragTarget<IdCardElementType>)).dx));
        expect(tester.getTopLeft(swatch).dy, greaterThan(80));
      }
      expect(find.byType(AlertDialog), findsNothing);
      // The "none" swatch makes no sense for a card background.
      expect(find.byTooltip('None'), findsNothing);
    });

    testWidgets('tapping a swatch sets the card color, marks it dirty and '
        'shows a check on it', (tester) async {
      int? saved;
      await pumpEditor(tester, onSaved: (c) => saved = c);
      await tapCard(tester);

      // White (the default) is the checked one.
      expect(
          find.descendant(
              of: find.byTooltip('White'), matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save').evaluate().isNotEmpty, isTrue);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
              .onPressed,
          isNull);

      await tester.tap(find.byTooltip('Red'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byTooltip('Red'), matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byTooltip('White'), matching: find.byIcon(Icons.check_rounded)),
          findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(saved, 0xFFCD4855);
    });

    testWidgets(
        'the card has no border until clicked; the white swatch keeps a strong one',
        (tester) async {
      await pumpEditor(tester);

      // The unselected card has no border at all.
      expect(hasAnyBorder(tester), isFalse);

      await tapCard(tester);
      expect(hasAnyBorder(tester), isTrue);
      // The white swatch carries a strong outline, so it shows on the white
      // panel.
      final white = tester.widget<Container>(find.descendant(
          of: find.byTooltip('White'), matching: find.byType(Container)).first);
      final border = (white.decoration as BoxDecoration).border as Border;
      expect(border.top.width, greaterThanOrEqualTo(1.5));
      expect(border.top.color.computeLuminance(), lessThan(0.4));
    });

    testWidgets(
        'selecting an element, or clicking the empty space, replaces the card '
        'selection', (tester) async {
      await pumpEditor(tester, front: const [element]);
      final canvas = find.byType(DragTarget<IdCardElementType>);

      await tapCard(tester);
      expect(highlighted(tester), isTrue);

      // Tap the element: it becomes the selection, the card is unhighlighted
      // and its color options go away.
      await tester.tap(_canvasText('Existing Text'));
      await tester.pumpAndSettle();
      expect(highlighted(tester), isFalse);
      expect(backgroundOptions, findsNothing);
      expect(find.text('Position & Size'), findsOneWidget);

      // The blank area around the card deselects everything.
      await tapCard(tester);
      if (!highlighted(tester)) {
        // (the tap landed on the element — pick the card by a corner)
        await tester.tapAt(tester.getTopLeft(editableCard) + const Offset(6, 6));
        await tester.pumpAndSettle();
      }
      expect(highlighted(tester), isTrue);
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(highlighted(tester), isFalse);
      expect(backgroundOptions, findsNothing);
      expect(find.text('Select an element to edit its properties.'),
          findsOneWidget);
    });
  });

  group('canvas zoom', () {
    Future<void> pumpEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: IdCardTemplateEditorPage(
          templateName: 'Test Template',
          initialFrontLayout: const [],
          initialBackLayout: const [],
          onSave: (f, b, orientation, backgroundColor) async {},
          onUploadImage: (bytes, fileName) async => 'fake/path.png',
          onRename: (newName) async {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    // The editable card is the one container in the canvas casting a shadow.
    final card = find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false) &&
        (w.constraints?.hasTightWidth ?? false));

    Future<void> wheel(WidgetTester tester, double dy) async {
      final canvas = find.byType(DragTarget<IdCardElementType>);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(tester.getCenter(canvas)));
      await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
      await tester.pumpAndSettle();
    }

    testWidgets('a slider along the bottom zooms the card in and out',
        (tester) async {
      await pumpEditor(tester);
      expect(find.text('100%'), findsOneWidget);
      final base = tester.getSize(card);

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);
      // The bar sits at the bottom of the screen.
      expect(tester.getBottomLeft(slider).dy, greaterThan(850));

      // Drag the slider to its far right: maximum zoom (300%).
      await tester.drag(slider, const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(find.text('300%'), findsOneWidget);
      expect(tester.getSize(card).width, closeTo(base.width * 3, 1));

      // ...and to the far left: minimum zoom (25%).
      await tester.drag(slider, const Offset(-1000, 0));
      await tester.pumpAndSettle();
      expect(find.text('25%'), findsOneWidget);
      expect(tester.getSize(card).width, closeTo(base.width / 4, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the +/- buttons step the zoom', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(find.text('110%'), findsOneWidget);
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pumpAndSettle();
      expect(find.text('90%'), findsOneWidget);
    });

    testWidgets('the percentage opens a dropdown of preset zoom levels',
        (tester) async {
      await pumpEditor(tester);
      final base = tester.getSize(card).width;

      await tester.tap(find.text('100%'));
      await tester.pumpAndSettle();
      for (final preset in [25, 50, 75, 125, 150, 200, 300]) {
        expect(find.text('$preset%'), findsOneWidget, reason: '$preset%');
      }
      expect(find.text('100%'), findsNWidgets(2)); // label + menu entry

      var current = 100;
      for (final preset in [300, 25, 150, 100]) {
        if (find.text('$current%').evaluate().length < 2) {
          await tester.tap(find.text('$current%'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('$preset%').last);
        await tester.pumpAndSettle();
        current = preset;
        expect(find.text('$preset%'), findsOneWidget, reason: 'label $preset%');
        expect(tester.getSize(card).width, closeTo(base * preset / 100, 1));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ctrl + mouse wheel zooms; a plain wheel does not',
        (tester) async {
      await pumpEditor(tester);
      final base = tester.getSize(card);

      await wheel(tester, -100); // no Ctrl
      expect(tester.getSize(card).width, closeTo(base.width, 0.01));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await wheel(tester, -100); // wheel up = zoom in
      expect(tester.getSize(card).width, greaterThan(base.width));
      final zoomedIn = tester.getSize(card).width;

      await wheel(tester, 100); // wheel down = zoom out
      await wheel(tester, 100);
      expect(tester.getSize(card).width, lessThan(zoomedIn));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      // Zoom is a view setting: it doesn't mark the template unsaved.
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
              .onPressed,
          isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a card larger than the canvas scrolls instead of clipping',
        (tester) async {
      await pumpEditor(tester);
      await tester.drag(find.byType(Slider), const Offset(500, 0));
      await tester.pumpAndSettle();

      final canvas = find.byType(DragTarget<IdCardElementType>);
      expect(tester.getSize(card).width * 1.0,
          greaterThan(0)); // card is laid out at full zoomed size
      final before = tester.getTopLeft(card);
      await tester.drag(canvas, const Offset(0, -100));
      await tester.pumpAndSettle();
      // Either axis moved (the card is taller than the viewport at 300%).
      expect(tester.getTopLeft(card), isNot(before));
      expect(tester.takeException(), isNull);
    });
  });

  group('resizing and text hugging', () {
    const rect = IdCardTemplateElement(
      id: 'rect-1',
      type: IdCardElementType.rectangle,
      x: 50,
      y: 40,
      width: 60,
      height: 40,
    );
    const text = IdCardTemplateElement(
      id: 'text-1',
      type: IdCardElementType.staticText,
      x: 20,
      y: 20,
      // Deliberately far larger than the text: the box must shrink to it.
      width: 150,
      height: 60,
      textContent: 'Hello Card',
      fontSize: 12,
    );

    List<IdCardTemplateElement>? savedFront;

    Future<void> pumpEditor(
        WidgetTester tester, List<IdCardTemplateElement> front) async {
      savedFront = null;
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        // A fresh key per pump, so repeated pumps in one test start a brand-new
        // editor instead of updating the previous one (which keeps its edits).
        key: UniqueKey(),
        home: IdCardTemplateEditorPage(
          templateName: 'Test Template',
          initialFrontLayout: front,
          initialBackLayout: const [],
          onSave: (f, b, orientation, backgroundColor) async => savedFront = f,
          onUploadImage: (bytes, fileName) async => 'fake/path.png',
          onRename: (newName) async {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<IdCardTemplateElement> saved(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      return savedFront!.single;
    }

    Finder handle(String name) => find.byKey(ValueKey('resize-$name'));

    final editableCard = find.byWidgetPredicate((w) =>
        w is Container &&
        (w.constraints?.hasTightWidth ?? false) &&
        w.decoration is BoxDecoration &&
        ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false));

    // The selected element's selection ring: a 2px blue border drawn just
    // OUTSIDE its box (so it never overlaps the content it hugs).
    final outline = find.byWidgetPredicate((w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        // Rectangular only: the round resize handles have a blue edge too.
        (w.decoration as BoxDecoration).shape == BoxShape.rectangle &&
        ((w.decoration as BoxDecoration).border is Border) &&
        ((w.decoration as BoxDecoration).border as Border).top.width == 2 &&
        ((w.decoration as BoxDecoration).border as Border).top.color ==
            const Color(0xFF345892));

    // Taps a point inside the card, in card points (zoom 2.7).
    Future<void> tapCardPoint(WidgetTester tester, double x, double y) async {
      await tester
          .tapAt(tester.getRect(editableCard).topLeft + Offset(x * 2.7, y * 2.7));
      await tester.pumpAndSettle();
    }

    testWidgets('a selected element has eight handles, none when unselected',
        (tester) async {
      await pumpEditor(tester, const [rect]);
      const names = ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'];
      for (final name in names) {
        expect(handle(name), findsNothing, reason: 'nothing selected');
      }
      await tapCardPoint(tester, 80, 60); // inside the rectangle
      for (final name in names) {
        expect(handle(name), findsOneWidget, reason: name);
      }
      // Corners sit on the corners, sides on the middle of each side.
      final box = tester.getRect(outline).deflate(2); // the ring sits 2px outside the box
      expect(tester.getCenter(handle('nw')), box.topLeft);
      expect(tester.getCenter(handle('se')), box.bottomRight);
      expect(tester.getCenter(handle('n')), box.topCenter);
      expect(tester.getCenter(handle('e')), box.centerRight);
      expect(tester.getCenter(handle('s')), box.bottomCenter);
      expect(tester.getCenter(handle('w')), box.centerLeft);
    });

    testWidgets('every handle moves its own edges and pins the opposite ones',
        (tester) async {
      // The rectangle starts at left 50, top 40, right 110, bottom 80.
      Future<({double l, double t, double r, double b})> dragHandle(
          String name, Offset by) async {
        await pumpEditor(tester, const [rect]);
        await tapCardPoint(tester, 80, 60);
        await tester.drag(handle(name), by);
        await tester.pumpAndSettle();
        final e = await saved(tester);
        return (l: e.x, t: e.y, r: e.x + e.width, b: e.y + e.height);
      }

      // Corners: two edges move, the other two stay.
      var g = await dragHandle('se', const Offset(60, 60));
      expect([g.l, g.t], [50, 40]);
      expect(g.r, greaterThan(110));
      expect(g.b, greaterThan(80));

      g = await dragHandle('nw', const Offset(-60, -60));
      expect([g.r, g.b], [110, 80]);
      expect(g.l, lessThan(50));
      expect(g.t, lessThan(40));

      g = await dragHandle('ne', const Offset(60, -60));
      expect([g.l, g.b], [50, 80]);
      expect(g.r, greaterThan(110));
      expect(g.t, lessThan(40));

      g = await dragHandle('sw', const Offset(-60, 60));
      expect([g.r, g.t], [110, 40]);
      expect(g.l, lessThan(50));
      expect(g.b, greaterThan(80));

      // Sides: one edge moves; the drag's other axis is ignored.
      g = await dragHandle('e', const Offset(60, 90));
      expect([g.l, g.t, g.b], [50, 40, 80]);
      expect(g.r, greaterThan(110));

      g = await dragHandle('s', const Offset(90, 60));
      expect([g.l, g.t, g.r], [50, 40, 110]);
      expect(g.b, greaterThan(80));

      g = await dragHandle('w', const Offset(-60, 90));
      expect([g.t, g.r, g.b], [40, 110, 80]);
      expect(g.l, lessThan(50));

      g = await dragHandle('n', const Offset(90, -60));
      expect([g.l, g.r, g.b], [50, 110, 80]);
      expect(g.t, lessThan(40));

      // Dragging a handle past the opposite edge stops at the minimum size
      // and leaves the opposite edge where it was.
      g = await dragHandle('w', const Offset(900, 0));
      expect(g.r - g.l, 8);
      expect(g.r, 110);
    });

    testWidgets('a text element hugs its text, and keeps hugging as it changes',
        (tester) async {
      await pumpEditor(tester, const [text]);
      final canvasText = _canvasText('Hello Card');
      await tester.tap(canvasText);
      await tester.pumpAndSettle();

      Size box() => tester.getRect(outline).deflate(2).size;
      Size glyphs() => tester.getSize(canvasText);
      // Loaded with a 150x60 box, but the outline is the text's own size.
      expect(box().width, closeTo(glyphs().width, 0.6));
      expect(box().height, closeTo(glyphs().height, 0.6));
      expect(box().width, lessThan(150 * 2.7));

      // Moving it: the outline stays glued to the text.
      final before = tester.getTopLeft(canvasText);
      await tester.drag(canvasText, const Offset(60, 30));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(canvasText), isNot(before));
      expect(tester.getRect(outline).deflate(2).topLeft.dx,
          closeTo(tester.getTopLeft(canvasText).dx, 0.6));
      expect(tester.getRect(outline).deflate(2).topLeft.dy,
          closeTo(tester.getTopLeft(canvasText).dy, 0.6));
      expect(box().width, closeTo(glyphs().width, 0.6));
      expect(box().height, closeTo(glyphs().height, 0.6));

      // Scaling it with a handle changes the font size, and the outline
      // follows the bigger text; the opposite (top-left) corner stays put.
      final widthBefore = box().width;
      final topLeftBefore = tester.getRect(outline).deflate(2).topLeft;
      await tester.drag(handle('se'), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(box().width, greaterThan(widthBefore));
      expect(box().width, closeTo(glyphs().width, 0.6));
      expect(box().height, closeTo(glyphs().height, 0.6));
      expect(tester.getRect(outline).deflate(2).topLeft.dx, closeTo(topLeftBefore.dx, 0.6));
      expect(tester.getRect(outline).deflate(2).topLeft.dy, closeTo(topLeftBefore.dy, 0.6));
      final e = await saved(tester);
      expect(e.fontSize, greaterThan(12));
    });

    group('Border Radius on Image and Rectangle', () {
      const image = IdCardTemplateElement(
        id: 'img-1',
        type: IdCardElementType.image,
        x: 20,
        y: 20,
        width: 60,
        height: 80,
        imagePath: 'fake/path.png',
      );
      const box = IdCardTemplateElement(
        id: 'box-1',
        type: IdCardElementType.rectangle,
        x: 20,
        y: 20,
        width: 60,
        height: 40,
        fillColor: 0xFF345892,
        strokeColor: 0x00000000,
      );

      // The element's corner radius as drawn on the canvas, in screen pixels:
      // a ClipRRect (picture) or a BoxDecoration (rectangle).
      double drawn(WidgetTester tester) {
        final clips = find.descendant(
            of: editableCard, matching: find.byType(ClipRRect));
        if (clips.evaluate().isNotEmpty) {
          return (tester.widget<ClipRRect>(clips).borderRadius as BorderRadius)
              .topLeft
              .x;
        }
        final decorated = find.descendant(
            of: editableCard,
            matching: find.byWidgetPredicate((w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color ==
                    const Color(0xFF345892)));
        final radius = (tester.widget<Container>(decorated).decoration
                as BoxDecoration)
            .borderRadius as BorderRadius?;
        return radius?.topLeft.x ?? 0;
      }

      Future<void> typeRadius(WidgetTester tester, String id, String v) async {
        await tester.enterText(find.byKey(ValueKey('${id}_Border Radius')), v);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }

      testWidgets('an Image can be rounded', (tester) async {
        await pumpEditor(tester, const [image]);
        await tapCardPoint(tester, 50, 60);
        expect(find.text('Border Radius'), findsOneWidget);
        expect(drawn(tester), 0);
        await typeRadius(tester, 'img-1', '10');
        expect(drawn(tester), closeTo(10 * 2.7, 0.01));
        expect((await saved(tester)).cornerRadius, 10);
      });

      testWidgets('a Rectangle can be rounded', (tester) async {
        await pumpEditor(tester, const [box]);
        await tapCardPoint(tester, 50, 40);
        expect(find.text('Border Radius'), findsOneWidget);
        expect(drawn(tester), 0);
        await typeRadius(tester, 'box-1', '8');
        expect(drawn(tester), closeTo(8 * 2.7, 0.01));
        // Held at a full pill: half the shorter (40 tall) side.
        await typeRadius(tester, 'box-1', '500');
        expect(drawn(tester), closeTo(20 * 2.7, 0.01));
        expect((await saved(tester)).cornerRadius, 20);
      });

      testWidgets('there is no separate RoundedRect tool', (tester) async {
        await pumpEditor(tester, const []);
        expect(find.text('Rectangle'), findsOneWidget);
        expect(find.text('RoundedRect'), findsNothing);
      });

      testWidgets('a template saved with a RoundedRect still opens',
          (tester) async {
        await pumpEditor(tester, const [
          IdCardTemplateElement(
            id: 'old-1',
            type: IdCardElementType.roundedRect,
            x: 20,
            y: 20,
            width: 60,
            height: 40,
            fillColor: 0xFF345892,
            strokeColor: 0x00000000,
            cornerRadius: 12,
          ),
        ]);
        await tapCardPoint(tester, 50, 40);
        expect(drawn(tester), closeTo(12 * 2.7, 0.01));
        expect(find.text('Border Radius'), findsOneWidget);
      });
    });

    group('Opacity and crop on pictures', () {
      const photo = IdCardTemplateElement(
        id: 'photo-1',
        type: IdCardElementType.idPicture,
        x: 20,
        y: 20,
        width: 60,
        height: 80,
      );
      final opacityField = find.byKey(const ValueKey('photo-1_Opacity (%)'));
      final zoomSlider =
          find.byKey(const ValueKey('photo-1_crop_zoom_slider'));

      double canvasOpacity(WidgetTester tester) {
        final o = find.descendant(of: editableCard, matching: find.byType(Opacity));
        return o.evaluate().isEmpty ? 1 : tester.widget<Opacity>(o).opacity;
      }

      Future<void> select(WidgetTester tester) async {
        await pumpEditor(tester, const [photo]);
        await tapCardPoint(tester, 50, 60);
      }

      testWidgets('Opacity is a field plus a slider that fades the picture',
          (tester) async {
        await select(tester);
        expect(find.text('Opacity (%)'), findsOneWidget);
        expect(opacityField, findsOneWidget);
        expect(canvasOpacity(tester), 1);

        await tester.enterText(opacityField, '40');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(canvasOpacity(tester), closeTo(0.4, 0.001));
        expect(tester.widget<Slider>(find.byKey(const ValueKey('photo-1_opacity_slider'))).value, 40);
        expect((await saved(tester)).opacity, closeTo(0.4, 0.001));
      });

      testWidgets('Crop turns on a zoom and a reset, Done turns them off',
          (tester) async {
        await select(tester);
        expect(find.text('Crop'), findsOneWidget);
        expect(zoomSlider, findsNothing);

        await tester.tap(find.text('Crop'));
        await tester.pumpAndSettle();
        expect(zoomSlider, findsOneWidget);
        expect(find.text('Reset Crop'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(zoomSlider, findsNothing);
      });

      testWidgets('while cropping, dragging slides the picture, not the frame',
          (tester) async {
        await select(tester);
        await tester.tap(find.text('Crop'));
        await tester.pumpAndSettle();

        // Zoom in first: at 100% there is little to slide through.
        await tester.ensureVisible(zoomSlider);
        await tester.drag(zoomSlider, const Offset(400, 0));
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(zoomSlider).value, greaterThan(100));

        // The selection handles sit on the frame, so they show whether it moved.
        final frameBefore = tester.getCenter(handle('nw'));
        final gesture = await tester.startGesture(
            tester.getRect(editableCard).topLeft + const Offset(50 * 2.7, 60 * 2.7));
        await gesture.moveBy(const Offset(30, 30));
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(tester.getCenter(handle('nw')), frameBefore,
            reason: 'the frame did not move');
        final e = await saved(tester);
        expect(e.x, 20);
        expect(e.y, 20);
        expect(e.cropZoom, greaterThan(1));
        expect(e.cropX, isNot(0), reason: 'the picture slid inside the frame');
      });

      testWidgets('Reset Crop puts the picture back; the crop is one undo',
          (tester) async {
        await select(tester);
        await tester.tap(find.text('Crop'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(zoomSlider);
        await tester.drag(zoomSlider, const Offset(400, 0));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Reset Crop'));
        await tester.tap(find.text('Reset Crop'));
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(zoomSlider).value, 100);
        final e = await saved(tester);
        expect(e.cropZoom, 1);
        expect(e.cropX, 0);
      });

      testWidgets('selecting something else ends cropping', (tester) async {
        await pumpEditor(tester, const [
          photo,
          IdCardTemplateElement(
            id: 'other',
            type: IdCardElementType.rectangle,
            x: 100,
            y: 20,
            width: 50,
            height: 30,
            fillColor: 0xFF345892,
            strokeColor: 0x00000000,
          ),
        ]);
        await tapCardPoint(tester, 50, 60);
        await tester.tap(find.text('Crop'));
        await tester.pumpAndSettle();
        expect(zoomSlider, findsOneWidget);
        await tapCardPoint(tester, 120, 30);
        await tapCardPoint(tester, 50, 60);
        expect(zoomSlider, findsNothing, reason: 'cropping did not stay on');
      });
    });

    group('dragging past the card edge', () {
      const box = IdCardTemplateElement(
        id: 'box-1',
        type: IdCardElementType.rectangle,
        x: 20,
        y: 40,
        width: 60,
        height: 40,
        fillColor: 0xFF345892,
        strokeColor: 0x00000000,
      );

      // Presses the box and drags it until its left edge is [leftPt] card
      // points from the card's left, then lets go.
      Future<void> dragLeftEdgeTo(WidgetTester tester, double leftPt) async {
        final cardLeft = tester.getRect(editableCard).left;
        final start = tester.getRect(editableCard).topLeft +
            const Offset((20 + 30) * 2.7, (40 + 20) * 2.7);
        final gesture = await tester.startGesture(start);
        await gesture.moveBy(const Offset(30, 30));
        await tester.pump();
        final nw = tester.getCenter(handle('nw')).dx;
        await gesture.moveBy(Offset(cardLeft + leftPt * 2.7 - nw, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      testWidgets('it snaps to the card edge first', (tester) async {
        await pumpEditor(tester, const [box]);
        await tapCardPoint(tester, 50, 60);
        await dragLeftEdgeTo(tester, 2); // within the 4pt snap range of 0
        expect((await saved(tester)).x, 0);
      });

      testWidgets('a firm pull takes it off the card', (tester) async {
        await pumpEditor(tester, const [box]);
        await tapCardPoint(tester, 50, 60);
        await dragLeftEdgeTo(tester, -25);
        final e = await saved(tester);
        expect(e.x, lessThan(-4), reason: 'past the snap, outside the card');
        expect(e.x, greaterThan(-60), reason: 'but still partly on the card');
      });

      testWidgets('it can never be dragged completely off the card',
          (tester) async {
        await pumpEditor(tester, const [box]);
        await tapCardPoint(tester, 50, 60);
        await dragLeftEdgeTo(tester, -500);
        final e = await saved(tester);
        // 8pt of it always stays on the card, so it can be grabbed again.
        expect(e.x + e.width, closeTo(8, 0.01));
      });

      testWidgets('the part hanging off the card is clipped away',
          (tester) async {
        await pumpEditor(tester, const [
          IdCardTemplateElement(
            id: 'box-1',
            type: IdCardElementType.rectangle,
            x: -20,
            y: 40,
            width: 60,
            height: 40,
            fillColor: 0xFF345892,
            strokeColor: 0x00000000,
          ),
        ]);
        final card = tester.getRect(editableCard);
        final shape = find.descendant(
            of: editableCard,
            matching: find.byWidgetPredicate((w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color ==
                    const Color(0xFF345892)));
        // The rectangle really does start left of the card...
        expect(tester.getRect(shape).left, lessThan(card.left));
        // ...inside a clip exactly the size of the card.
        final clip = find.ancestor(of: shape, matching: find.byType(ClipRect));
        expect(clip, findsWidgets);
        expect(
            clip.evaluate().any((e) =>
                tester.getRect(find.byWidget(e.widget)) == card),
            isTrue,
            reason: 'no clip the size of the card around the element');
      });

      testWidgets('the outline of a selected off-card element is not clipped',
          (tester) async {
        await pumpEditor(tester, const [
          IdCardTemplateElement(
            id: 'box-1',
            type: IdCardElementType.rectangle,
            x: -20,
            y: 40,
            width: 60,
            height: 40,
            fillColor: 0xFF345892,
            strokeColor: 0x00000000,
          ),
        ]);
        await tapCardPoint(tester, 10, 60); // the part still on the card
        final ring = tester.getRect(outline);
        expect(ring.left, lessThan(tester.getRect(editableCard).left),
            reason: 'the outline runs past the card edge');
        // And it is not inside the card-sized clip.
        expect(
            find
                .ancestor(of: outline, matching: find.byType(ClipRect))
                .evaluate()
                .where((e) =>
                    tester.getRect(find.byWidget(e.widget)) ==
                    tester.getRect(editableCard))
                .isEmpty,
            isTrue);
      });

      testWidgets('X and Y fields accept a position past the edge',
          (tester) async {
        await pumpEditor(tester, const [box]);
        await tapCardPoint(tester, 50, 60);
        await tester.enterText(find.byKey(const ValueKey('box-1_X')), '-30');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect((await saved(tester)).x, -30);
      });
    });

    testWidgets('Font Weight dropdown offers Regular and Bold only',
        (tester) async {
      await pumpEditor(tester, const [text]);
      final canvasText = _canvasText('Hello Card');
      await tester.tap(canvasText);
      await tester.pumpAndSettle();

      FontWeight? drawn() => tester.widget<Text>(canvasText).style?.fontWeight;
      expect(find.text('Font Weight'), findsOneWidget);
      expect(drawn(), FontWeight.w400);

      final dropdown = find.byType(DropdownButton<int>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('Regular'), findsWidgets);
      expect(find.text('Bold'), findsWidgets);
      // The weights the printed card can't show are not offered.
      for (final name in ['Medium', 'Semi Bold', 'Extra Bold', 'Black (Heavy)']) {
        expect(find.text(name), findsNothing, reason: name);
      }

      await tester.tap(find.text('Bold').last);
      await tester.pumpAndSettle();
      expect(drawn(), FontWeight.w700);
      // The selection box still hugs the text (the real font gets wider when
      // bold; the test font does not, so only the hugging is checked).
      expect(tester.getRect(outline).deflate(2).width,
          closeTo(tester.getSize(canvasText).width, 0.6));
      expect(find.text('Bold'), findsOneWidget); // the dropdown shows it

      final e = await saved(tester);
      expect(e.fontWeight, 700);
    });

    testWidgets('a template saved with a heavier weight shows as Bold',
        (tester) async {
      await pumpEditor(
          tester, [text.copyWith(fontWeight: 900)]);
      final canvasText = _canvasText('Hello Card');
      await tester.tap(canvasText);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(canvasText).style?.fontWeight, FontWeight.w700);
      expect(find.text('Bold'), findsOneWidget);
    });

    group('ID Picture border radius', () {
      // 60x80 card units, so the roundest it can get is 30.
      const photo = IdCardTemplateElement(
        id: 'photo-1',
        type: IdCardElementType.idPicture,
        x: 20,
        y: 20,
        width: 60,
        height: 80,
      );
      final radiusField = find.byKey(const ValueKey('photo-1_Border Radius'));
      final radiusSlider =
          find.byKey(const ValueKey('photo-1_border_radius_slider'));

      // The picture's corner radius as drawn on the canvas, in screen pixels.
      double drawn(WidgetTester tester) {
        final clip = tester.widget<ClipRRect>(find.descendant(
            of: editableCard, matching: find.byType(ClipRRect)));
        return (clip.borderRadius as BorderRadius).topLeft.x;
      }

      Future<void> select(WidgetTester tester) async {
        await pumpEditor(tester, const [photo]);
        await tapCardPoint(tester, 50, 60);
      }

      testWidgets('an ID Picture has it as a field plus a slider',
          (tester) async {
        await select(tester);
        expect(find.text('Border Radius'), findsOneWidget);
        expect(radiusField, findsOneWidget);
        expect(radiusSlider, findsOneWidget);
        expect(drawn(tester), 0);

        // An ellipse is already as round as it gets: no radius for it.
        await pumpEditor(tester, const [
          IdCardTemplateElement(
            id: 'oval',
            type: IdCardElementType.ellipse,
            x: 50,
            y: 40,
            width: 60,
            height: 40,
          ),
        ]);
        await tapCardPoint(tester, 80, 60);
        expect(find.text('Border Radius'), findsNothing);
      });

      testWidgets('typing a number rounds the picture and is saved',
          (tester) async {
        await select(tester);
        await tester.enterText(radiusField, '12');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(drawn(tester), closeTo(12 * 2.7, 0.01));
        expect(tester.widget<Slider>(radiusSlider).value, 12);
        expect((await saved(tester)).cornerRadius, 12);
      });

      testWidgets('a number past a full circle is held at one',
          (tester) async {
        await select(tester);
        await tester.enterText(radiusField, '999');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(drawn(tester), closeTo(30 * 2.7, 0.01));
        expect((await saved(tester)).cornerRadius, 30);
      });

      testWidgets('the slider sets it, and a whole drag is one undo step',
          (tester) async {
        await select(tester);
        final start = tester.getCenter(radiusSlider);
        final gesture = await tester.startGesture(start);
        await gesture.moveBy(const Offset(40, 0));
        await gesture.moveBy(const Offset(40, 0));
        await gesture.moveBy(const Offset(40, 0));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(drawn(tester), greaterThan(0));
        final radius = tester.widget<Slider>(radiusSlider).value;
        expect(radius, greaterThan(0));
        expect(radius, radius.roundToDouble()); // whole pixels

        // The number field follows the slider.
        expect(find.text(radius.toStringAsFixed(0)), findsWidgets);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(drawn(tester), 0, reason: 'one undo undoes the whole drag');
      });
    });

    testWidgets('ID Data elements get a Font Weight too', (tester) async {
      const idData = IdCardTemplateElement(
        id: 'data-1',
        type: IdCardElementType.idData,
        x: 20,
        y: 20,
        width: 100,
        height: 20,
        fieldKey: IdDataFieldKey.course,
        fontSize: 12,
        fontWeight: 700,
      );
      await pumpEditor(tester, const [idData]);
      await tapCardPoint(tester, 60, 30);
      expect(find.text('Font Weight'), findsOneWidget);
      expect(find.text('Bold'), findsOneWidget); // the saved weight is shown
    });

    testWidgets('editing the text content re-fits the box', (tester) async {
      await pumpEditor(tester, const [text]);
      await tester.tap(_canvasText('Hello Card'));
      await tester.pumpAndSettle();
      final before = tester.getRect(outline).deflate(2).size.width;

      // Targeted by key (see the existing "editing a static text" test).
      await tester.enterText(find.byKey(const ValueKey('text-1_content')),
          'Hello Card and a much longer line');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final grown = _canvasText('Hello Card and a much longer line');
      expect(grown, findsOneWidget);
      expect(tester.getRect(outline).deflate(2).size.width, greaterThan(before));
      expect(tester.getRect(outline).deflate(2).size.width,
          closeTo(tester.getSize(grown).width, 0.6));
    });
  });

  group('editing text in place', () {
    const text = IdCardTemplateElement(
      id: 'text-1',
      type: IdCardElementType.staticText,
      x: 20,
      y: 20,
      width: 60,
      height: 14,
      textContent: 'Hello',
      fontSize: 12,
    );
    const rect = IdCardTemplateElement(
      id: 'rect-1',
      type: IdCardElementType.rectangle,
      x: 50,
      y: 60,
      width: 60,
      height: 40,
    );

    List<IdCardTemplateElement>? savedFront;

    Future<void> pumpEditor(WidgetTester tester) async {
      savedFront = null;
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: IdCardTemplateEditorPage(
          templateName: 'Test Template',
          initialFrontLayout: const [text, rect],
          initialBackLayout: const [],
          onSave: (f, b, orientation, backgroundColor) async => savedFront = f,
          onUploadImage: (bytes, fileName) async => 'fake/path.png',
          onRename: (newName) async {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    final canvas = find.byType(DragTarget<IdCardElementType>);
    // The only text field on the canvas itself (the panel's are outside it).
    final inlineField =
        find.descendant(of: canvas, matching: find.byType(TextField));
    final selectionRing = find.byWidgetPredicate((w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        // Rectangular only: the round resize handles have a blue edge too.
        (w.decoration as BoxDecoration).shape == BoxShape.rectangle &&
        ((w.decoration as BoxDecoration).border is Border) &&
        ((w.decoration as BoxDecoration).border as Border).top.width == 2 &&
        ((w.decoration as BoxDecoration).border as Border).top.color ==
            const Color(0xFF345892));

    Future<void> doubleClick(WidgetTester tester, Finder target) async {
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<String> savedText(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      return savedFront!.firstWhere((e) => e.id == 'text-1').textContent!;
    }

    testWidgets('a single click only selects; a double click edits in place',
        (tester) async {
      await pumpEditor(tester);
      expect(inlineField, findsNothing);

      await tester.tap(_canvasText('Hello'));
      await tester.pumpAndSettle();
      expect(inlineField, findsNothing);
      expect(find.byKey(const ValueKey('resize-se')), findsOneWidget);

      await tester.tap(_canvasText('Hello'));
      await tester.pumpAndSettle();
      expect(inlineField, findsOneWidget);
      // Typing in place, so the resize handles get out of the way.
      expect(find.byKey(const ValueKey('resize-se')), findsNothing);
      // The field starts with the current text, all selected.
      final controller = tester.widget<TextField>(inlineField).controller!;
      expect(controller.text, 'Hello');
      expect(controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 5));
      expect(
          tester.widget<TextField>(inlineField).focusNode!.hasFocus, isTrue);
    });

    testWidgets(
        'editing is seamless: the text does not move or wrap, and a '
        'line break can never be typed', (tester) async {
      await pumpEditor(tester);
      final display = _canvasText('Hello');
      final shownAt = tester.getTopLeft(display);
      final shownSize = tester.getSize(display);

      await doubleClick(tester, display);
      final editable =
          find.descendant(of: inlineField, matching: find.byType(EditableText));
      // Same spot, same single line of the same height as the plain text.
      expect(tester.getTopLeft(editable).dx, closeTo(shownAt.dx, 0.1));
      expect(tester.getTopLeft(editable).dy, closeTo(shownAt.dy, 0.1));
      expect(tester.getSize(editable).height, closeTo(shownSize.height, 1));
      expect(tester.widget<EditableText>(editable).maxLines, 1);

      // Even a long entry stays on one line, the field never growing taller.
      await tester.enterText(inlineField, 'A fairly long line of static text');
      await tester.pumpAndSettle();
      expect(tester.getSize(editable).height, closeTo(shownSize.height, 1));

      // A line break in the input is dropped instead of starting a new line.
      await tester.enterText(inlineField, 'One\nTwo');
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextField>(inlineField).controller!.text, 'OneTwo');
      expect(tester.getSize(editable).height, closeTo(shownSize.height, 1));
    });

    testWidgets('typing replaces the text, the box keeps hugging, Enter commits',
        (tester) async {
      await pumpEditor(tester);
      await doubleClick(tester, _canvasText('Hello'));
      final ringBefore = tester.getRect(selectionRing);

      await tester.enterText(inlineField, 'Hello there, STIer');
      await tester.pumpAndSettle();
      // The selection box grew with the text as it was typed.
      final ringAfter = tester.getRect(selectionRing);
      expect(ringAfter.width, greaterThan(ringBefore.width));
      expect(ringAfter.left, closeTo(ringBefore.left, 0.6));

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(inlineField, findsNothing);
      expect(_canvasText('Hello there, STIer'), findsOneWidget);
      expect(find.byKey(const ValueKey('resize-se')), findsOneWidget);
      expect(await savedText(tester), 'Hello there, STIer');
    });

    testWidgets('the properties panel follows what is typed on the canvas',
        (tester) async {
      await pumpEditor(tester);
      await doubleClick(tester, _canvasText('Hello'));
      await tester.enterText(inlineField, 'Live');
      await tester.pumpAndSettle();
      expect(_panelText(tester, 'text-1_content'), 'Live');
    });

    testWidgets('Escape puts the original text back', (tester) async {
      await pumpEditor(tester);
      await doubleClick(tester, _canvasText('Hello'));
      await tester.enterText(inlineField, 'Oops');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(inlineField, findsNothing);
      expect(_canvasText('Hello'), findsOneWidget);
      expect(_canvasText('Oops'), findsNothing);
    });

    testWidgets('clicking away commits what was typed', (tester) async {
      await pumpEditor(tester);
      await doubleClick(tester, _canvasText('Hello'));
      await tester.enterText(inlineField, 'Kept');
      await tester.pumpAndSettle();

      // Click the empty canvas space above-left of the card.
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(6, 6));
      await tester.pumpAndSettle();

      expect(inlineField, findsNothing);
      expect(_canvasText('Kept'), findsOneWidget);
    });

    testWidgets('the whole editing session is one undo step', (tester) async {
      await pumpEditor(tester);
      await doubleClick(tester, _canvasText('Hello'));
      await tester.enterText(inlineField, 'First');
      await tester.enterText(inlineField, 'Second');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_canvasText('Second'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(_canvasText('Hello'), findsOneWidget);
    });

    testWidgets('double-clicking a non-text element does not start editing',
        (tester) async {
      await pumpEditor(tester);
      final card = tester.getRect(find.byWidgetPredicate((w) =>
          w is Container &&
          (w.constraints?.hasTightWidth ?? false) &&
          w.decoration is BoxDecoration &&
          ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false)));
      final point = card.topLeft + const Offset(80 * 2.7, 80 * 2.7);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(inlineField, findsNothing);
      expect(find.byKey(const ValueKey('resize-se')), findsOneWidget);
    });
  });

  group('properties panel stays live', () {
    const rect = IdCardTemplateElement(
      id: 'rect-1',
      type: IdCardElementType.rectangle,
      x: 50,
      y: 40,
      width: 60,
      height: 40,
    );
    const text = IdCardTemplateElement(
      id: 'text-1',
      type: IdCardElementType.staticText,
      x: 20,
      y: 20,
      width: 40,
      height: 14,
      textContent: 'Live',
      fontSize: 12,
    );

    Future<void> pumpEditor(
        WidgetTester tester, List<IdCardTemplateElement> front) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: IdCardTemplateEditorPage(
          templateName: 'Test Template',
          initialFrontLayout: front,
          initialBackLayout: const [],
          onSave: (f, b, orientation, backgroundColor) async {},
          onUploadImage: (bytes, fileName) async => 'fake/path.png',
          onRename: (newName) async {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    final editableCard = find.byWidgetPredicate((w) =>
        w is Container &&
        (w.constraints?.hasTightWidth ?? false) &&
        w.decoration is BoxDecoration &&
        ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false));

    Future<Offset> selectRect(WidgetTester tester) async {
      final inside =
          tester.getRect(editableCard).topLeft + const Offset(80 * 2.7, 60 * 2.7);
      await tester.tapAt(inside);
      await tester.pumpAndSettle();
      return inside;
    }

    double number(WidgetTester tester, String id, String label) =>
        double.parse(_panelText(tester, '${id}_$label'));

    testWidgets('X and Y follow the element while it is dragged',
        (tester) async {
      await pumpEditor(tester, const [rect]);
      final inside = await selectRect(tester);
      expect(number(tester, 'rect-1', 'X'), 50);
      expect(number(tester, 'rect-1', 'Y'), 40);

      // Hold the drag: the panel must already show the new position while
      // the mouse is still down, not only after it is released.
      final gesture = await tester.startGesture(inside);
      await gesture.moveBy(const Offset(60, 0)); // gets past the pan slop
      await tester.pump();
      await gesture.moveBy(const Offset(54, 27));
      await tester.pump();
      final midX = number(tester, 'rect-1', 'X');
      final midY = number(tester, 'rect-1', 'Y');
      expect(midX, greaterThan(50));
      expect(midY, greaterThan(40));
      await gesture.moveBy(const Offset(54, 27));
      await tester.pump();
      expect(number(tester, 'rect-1', 'X'), greaterThan(midX));
      expect(number(tester, 'rect-1', 'Y'), greaterThan(midY));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('W, H and X follow a handle while it is dragged',
        (tester) async {
      await pumpEditor(tester, const [rect]);
      await selectRect(tester);
      expect(number(tester, 'rect-1', 'W'), 60);
      expect(number(tester, 'rect-1', 'H'), 40);

      final se = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('resize-se'))));
      await se.moveBy(const Offset(60, 60));
      await tester.pump();
      await se.moveBy(const Offset(54, 54));
      await tester.pump();
      expect(number(tester, 'rect-1', 'W'), greaterThan(60));
      expect(number(tester, 'rect-1', 'H'), greaterThan(40));
      final w = number(tester, 'rect-1', 'W');
      await se.moveBy(const Offset(54, 54));
      await tester.pump();
      expect(number(tester, 'rect-1', 'W'), greaterThan(w));
      await se.up();
      await tester.pumpAndSettle();

      // A left-side handle moves X while it changes W.
      final west = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('resize-w'))));
      await west.moveBy(const Offset(-60, 0));
      await tester.pump();
      await west.moveBy(const Offset(-54, 0));
      await tester.pump();
      expect(number(tester, 'rect-1', 'X'), lessThan(50));
      await west.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Font Size, W and H follow a text element being scaled',
        (tester) async {
      await pumpEditor(tester, const [text]);
      await tester.tap(_canvasText('Live'));
      await tester.pumpAndSettle();
      expect(number(tester, 'text-1', 'Font Size'), 12);
      final w0 = number(tester, 'text-1', 'W');

      final se = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('resize-se'))));
      await se.moveBy(const Offset(60, 0));
      await tester.pump();
      await se.moveBy(const Offset(54, 0));
      await tester.pump();
      expect(number(tester, 'text-1', 'Font Size'), greaterThan(12));
      expect(number(tester, 'text-1', 'W'), greaterThan(w0));
      await se.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a half-typed number is dropped when the field loses focus',
        (tester) async {
      await pumpEditor(tester, const [rect]);
      await selectRect(tester);

      await tester.enterText(find.byKey(const ValueKey('rect-1_X')), '99');
      await tester.pump();
      expect(_panelText(tester, 'rect-1_X'), '99');
      // Focus moves to another field without Enter: the real value returns.
      await tester.enterText(find.byKey(const ValueKey('rect-1_Y')), '41');
      await tester.pumpAndSettle();
      expect(_panelText(tester, 'rect-1_X'), '50');
    });
  });

  group('deleting with the keyboard', () {
    const rect = IdCardTemplateElement(
      id: 'rect-1',
      type: IdCardElementType.rectangle,
      x: 50,
      y: 40,
      width: 60,
      height: 40,
    );
    const text = IdCardTemplateElement(
      id: 'text-1',
      type: IdCardElementType.staticText,
      x: 20,
      y: 10,
      width: 40,
      height: 14,
      textContent: 'Keep me',
      fontSize: 12,
    );

    List<IdCardTemplateElement>? savedFront;

    Future<void> pumpEditor(WidgetTester tester) async {
      savedFront = null;
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: IdCardTemplateEditorPage(
          templateName: 'Test Template',
          initialFrontLayout: const [rect, text],
          initialBackLayout: const [],
          onSave: (f, b, orientation, backgroundColor) async => savedFront = f,
          onUploadImage: (bytes, fileName) async => 'fake/path.png',
          onRename: (newName) async {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    final editableCard = find.byWidgetPredicate((w) =>
        w is Container &&
        (w.constraints?.hasTightWidth ?? false) &&
        w.decoration is BoxDecoration &&
        ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false));

    // A point inside the rectangle (card points 80,60 at zoom 2.7).
    Offset rectPoint(WidgetTester tester) =>
        tester.getRect(editableCard).topLeft + const Offset(80 * 2.7, 60 * 2.7);

    Future<void> clickRect(WidgetTester tester) async {
      await tester.tapAt(rectPoint(tester));
      await tester.pumpAndSettle();
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    Future<List<String>> remainingIds(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      return [for (final e in savedFront!) e.id];
    }

    testWidgets('Delete removes the selected element', (tester) async {
      await pumpEditor(tester);
      await clickRect(tester);
      await press(tester, LogicalKeyboardKey.delete);
      expect(await remainingIds(tester), ['text-1']);
    });

    testWidgets('Backspace removes it too', (tester) async {
      await pumpEditor(tester);
      await clickRect(tester);
      await press(tester, LogicalKeyboardKey.backspace);
      expect(await remainingIds(tester), ['text-1']);
    });

    testWidgets(
        'still works after a properties field had focus: clicking the canvas '
        'hands the keyboard back to it', (tester) async {
      await pumpEditor(tester);
      await clickRect(tester);

      // Focus a field in the properties panel...
      await tester.tap(find.byKey(const ValueKey('rect-1_X')));
      await tester.pumpAndSettle();
      // ...then click the element on the canvas again and press Delete.
      await clickRect(tester);
      await press(tester, LogicalKeyboardKey.delete);
      expect(await remainingIds(tester), ['text-1']);
    });

    testWidgets('works after dragging an element, with a panel field focused',
        (tester) async {
      await pumpEditor(tester);
      await clickRect(tester);
      await tester.tap(find.byKey(const ValueKey('rect-1_Y')));
      await tester.pumpAndSettle();

      await tester.dragFrom(rectPoint(tester), const Offset(90, 0)); // well past the pan slop
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.delete);
      expect(await remainingIds(tester), ['text-1']);
    });

    testWidgets('works after a resize handle was used', (tester) async {
      await pumpEditor(tester);
      await clickRect(tester);
      await tester.tap(find.byKey(const ValueKey('rect-1_W')));
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(const ValueKey('resize-se')), const Offset(30, 30));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.delete);
      expect(await remainingIds(tester), ['text-1']);
    });

    testWidgets('works after finishing an in-place text edit', (tester) async {
      await pumpEditor(tester);
      final label = _canvasText('Keep me');
      await tester.tap(label);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(label);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.delete);
      expect(await remainingIds(tester), ['rect-1']);
    });

    testWidgets(
        'but Delete/Backspace inside a text field only edit that field',
        (tester) async {
      await pumpEditor(tester);
      await clickRect(tester);

      await tester.tap(find.byKey(const ValueKey('rect-1_X')));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.delete);
      await press(tester, LogicalKeyboardKey.backspace);
      // The rectangle is still there and selected (nothing was deleted, and
      // nothing changed, so there is nothing to save).
      expect(find.byKey(const ValueKey('resize-se')), findsOneWidget);
      expect(_saveEnabled(tester), isFalse);
    });

    testWidgets('Delete with nothing selected does nothing', (tester) async {
      await pumpEditor(tester);
      await clickRect(tester);
      // Click the blank canvas to deselect, then press Delete.
      await tester.tapAt(
          tester.getTopLeft(find.byType(DragTarget<IdCardElementType>)) +
              const Offset(8, 8));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.delete);
      expect(_saveEnabled(tester), isFalse, reason: 'nothing was changed');
      expect(find.byKey(const ValueKey('resize-se')), findsNothing);
    });
  });

  group('Ctrl + wheel zoom works anywhere on the canvas', () {
    Future<void> pumpEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: IdCardTemplateEditorPage(
          templateName: 'Test Template',
          initialFrontLayout: const [],
          initialBackLayout: const [],
          onSave: (f, b, orientation, backgroundColor) async {},
          onUploadImage: (bytes, fileName) async => 'fake/path.png',
          onRename: (newName) async {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    final canvas = find.byType(DragTarget<IdCardElementType>);
    final card = find.byWidgetPredicate((w) =>
        w is Container &&
        (w.constraints?.hasTightWidth ?? false) &&
        w.decoration is BoxDecoration &&
        ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false));

    // A spot on the canvas well away from the card (the blank margin).
    Offset blankSpot(WidgetTester tester) =>
        tester.getTopLeft(canvas) + const Offset(20, 20);

    Future<void> wheelAt(WidgetTester tester, Offset at, double dy) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
      await tester.pumpAndSettle();
    }

    testWidgets('over the blank area around the card, not just over the card',
        (tester) async {
      await pumpEditor(tester);
      expect(tester.getRect(card).contains(blankSpot(tester)), isFalse);
      final base = tester.getSize(card).width;

      // A plain wheel there does not zoom.
      await wheelAt(tester, blankSpot(tester), -100);
      expect(tester.getSize(card).width, closeTo(base, 0.01));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await wheelAt(tester, blankSpot(tester), -100); // up = zoom in
      final zoomedIn = tester.getSize(card).width;
      expect(zoomedIn, greaterThan(base));
      await wheelAt(tester, blankSpot(tester), 100); // down = zoom out
      expect(tester.getSize(card).width, lessThan(zoomedIn));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Cmd key works too, and the zoom is clamped',
        (tester) async {
      await pumpEditor(tester);
      final base = tester.getSize(card).width;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      for (var i = 0; i < 40; i++) {
        await wheelAt(tester, blankSpot(tester), -100);
      }
      expect(tester.getSize(card).width, closeTo(base * 3, 1)); // 300% max
      for (var i = 0; i < 80; i++) {
        await wheelAt(tester, blankSpot(tester), 100);
      }
      expect(tester.getSize(card).width, closeTo(base / 4, 1)); // 25% min
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    });

    testWidgets('a bigger wheel turn zooms more than a small one',
        (tester) async {
      await pumpEditor(tester);
      final base = tester.getSize(card).width;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await wheelAt(tester, blankSpot(tester), -50);
      final small = tester.getSize(card).width - base;
      await wheelAt(tester, blankSpot(tester), 50); // back
      await wheelAt(tester, blankSpot(tester), -200);
      final big = tester.getSize(card).width - base;
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(small, greaterThan(0));
      expect(big, greaterThan(small * 2));
    });

    testWidgets(
        'a platform pinch/scale signal (Ctrl + wheel on web, a touchpad '
        'pinch) zooms too, without needing Ctrl held', (tester) async {
      await pumpEditor(tester);
      final base = tester.getSize(card).width;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(blankSpot(tester)));
      await tester.sendEventToBinding(PointerScaleEvent(
        position: blankSpot(tester),
        scale: 1.5,
      ));
      await tester.pumpAndSettle();
      expect(tester.getSize(card).width, closeTo(base * 1.5, 1));
    });

    testWidgets('a touchpad pan-zoom (pinch) gesture zooms',
        (tester) async {
      await pumpEditor(tester);
      final base = tester.getSize(card).width;
      final at = blankSpot(tester);
      final pointer = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pointer.panZoomStart(at));
      await tester.sendEventToBinding(pointer.panZoomUpdate(at, scale: 1.4));
      await tester.pumpAndSettle();
      expect(tester.getSize(card).width, closeTo(base * 1.4, 1));
      await tester.sendEventToBinding(pointer.panZoomEnd());
      await tester.pumpAndSettle();
    });
  });

  group('selection stays visible on a blue card', () {
    const text = IdCardTemplateElement(
      id: 'text-1',
      type: IdCardElementType.staticText,
      x: 20,
      y: 20,
      width: 40,
      height: 14,
      textContent: 'On blue',
      fontSize: 12,
    );
    const blue = 0xFF345892; // the same blue as the selection color

    Future<void> pumpEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: IdCardTemplateEditorPage(
          templateName: 'Test Template',
          initialFrontLayout: const [text],
          initialBackLayout: const [],
          initialBackgroundColor: blue,
          onSave: (f, b, orientation, backgroundColor) async {},
          onUploadImage: (bytes, fileName) async => 'fake/path.png',
          onRename: (newName) async {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    final card = find.byWidgetPredicate((w) =>
        w is Container &&
        (w.constraints?.hasTightWidth ?? false) &&
        w.decoration is BoxDecoration &&
        ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false));

    Finder ringOfColor(Color color) => find.byWidgetPredicate((w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.rectangle &&
        (w.decoration as BoxDecoration).border is Border &&
        ((w.decoration as BoxDecoration).border as Border).top.color == color);

    testWidgets('a selected element is ringed in blue AND a white halo',
        (tester) async {
      await pumpEditor(tester);
      expect(ringOfColor(Colors.white), findsNothing);

      await tester.tap(find.text('On blue').first);
      await tester.pumpAndSettle();

      final ring = tester.getRect(ringOfColor(const Color(0xFF345892)));
      final halo = tester.getRect(ringOfColor(Colors.white));
      // The white halo hugs the blue ring on the outside (2px each side), so
      // against a blue card the halo is what stands out.
      expect(halo, ring.inflate(2));
      // On a card the same blue as the ring, the ring alone would be invisible
      // — the halo is a different color from the card.
      expect(Colors.white, isNot(const Color(blue)));
    });

    testWidgets('the resize handles are white with a blue edge',
        (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('On blue').first);
      await tester.pumpAndSettle();

      final handle = find.descendant(
          of: find.byKey(const ValueKey('resize-se')),
          matching: find.byType(Container));
      final decoration =
          tester.widget<Container>(handle.first).decoration as BoxDecoration;
      // A blue-filled dot would vanish on this blue card.
      expect(decoration.color, Colors.white);
      expect((decoration.border as Border).top.color,
          const Color(0xFF345892));
    });

    testWidgets('a selected card is outlined outside itself, not inside it',
        (tester) async {
      await pumpEditor(tester);
      final cardRing = find.byKey(const ValueKey('card-selection-ring'));
      expect(cardRing, findsNothing);

      // Click the blank part of the (blue) card.
      final cardRect = tester.getRect(card);
      await tester.tapAt(cardRect.bottomRight - const Offset(30, 30));
      await tester.pumpAndSettle();

      expect(cardRing, findsOneWidget);
      // The ring surrounds the card by its own 3px width...
      expect(tester.getRect(cardRing), cardRect.inflate(3));
      // ...and the card itself carries no border that could vanish into its
      // blue fill.
      final container = tester.widget<Container>(card);
      expect(container.foregroundDecoration, isNull);
      expect((container.decoration as BoxDecoration).border, isNull);
    });
  });

  group('editing text in place stays visible on any card color', () {
    const text = IdCardTemplateElement(
      id: 'text-1',
      type: IdCardElementType.staticText,
      x: 20,
      y: 20,
      width: 40,
      height: 14,
      textContent: 'Static',
      fontSize: 12,
    );

    Future<void> startEditing(WidgetTester tester, int cardColor) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: IdCardTemplateEditorPage(
          templateName: 'Test Template',
          initialFrontLayout: const [text],
          initialBackLayout: const [],
          initialBackgroundColor: cardColor,
          onSave: (f, b, orientation, backgroundColor) async {},
          onUploadImage: (bytes, fileName) async => 'fake/path.png',
          onRename: (newName) async {},
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Static').first);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Static').first);
      await tester.pumpAndSettle();
    }

    final canvas = find.byType(DragTarget<IdCardElementType>);

    /// How far apart two colors read, by luminance (0 = indistinguishable).
    double contrast(Color a, Color b) =>
        (a.computeLuminance() - b.computeLuminance()).abs();

    for (final entry in {
      'blue (the same blue as the editor accent)': 0xFF345892,
      'black': 0xFF000000,
      'white': 0xFFFFFFFF,
      'yellow': 0xFFF5C518,
      'green': 0xFF137333,
    }.entries) {
      testWidgets('on a ${entry.key} card the selection, caret and editing '
          'tint all show', (tester) async {
        final card = Color(entry.value);
        await startEditing(tester, entry.value);
        expect(find.descendant(of: canvas, matching: find.byType(TextField)),
            findsOneWidget);

        final theme = tester.widget<TextSelectionTheme>(find.descendant(
            of: canvas, matching: find.byType(TextSelectionTheme)));
        final selection = theme.data.selectionColor!;
        final caret = theme.data.cursorColor!;

        // The highlight, painted over the card, is clearly a different color
        // from the bare card (it used to be the card's own blue).
        expect(contrast(Color.alphaBlend(selection, card), card),
            greaterThan(0.05),
            reason: 'selection $selection on $card');
        // The caret is not the card's color either.
        expect(contrast(caret, card), greaterThan(0.2),
            reason: 'caret $caret on $card');
        // The field itself uses that caret color.
        expect(tester.widget<TextField>(find.descendant(of: canvas,
                matching: find.byType(TextField))).cursorColor,
            caret);
      });
    }

    testWidgets('the selected text is highlighted, not just the box',
        (tester) async {
      await startEditing(tester, 0xFF345892);
      final controller = tester
          .widget<TextField>(
              find.descendant(of: canvas, matching: find.byType(TextField)))
          .controller!;
      // Everything starts selected, so the highlight (a different color from
      // the card, per the tests above) covers the whole word.
      expect(controller.selection,
          TextSelection(baseOffset: 0, extentOffset: controller.text.length));
    });
  });
}

/// What a properties-panel field (found by its key) currently shows.
String _panelText(WidgetTester tester, String key) => tester
    .widget<EditableText>(find.descendant(
        of: find.byKey(ValueKey(key)), matching: find.byType(EditableText)))
    .controller
    .text;

bool _saveEnabled(WidgetTester tester) => tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
        .onPressed !=
    null;

/// Dragging an element shows ONE snap guide per axis — the line it actually
/// snapped to — even when several alignment candidates are close together.
void _snapGuideTests() {
  group('snap guides while dragging', () {
    const mover = IdCardTemplateElement(
      id: 'mover',
      type: IdCardElementType.rectangle,
      x: 10,
      y: 100,
      width: 20,
      height: 20,
    );

    // The red 1px-wide guide lines the canvas draws while snapping.
    final verticalGuides = find.byWidgetPredicate((w) =>
        w is Container &&
        w.color == Colors.redAccent &&
        w.constraints?.maxWidth == 1);

    final editableCard = find.byWidgetPredicate((w) =>
        w is Container &&
        (w.constraints?.hasTightWidth ?? false) &&
        w.decoration is BoxDecoration &&
        ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false));

    Future<double> pumpEditor(
        WidgetTester tester, List<IdCardTemplateElement> front) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: IdCardTemplateEditorPage(
          templateName: 'Test Template',
          initialFrontLayout: front,
          initialBackLayout: const [],
          onSave: (f, b, orientation, backgroundColor) async {},
          onUploadImage: (bytes, fileName) async => 'fake/path.png',
          onRename: (newName) async {},
        ),
      ));
      await tester.pumpAndSettle();
      return tester.getSize(editableCard).width / 2.7; // card width in points
    }

    // Left edge of the selected element, in card points, read off its handle.
    double moverLeft(WidgetTester tester) =>
        (tester.getCenter(find.byKey(const ValueKey('resize-nw'))).dx -
            tester.getRect(editableCard).left) /
        2.7;

    // Presses [mover] and drags it until its left edge is [leftPt] card
    // points from the card's left, leaving the pointer down. The first move is
    // diagonal and well past the slop so the element's pan wins over the
    // canvas scroll view.
    Future<TestGesture> holdDragTo(WidgetTester tester, double leftPt) async {
      final start = tester.getRect(editableCard).topLeft +
          const Offset((10 + 10) * 2.7, (100 + 10) * 2.7);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(30, 30));
      await tester.pump();
      await gesture.moveBy(Offset((leftPt - moverLeft(tester)) * 2.7, 0));
      await tester.pump();
      return gesture;
    }

    // Drags [mover] to [leftPt], reports how many vertical guides show, lets go.
    Future<int> dragAndCountGuides(WidgetTester tester, double leftPt) async {
      final gesture = await holdDragTo(tester, leftPt);
      final count = verticalGuides.evaluate().length;
      await gesture.up();
      await tester.pumpAndSettle();
      return count;
    }

    testWidgets('two nearby candidates draw one guide, not two',
        (tester) async {
      final width = await pumpEditor(tester, const []);
      // A second element whose left edge sits 3pt right of the spot where
      // [mover] would be centered on the card: two candidates inside the 4pt
      // snap range.
      final centered = width / 2 - 10;
      final other = IdCardTemplateElement(
        id: 'other',
        type: IdCardElementType.rectangle,
        x: centered + 3,
        y: 20,
        width: 40,
        height: 20,
      );
      await pumpEditor(tester, [mover, other]);
      // Drag to 1pt right of centered: nearest candidate is the card center.
      final guides = await dragAndCountGuides(tester, centered + 1);
      expect(guides, 1);
    });

    testWidgets('lined up with two things on the same line draws it once',
        (tester) async {
      final width = await pumpEditor(tester, const []);
      // [other] is centered on the card too, so centering [mover] lines it up
      // with the card AND with [other] — the same line, drawn once.
      final other = IdCardTemplateElement(
        id: 'other',
        type: IdCardElementType.rectangle,
        x: width / 2 - 20,
        y: 20,
        width: 40,
        height: 20,
      );
      await pumpEditor(tester, [mover, other]);
      final guides = await dragAndCountGuides(tester, width / 2 - 10);
      expect(guides, 1);
    });

    testWidgets('the guide is drawn at the edge that lines up',
        (tester) async {
      final width = await pumpEditor(tester, const []);
      // [other]'s left edge at 100: dragging [mover]'s left edge there should
      // draw the guide at x = 100pt, not at [mover]'s center.
      final other = IdCardTemplateElement(
        id: 'other',
        type: IdCardElementType.rectangle,
        x: width > 120 ? 100 : 60,
        y: 20,
        width: 30,
        height: 20,
      );
      await pumpEditor(tester, [mover, other]);
      final target = other.x;
      final cardLeft = tester.getRect(editableCard).left;
      final gesture = await holdDragTo(tester, target + 1);
      final line = tester.getTopLeft(verticalGuides).dx - cardLeft;
      expect(line, closeTo(target * 2.7, 0.6));
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}

/// A newly added shape starts with no border (so it is just a filled shape),
/// and a visible fill so it doesn't disappear; a line, which IS its stroke,
/// keeps a visible one.
void _newShapeDefaultTests() {
  group('new element defaults', () {
    Future<IdCardTemplateElement> dropTool(
        WidgetTester tester, String tool) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<IdCardTemplateElement>? savedFront;
      await tester.pumpWidget(MaterialApp(
        home: IdCardTemplateEditorPage(
          templateName: 'Test Template',
          initialFrontLayout: const [],
          initialBackLayout: const [],
          onSave: (f, b, orientation, backgroundColor) async => savedFront = f,
          onUploadImage: (bytes, fileName) async => 'fake/path.png',
          onRename: (newName) async {},
        ),
      ));
      await tester.pumpAndSettle();
      final toolFinder = find.text(tool);
      final canvas = find.byType(DragTarget<IdCardElementType>);
      await tester.drag(
          toolFinder, tester.getCenter(canvas) - tester.getCenter(toolFinder));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      return savedFront!.single;
    }

    for (final tool in ['Rectangle', 'Ellipse']) {
      testWidgets('$tool: no border, solid fill', (tester) async {
        final e = await dropTool(tester, tool);
        expect(e.strokeColor, 0x00000000, reason: 'border color is None');
        expect(e.fillColor! >> 24, 0xFF, reason: 'fill is visible');
      });
    }

    testWidgets('Line keeps a visible stroke', (tester) async {
      final e = await dropTool(tester, 'Line');
      expect(e.strokeColor! >> 24, 0xFF);
    });
  });
}
