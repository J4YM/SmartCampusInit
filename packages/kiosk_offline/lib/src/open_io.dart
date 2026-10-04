import 'dart:io';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'kiosk_database.dart';
import 'kiosk_offline_api.dart';
import 'kiosk_offline_impl.dart';
import 'kiosk_remote.dart';
import 'tap_rules.dart';

/// Opens (creating if needed) the on-disk database and starts background
/// sync. Throws if the database file cannot be opened — callers fall back to
/// online-only behaviour.
Future<KioskOffline?> openKioskOffline({
  required KioskRemote remote,
  required String readerUsbSerial,
  Duration tapOutMinWait = const Duration(hours: 1),
}) async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}kiosk_offline.sqlite');
  final db = KioskDatabase(NativeDatabase(file));
  final svc = KioskOfflineImpl(
    db: db,
    remote: remote,
    readerUsbSerial: readerUsbSerial,
    rules: TapRules(tapOutMinWait: tapOutMinWait),
  );
  await svc.start();
  return svc;
}
