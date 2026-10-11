import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

class _FakePad implements SignaturePadClient {
  _FakePad({this.available = true, this.points = 0});
  bool available;
  int points;
  final calls = <String>[];
  final png = Uint8List.fromList(
    // 1x1 transparent PNG.
    const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ],
  );

  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<void> beginCapture() async => calls.add('begin');
  @override
  Future<int> pointCount() async => points;
  @override
  Future<void> clear() async => calls.add('clear');
  @override
  Future<Uint8List> capturePng() async {
    calls.add('png');
    return png;
  }

  @override
  Future<void> endCapture() async => calls.add('end');
  @override
  void dispose() {}
}

Future<Uint8List?> _open(WidgetTester tester, _FakePad pad) async {
  Uint8List? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          result = await showDialog<Uint8List>(
            context: context,
            builder: (_) => SignatureCaptureDialog(padClient: pad),
          );
        },
        child: const Text('Open'),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump();
  return result;
}

void main() {
  testWidgets('falls back to the on-screen board when no pad is detected',
      (tester) async {
    final pad = _FakePad(available: false);
    await _open(tester, pad);

    expect(find.textContaining('not detected'), findsOneWidget);
    expect(find.text('Sign on the Topaz pad'), findsNothing);
    expect(pad.calls, isEmpty);
  });

  testWidgets('uses the pad when available and warns if nothing was signed',
      (tester) async {
    final pad = _FakePad();
    await _open(tester, pad);

    expect(find.text('Sign on the Topaz pad'), findsOneWidget);
    expect(pad.calls, ['begin']);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Sign on the pad before continuing.'), findsOneWidget);
    expect(pad.calls, isNot(contains('png')));
  });

  testWidgets('captures from the pad and returns the PNG', (tester) async {
    final pad = _FakePad(points: 30);
    Uint8List? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showDialog<Uint8List>(
              context: context,
              builder: (_) => SignatureCaptureDialog(padClient: pad),
            );
          },
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pump();
    await tester.pump();
    expect(pad.calls, ['begin', 'png', 'end']);

    await tester.tap(find.widgetWithText(FilledButton, 'Use Signature'));
    await tester.pumpAndSettle();
    expect(result, pad.png);
  });

  testWidgets('"Use On-Screen Board" stops the pad and shows the canvas',
      (tester) async {
    final pad = _FakePad();
    await _open(tester, pad);

    await tester.tap(find.widgetWithText(SecondaryPillButton, 'Use On-Screen Board'));
    await tester.pump();

    expect(pad.calls, ['begin', 'end']);
    expect(find.text('Sign on the Topaz pad'), findsNothing);
  });
}
