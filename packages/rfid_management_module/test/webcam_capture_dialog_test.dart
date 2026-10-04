import 'package:dashboard_layout/dashboard_layout.dart';
import 'dart:typed_data';

import 'package:camera/camera.dart' show CameraPreview;
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rfid_management_module/rfid_management_module.dart';
import 'package:rfid_management_module/ui/webcam_capture_dialog.dart'
    show orderCamerasForOpening, webcamRetryDelay;

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
    expect(find.widgetWithText(SecondaryPillButton, 'Cancel'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
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

    await tester.tap(find.text('Retry'));
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
    await tester.tap(find.widgetWithText(SecondaryPillButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.byType(WebcamCaptureDialog), findsNothing);
  });

  group('with several cameras', () {
    final original = webcamRetryDelay;
    setUp(() => webcamRetryDelay = Duration.zero);
    tearDown(() => webcamRetryDelay = original);

    CameraDescription cam(String name) => CameraDescription(
          name: name,
          lensDirection: CameraLensDirection.external,
          sensorOrientation: 0,
        );

    Future<_FakeMultiCameraPlatform> open(
      WidgetTester tester,
      _FakeMultiCameraPlatform platform,
    ) async {
      CameraPlatform.instance = platform;
      await tester.pumpWidget(const MaterialApp(home: WebcamCaptureDialog()));
      await tester.pumpAndSettle();
      return platform;
    }

    testWidgets(
        'a dead first camera (virtual cam, IR sensor…) no longer stops the '
        'real webcam from opening', (tester) async {
      final platform = await open(
        tester,
        _FakeMultiCameraPlatform(
          cameras: [cam('Virtual Cam X'), cam('Integrated Webcam')],
          alwaysFails: {'Virtual Cam X'},
        ),
      );
      expect(find.textContaining('another app or browser tab'), findsNothing);
      expect(find.byType(CameraPreview), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Capture'))
              .onPressed,
          isNotNull);
      // The real webcam was tried first (virtual cameras go last) and kept.
      expect(platform.openedNames.first, 'Integrated Webcam');
    });

    testWidgets('an unlisted-by-name dead camera is skipped for the next one',
        (tester) async {
      final platform = await open(
        tester,
        _FakeMultiCameraPlatform(
          cameras: [cam('USB Camera A'), cam('USB Camera B')],
          alwaysFails: {'USB Camera A'},
        ),
      );
      expect(find.byType(CameraPreview), findsOneWidget);
      // A was tried (twice — see the release race below), then B opened.
      expect(platform.attemptedNames, ['USB Camera A', 'USB Camera A', 'USB Camera B']);
    });

    testWidgets(
        'a camera that is only briefly unavailable (the OS still releasing the '
        'probe stream) opens on the second try', (tester) async {
      final platform = await open(
        tester,
        _FakeMultiCameraPlatform(
          cameras: [cam('Integrated Webcam')],
          failFirstAttemptFor: {'Integrated Webcam'},
        ),
      );
      expect(find.textContaining('another app or browser tab'), findsNothing);
      expect(find.byType(CameraPreview), findsOneWidget);
      expect(platform.attemptedNames, ['Integrated Webcam', 'Integrated Webcam']);
    });

    testWidgets(
        'when every camera is genuinely unavailable the not-readable message '
        'still shows, with Retry', (tester) async {
      await open(
        tester,
        _FakeMultiCameraPlatform(
          cameras: [cam('Cam 1'), cam('Cam 2')],
          alwaysFails: {'Cam 1', 'Cam 2'},
        ),
      );
      expect(find.textContaining('another app or browser tab'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a different kind of failure on one camera moves on to the next',
        (tester) async {
      final platform = await open(
        tester,
        _FakeMultiCameraPlatform(
          cameras: [cam('Cam 1'), cam('Cam 2')],
          alwaysFails: {'Cam 1'},
          failureCode: 'cameraPermission',
        ),
      );
      expect(find.byType(CameraPreview), findsOneWidget);
      // No pointless second try for a failure that is not "busy".
      expect(platform.attemptedNames, ['Cam 1', 'Cam 2']);
    });

    test('real webcams are tried before IR sensors and virtual cameras', () {
      final ordered = orderCamerasForOpening([
        cam('Integrated IR Camera'),
        cam('OBS Virtual Camera'),
        cam('Integrated Webcam'),
        cam('Logitech HD Webcam'),
        cam('Windows Hello Face'),
      ]);
      expect([for (final c in ordered) c.name], [
        'Integrated Webcam',
        'Logitech HD Webcam',
        'Integrated IR Camera',
        'OBS Virtual Camera',
        'Windows Hello Face',
      ]);
    });

    test('with only ordinary cameras the system order is kept', () {
      final ordered = orderCamerasForOpening(
          [cam('USB Camera B'), cam('USB Camera A'), cam('Integrated Camera')]);
      expect([for (final c in ordered) c.name],
          ['USB Camera B', 'USB Camera A', 'Integrated Camera']);
    });
  });
}

/// A camera backend with several devices, some of which can't be opened.
class _FakeMultiCameraPlatform extends CameraPlatform
    with MockPlatformInterfaceMixin {
  _FakeMultiCameraPlatform({
    required this.cameras,
    this.alwaysFails = const {},
    this.failFirstAttemptFor = const {},
    this.failureCode = 'cameraNotReadable',
  });

  final List<CameraDescription> cameras;

  /// Devices that never open.
  final Set<String> alwaysFails;

  /// Devices that fail their first open but work afterwards.
  final Set<String> failFirstAttemptFor;
  final String failureCode;

  final Map<int, String> _namesById = {};
  final List<String> attemptedNames = [];
  final List<String> openedNames = [];
  int _nextId = 1;

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    final id = _nextId++;
    _namesById[id] = cameraDescription.name;
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    final name = _namesById[cameraId]!;
    final attemptsSoFar = attemptedNames.where((n) => n == name).length;
    attemptedNames.add(name);
    if (alwaysFails.contains(name) ||
        (failFirstAttemptFor.contains(name) && attemptsSoFar == 0)) {
      throw CameraException(failureCode, 'Could not start video source');
    }
    openedNames.add(name);
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(CameraInitializedEvent(
        cameraId,
        640,
        480,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ));

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      const Stream.empty();

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => const Stream.empty();

  @override
  Widget buildPreview(int cameraId) => const SizedBox(width: 10, height: 10);

  @override
  Future<void> pausePreview(int cameraId) async {}

  @override
  Future<void> dispose(int cameraId) async {}
}
