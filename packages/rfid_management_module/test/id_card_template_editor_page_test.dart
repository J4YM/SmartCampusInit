// packages/rfid_management_module/test/id_card_template_editor_page_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// `find.text` matches both `Text` and `EditableText` widgets. Now that the
/// properties panel's Content field mirrors a selected staticText element's
/// text, a plain `find.text` call is ambiguous whenever that element is
/// selected (it also matches the panel's TextFormField). This restricts the
/// match to the canvas's own `Text` widget.
Finder _canvasText(String text) =>
    find.byWidgetPredicate((widget) => widget is Text && widget.data == text);

void main() {
  testWidgets('adding a text element from the toolbox shows it on the canvas',
      (tester) async {
    List<IdCardTemplateElement>? savedFront;
    List<IdCardTemplateElement>? savedBack;

    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [],
        initialBackLayout: const [],
        onSave: (front, back) async {
          savedFront = front;
          savedBack = back;
        },
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Editing Test Template'), findsOneWidget);
    expect(find.text('Static Text', skipOffstage: false), findsNothing);

    // Simulate a toolbox drag-and-drop onto the canvas.
    final textTool = find.text('Text');
    final canvas = find.byType(DragTarget<IdCardElementType>);
    await tester.drag(textTool, tester.getCenter(canvas) - tester.getCenter(textTool));
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
        onSave: (front, back) async {},
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Existing Text'), findsOneWidget);

    await tester.tap(find.text('Existing Text'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete Element'));
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
        onSave: (front, back) async {},
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
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
        onSave: (front, back) async {},
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
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
        onSave: (front, back) async {},
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
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
}
