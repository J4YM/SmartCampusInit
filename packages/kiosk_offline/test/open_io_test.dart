import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/src/open_io.dart';

import 'support/fake_remote.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('kiosk_open_io_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<dynamic> open(String path) => openKioskOfflineAt(
        path,
        remote: FakeRemote()..pingResult = false,
        readerUsbSerial: 'KIOSK-MAIN-001',
      );

  test('a corrupt database file throws instead of returning a dead service', () async {
    final f = File('${tmp.path}${Platform.pathSeparator}bad.sqlite')
      ..writeAsBytesSync(List<int>.generate(4096, (i) => (i * 31 + 7) & 0xff));
    await expectLater(open(f.path), throwsA(anything));
  });

  test('a path whose parent is a regular file throws', () async {
    final parent = File('${tmp.path}${Platform.pathSeparator}notadir')..writeAsStringSync('x');
    final p = '${parent.path}${Platform.pathSeparator}k.sqlite';
    await expectLater(open(p), throwsA(anything));
  });

  test('a path that is a directory throws', () async {
    final d = Directory('${tmp.path}${Platform.pathSeparator}dir.sqlite')..createSync();
    await expectLater(open(d.path), throwsA(anything));
  });

  test('a fresh path opens and disposes cleanly', () async {
    final p = '${tmp.path}${Platform.pathSeparator}ok.sqlite';
    final svc = await open(p);
    expect(svc, isNotNull);
    await svc.dispose();
  });
}
