import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

void main() {
  testWidgets('shows an error when Done is tapped with nothing drawn',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SignatureCaptureDialog()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(find.text('Draw a signature before continuing.'), findsOneWidget);
  });

  testWidgets('Cancel pops with null', (tester) async {
    Uint8List? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showDialog<Uint8List>(
              context: context,
              builder: (_) => const SignatureCaptureDialog(),
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
  });
}
