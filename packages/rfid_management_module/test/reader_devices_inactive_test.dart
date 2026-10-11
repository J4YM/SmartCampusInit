import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// Deactivated readers (decommissioned hardware, e.g. the starter "Floor n"
/// readers) are out of the Reader Devices list unless asked for.
void main() {
  RfidReaderRowModel reader(String id, String label, {bool active = true}) =>
      RfidReaderRowModel(
        id: id,
        label: label,
        usbSerial: 'USB-$id',
        location: 'Somewhere',
        isKioskReader: false,
        isActive: active,
        isOnline: true,
        lastSeenLabel: '1m ago',
      );

  Future<void> show(
    WidgetTester tester,
    List<RfidReaderRowModel> readers, {
    Future<void> Function(String id, bool isActive)? onSetActive,
  }) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RfidReaderManagementPage(
            embedded: true,
            readers: readers,
            isBusy: false,
            onAddReader: ({required label, required usbSerial, location}) async {},
            onUpdateReader: (
                    {required id,
                    required label,
                    required usbSerial,
                    location}) async {},
            onSetActive: onSetActive ?? (_, __) async {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('inactive readers are hidden, with a way to show them',
      (tester) async {
    await show(tester, [
      reader('k', 'Main Kiosk'),
      reader('1', 'Floor 1 Reader', active: false),
      reader('2', 'Floor 2 Reader', active: false),
    ]);

    expect(find.text('Main Kiosk'), findsOneWidget);
    expect(find.text('Floor 1 Reader'), findsNothing);
    expect(find.text('Floor 2 Reader'), findsNothing);
    expect(find.text('Show 2 inactive readers'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle-inactive-readers')));
    await tester.pumpAndSettle();
    expect(find.text('Floor 1 Reader'), findsOneWidget);
    expect(find.text('Floor 2 Reader'), findsOneWidget);
    expect(find.text('Hide inactive readers'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle-inactive-readers')));
    await tester.pumpAndSettle();
    expect(find.text('Floor 1 Reader'), findsNothing);
  });

  testWidgets('says "1 inactive reader" for one', (tester) async {
    await show(tester, [
      reader('k', 'Main Kiosk'),
      reader('1', 'Floor 1 Reader', active: false),
    ]);
    expect(find.text('Show 1 inactive reader'), findsOneWidget);
  });

  testWidgets('no toggle when every reader is active', (tester) async {
    await show(tester, [reader('k', 'Main Kiosk'), reader('1', 'Lobby')]);
    expect(find.byKey(const Key('toggle-inactive-readers')), findsNothing);
    expect(find.text('Lobby'), findsOneWidget);
  });

  testWidgets('with only inactive readers it says so instead of "none yet"',
      (tester) async {
    await show(tester, [reader('1', 'Floor 1 Reader', active: false)]);
    expect(find.textContaining('No active readers'), findsOneWidget);
    expect(find.textContaining('No readers registered yet'), findsNothing);
  });

  testWidgets('a deactivated reader can be reactivated from the shown list',
      (tester) async {
    final calls = <(String, bool)>[];
    await show(
      tester,
      [reader('1', 'Floor 1 Reader', active: false)],
      onSetActive: (id, active) async => calls.add((id, active)),
    );
    await tester.tap(find.byKey(const Key('toggle-inactive-readers')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reactivate'));
    await tester.pumpAndSettle();
    expect(calls, [('1', true)]);
  });

  testWidgets('the choice survives the host refreshing the list',
      (tester) async {
    final list = [
      reader('k', 'Main Kiosk'),
      reader('1', 'Floor 1 Reader', active: false),
    ];
    await show(tester, list);
    await tester.tap(find.byKey(const Key('toggle-inactive-readers')));
    await tester.pumpAndSettle();
    expect(find.text('Floor 1 Reader'), findsOneWidget);

    // The background refresh hands down a fresh list.
    await show(tester, [...list]);
    expect(find.text('Floor 1 Reader'), findsOneWidget);
  });
}
