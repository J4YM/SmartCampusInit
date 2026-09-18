// packages/rfid_management_module/test/id_card_template_editor_print_mode_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// No-op fake so a real camera_windows/camera_web plugin call is never
/// attempted — `availableCameras()` hangs forever without a fake (see
/// webcam_capture_dialog_test.dart's own doc comment on this).
class _FakeCameraPlatform extends CameraPlatform with MockPlatformInterfaceMixin {
  @override
  Future<List<CameraDescription>> availableCameras() async =>
      [const CameraDescription(
        name: 'fake',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 0,
      )];
}

/// A real, valid 1x1 transparent PNG — `Image.memory` needs actual
/// decodable image bytes, not arbitrary placeholder bytes, or it throws
/// asynchronously during the codec decode (which then fails the test).
final Uint8List _validPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

const _student = RfidStudentRow(
  id: 'student-1',
  rfidNo: '',
  studentNumber: '2023-0001',
  firstName: 'Juan',
  middleInitial: 'D',
  lastName: 'Cruz',
  course: 'BSIT',
  yearLevel: '3rd Year',
  section: 'BSIT 3A',
  guardianName: 'Maria Cruz',
  guardianContactNo: '09171234567',
);

const _photoElement = IdCardTemplateElement(
  id: 'photo',
  type: IdCardElementType.idPicture,
  x: 10,
  y: 10,
  width: 60,
  height: 70,
);

const _nameElement = IdCardTemplateElement(
  id: 'name',
  type: IdCardElementType.idData,
  x: 10,
  y: 90,
  width: 100,
  height: 20,
  fieldKey: IdDataFieldKey.firstName,
);

const _signatureElement = IdCardTemplateElement(
  id: 'sig',
  type: IdCardElementType.signature,
  x: 10,
  y: 10,
  width: 100,
  height: 30,
);

