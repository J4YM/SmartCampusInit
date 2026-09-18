import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// A minimal fake so `availableCameras()` fails predictably and instantly
/// instead of hanging: `camera`'s real platform implementations talk over
/// Pigeon-generated channels that, unlike a plain `MethodChannel`, never
/// resolve (rather than throwing `MissingPluginException`) when no native
/// side answers them — which is exactly the state a plain `flutter test`
/// run is in, with no real camera plugin registered.
class _ThrowingCameraPlatform extends CameraPlatform
    with MockPlatformInterfaceMixin {
  _ThrowingCameraPlatform(this.error);
  final Object error;
  int callCount = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    callCount++;
    throw error;
  }
}

void main() {
  late CameraPlatform originalPlatform;

  setUp(() {
    originalPlatform = CameraPlatform.instance;
    CameraPlatform.instance = _ThrowingCameraPlatform(
      CameraException(
        'cameraNotReadable',
        'The camera is not readable due to a hardware error that '
            'prevented access to the device.',
      ),
    );
  });

  tearDown(() {
    CameraPlatform.instance = originalPlatform;
  });

  Widget buildDialog() {
    return const MaterialApp(home: WebcamCaptureDialog());
  }

  testWidgets(
      'shows the not-readable explanation with Cancel/Retry actions when the camera fails to open',
      (tester) async {
    await tester.pumpWidget(buildDialog());
    await tester.pumpAndSettle();

    expect(
      find.textContaining('another app or browser tab'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    // The dead-end "Capture" button from the non-error action row must not
    // also be showing at the same time.
    expect(find.widgetWithText(FilledButton, 'Capture'), findsNothing);
  });

  testWidgets('a non-cameraNotReadable failure shows the raw error instead',
      (tester) async {
    CameraPlatform.instance =
        _ThrowingCameraPlatform(StateError('camera subsystem exploded'));

    await tester.pumpWidget(buildDialog());
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open the camera:'), findsOneWidget);
    expect(
      find.textContaining('another app or browser tab'),
      findsNothing,
    );
  });

  testWidgets('tapping Retry attempts to open the camera again',
      (tester) async {
    await tester.pumpWidget(buildDialog());
    await tester.pumpAndSettle();
    final platform = CameraPlatform.instance as _ThrowingCameraPlatform;
    expect(platform.callCount, 1);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(platform.callCount, 2);
    expect(
      find.textContaining('another app or browser tab'),
      findsOneWidget,
    );
  });

  testWidgets('Cancel pops the dialog with no result', (tester) async {
    Uint8List? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showDialog<Uint8List>(
              context: context,
              builder: (_) => const WebcamCaptureDialog(),
            );
          },
          child: const Text('Open'),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.byType(WebcamCaptureDialog), findsNothing);
  });
}
