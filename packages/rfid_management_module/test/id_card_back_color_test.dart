import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// The front and the back of an ID card are coloured separately, and the
/// signature sits on the card's own colour instead of in a white box.
void main() {
  group('front and back colours', () {
    const red = 0xFFCD4855;
    const blue = 0xFF345892;
    const white = 0xFFFFFFFF;

    Future<void> pumpEditor(
      WidgetTester tester, {
      int front = white,
      int? back,
      void Function(int front, int back)? onSaved,
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: IdCardTemplateEditorPage(
          templateName: 'Test Template',
          initialFrontLayout: const [],
          initialBackLayout: const [],
          initialBackgroundColor: front,
          initialBackBackgroundColor: back,
          onSave: (f, b, orientation, backgroundColor, backBackgroundColor) async =>
              onSaved?.call(backgroundColor, backBackgroundColor),
          onUploadImage: (bytes, fileName) async => 'fake/path.png',
          onRename: (newName) async {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    // The editable card: the one tight-sized container casting a shadow.
    final editableCard = find.byWidgetPredicate((w) =>
        w is Container &&
        (w.constraints?.hasTightWidth ?? false) &&
        w.decoration is BoxDecoration &&
        ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false));

    Color canvas(WidgetTester tester) =>
        (tester.widget<Container>(editableCard).decoration as BoxDecoration)
            .color!;

    Future<void> tapCard(WidgetTester tester) async {
      await tester
          .tapAt(tester.getCenter(find.byType(DragTarget<IdCardElementType>)));
      await tester.pumpAndSettle();
    }

    Future<void> showBack(WidgetTester tester) async {
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
    }

    testWidgets('each side shows its own colour', (tester) async {
      await pumpEditor(tester, front: blue, back: red);
      expect(canvas(tester), const Color(blue));
      await showBack(tester);
      expect(canvas(tester), const Color(red));
    });

    testWidgets('a template with no back colour starts the back on the front colour',
        (tester) async {
      await pumpEditor(tester, front: blue);
      await showBack(tester);
      expect(canvas(tester), const Color(blue));
    });

    testWidgets('the Background option says which side it is colouring',
        (tester) async {
      await pumpEditor(tester);
      await tapCard(tester);
      expect(find.text('Front background'), findsOneWidget);

      await showBack(tester);
      await tapCard(tester);
      expect(find.text('Back background'), findsOneWidget);
      expect(find.text('Front background'), findsNothing);
    });

    testWidgets('colouring the back leaves the front alone (and vice versa)',
        (tester) async {
      int? savedFront, savedBack;
      await pumpEditor(tester, onSaved: (f, b) {
        savedFront = f;
        savedBack = b;
      });

      // Back goes red.
      await showBack(tester);
      await tapCard(tester);
      await tester.tap(find.byTooltip('Red'));
      await tester.pumpAndSettle();
      expect(canvas(tester), const Color(red));

      // The front is still white.
      await tester.tap(find.text('Front'));
      await tester.pumpAndSettle();
      expect(canvas(tester), const Color(white));

      // Front goes blue; the back keeps its red.
      await tapCard(tester);
      await tester.tap(find.byTooltip('Blue'));
      await tester.pumpAndSettle();
      expect(canvas(tester), const Color(blue));
      await showBack(tester);
      expect(canvas(tester), const Color(red));

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(savedFront, blue);
      expect(savedBack, red);
    });

    test('the model falls back to the front colour for the back', () {
      const same = IdCardTemplateDetail(
        id: 'a',
        name: 'a',
        frontLayout: [],
        backLayout: [],
        backgroundColor: 0xFF123456,
      );
      expect(same.backBackgroundColor, isNull);
      expect(same.effectiveBackBackgroundColor, 0xFF123456);

      const own = IdCardTemplateDetail(
        id: 'b',
        name: 'b',
        frontLayout: [],
        backLayout: [],
        backgroundColor: 0xFF123456,
        backBackgroundColor: 0xFFABCDEF,
      );
      expect(own.effectiveBackBackgroundColor, 0xFFABCDEF);
    });
  });

  group('signature background', () {
    /// A 20x10 PNG: opaque white paper with a solid black bar, like a
    /// signature saved before the pad exported transparency.
    Future<Uint8List> whitePaperSignature() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 20, 10),
          ui.Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawRect(const Rect.fromLTWH(5, 4, 10, 2),
          ui.Paint()..color = const Color(0xFF000000));
      final image = await recorder.endRecording().toImage(20, 10);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }

    Future<List<int>> pixel(Uint8List png, int x, int y) async {
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      final data =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      final i = (y * image.width + x) * 4;
      return [for (var k = 0; k < 4; k++) data!.getUint8(i + k)];
    }

    testWidgets('white paper becomes transparent, the ink stays solid',
        (tester) async {
      await tester.runAsync(() async {
        final original = await whitePaperSignature();
        expect(await pixel(original, 0, 0), [255, 255, 255, 255]);

        final cleared = await signatureWithTransparentBackground(original);

        final paper = await pixel(cleared, 0, 0);
        expect(paper[3], 0, reason: 'the paper is see-through');
        final ink = await pixel(cleared, 10, 5);
        expect(ink, [0, 0, 0, 255], reason: 'the stroke is untouched');
      });
    });

    testWidgets('an already-transparent signature is returned as it is',
        (tester) async {
      await tester.runAsync(() async {
        final cleared = await signatureWithTransparentBackground(
            await whitePaperSignature());
        final again = await signatureWithTransparentBackground(cleared);
        expect(again, same(cleared));
      });
    });

    testWidgets('something that is not an image is returned untouched',
        (tester) async {
      await tester.runAsync(() async {
        final junk = Uint8List.fromList([1, 2, 3, 4, 5]);
        expect(await signatureWithTransparentBackground(junk), same(junk));
      });
    });
  });
}