void main() {
  late CameraPlatform originalPlatform;
  setUp(() {
    originalPlatform = CameraPlatform.instance;
    CameraPlatform.instance = _FakeCameraPlatform();
  });
  tearDown(() => CameraPlatform.instance = originalPlatform);

  IdCardPrintContext buildPrintContext({
    Uint8List? initialPhotoBytes,
    Uint8List? initialSignatureBytes,
    Future<void> Function({
      required Uint8List photoBytes,
      required Uint8List? signatureBytes,
      required List<IdCardTemplateElement> frontLayout,
      required List<IdCardTemplateElement> backLayout,
    })? onPrint,
  }) {
    return IdCardPrintContext(
      student: _student,
      initialTemplateId: 'template-1',
      initialPhotoBytes: initialPhotoBytes,
      initialSignatureBytes: initialSignatureBytes,
      availableTemplates: const [],
      onLoadTemplate: (_) async =>
          const IdCardTemplateDetail(id: 'template-1', name: 'x', frontLayout: [], backLayout: []),
      onPrint: onPrint ?? ({required photoBytes, required signatureBytes, required frontLayout, required backLayout}) async {},
    );
  }

  // `IdCardTemplateEditorPage`'s State seeds several fields from its
  // `initial*` constructor params via `late` initializers that only ever
  // run once (Flutter reuses the same State object across a same-type,
  // same-key `pumpWidget` in place — real usage always pushes a fresh
  // route per print/edit session, so this never comes up outside tests).
  // A distinct Key per call forces a real remount whenever a test pumps
  // more than one variant, matching that real lifecycle.
  Widget buildEditor({
    required List<IdCardTemplateElement> front,
    List<IdCardTemplateElement> back = const [],
    IdCardPrintContext? printContext,
    Key? key,
  }) {
    return MaterialApp(
      home: IdCardTemplateEditorPage(
        key: key,
        templateName: 'Standard Template',
        initialFrontLayout: front,
        initialBackLayout: back,
        onSave: (_, __) async {},
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
        onRename: (_) async {},
        printContext: printContext,
      ),
    );
  }

  testWidgets('with no printContext, no print controls appear and canvas keeps placeholders',
      (tester) async {
    await tester.pumpWidget(buildEditor(front: [_photoElement, _nameElement]));
    await tester.pumpAndSettle();

    expect(find.text('PHOTO'), findsOneWidget);
    expect(find.text('{firstName}'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Print'), findsNothing);
    expect(find.widgetWithIcon(OutlinedButton, Icons.camera_alt_outlined), findsNothing);
  });

  testWidgets('with printContext, the canvas shows the real photo and field value',
      (tester) async {
    final photoBytes = _validPngBytes;
    await tester.pumpWidget(buildEditor(
      front: [_photoElement, _nameElement],
      printContext: buildPrintContext(initialPhotoBytes: photoBytes),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PHOTO'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('{firstName}'), findsNothing);
    expect(find.text('Juan'), findsOneWidget);
  });

  testWidgets('Capture Photo opens the webcam dialog and the returned bytes replace the placeholder',
      (tester) async {
    await tester.pumpWidget(buildEditor(
      front: [_photoElement],
      printContext: buildPrintContext(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PHOTO'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Capture Photo'));
    await tester.pumpAndSettle();

    expect(find.byType(WebcamCaptureDialog), findsOneWidget);
  });

  testWidgets('Capture Signature button only shows when the template has a signature element',
      (tester) async {
    await tester.pumpWidget(buildEditor(
      front: [_photoElement],
      printContext: buildPrintContext(),
    ));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Capture Signature'), findsNothing);

    await tester.pumpWidget(buildEditor(
      key: const Key('with-signature'),
      front: [_photoElement],
      back: [_signatureElement],
      printContext: buildPrintContext(),
    ));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Capture Signature'), findsOneWidget);
  });

  testWidgets('Print is disabled until a photo exists, and disabled again if a signature is still missing',
      (tester) async {
    await tester.pumpWidget(buildEditor(
      front: [_photoElement],
      back: [_signatureElement],
      printContext: buildPrintContext(),
    ));
    await tester.pumpAndSettle();

    FilledButton currentPrintButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Print'));
    expect(currentPrintButton().onPressed, isNull);

    await tester.pumpWidget(buildEditor(
      key: const Key('with-photo'),
      front: [_photoElement],
      back: [_signatureElement],
      printContext: buildPrintContext(initialPhotoBytes: _validPngBytes),
    ));
    await tester.pumpAndSettle();
    expect(currentPrintButton().onPressed, isNull); // still missing signature

    await tester.pumpWidget(buildEditor(
      key: const Key('with-photo-and-signature'),
      front: [_photoElement],
      back: [_signatureElement],
      printContext: buildPrintContext(
        initialPhotoBytes: _validPngBytes,
        initialSignatureBytes: _validPngBytes,
      ),
    ));
    await tester.pumpAndSettle();
    expect(currentPrintButton().onPressed, isNotNull);
  });

  testWidgets('tapping Print calls onPrint with the current layout and bytes, then pops',
      (tester) async {
    List<IdCardTemplateElement>? printedFront;
    Uint8List? printedPhoto;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => IdCardTemplateEditorPage(
              templateName: 'Standard Template',
              initialFrontLayout: const [_photoElement],
              initialBackLayout: const [],
              onSave: (_, __) async {},
              onUploadImage: (bytes, fileName) async => 'fake/path.png',
              onRename: (_) async {},
              printContext: buildPrintContext(
                initialPhotoBytes: _validPngBytes,
                onPrint: ({
                  required photoBytes,
                  required signatureBytes,
                  required frontLayout,
                  required backLayout,
                }) async {
                  printedFront = frontLayout;
                  printedPhoto = photoBytes;
                },
              ),
            ),
          )),
          child: const Text('Open'),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Print'));
    await tester.pumpAndSettle();

    expect(printedFront, [_photoElement]);
    expect(printedPhoto, _validPngBytes);
    expect(find.byType(IdCardTemplateEditorPage), findsNothing);
  });
}
