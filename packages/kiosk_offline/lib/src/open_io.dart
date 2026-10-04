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
  return openKioskOfflineAt(
    '${dir.path}${Platform.pathSeparator}kiosk_offline.sqlite',
    remote: remote,
    readerUsbSerial: readerUsbSerial,
    tapOutMinWait: tapOutMinWait,
  );
}

/// Like [openKioskOffline] but at an explicit [databasePath] (not exported by
/// the facade; used by tests). Drift opens SQLite lazily, so the open and
/// schema creation are forced here: an unusable file throws now rather than
/// returning a service that fails on every later call.
Future<KioskOffline?> openKioskOfflineAt(
  String databasePath, {
  required KioskRemote remote,
  required String readerUsbSerial,
  Duration tapOutMinWait = const Duration(hours: 1),
}) async {
  final db = KioskDatabase(NativeDatabase(File(databasePath)));
  try {
    await db.customSelect('SELECT 1').get();
    final check = await db.customSelect('PRAGMA quick_check').get();
    if (check.isEmpty || check.first.data.values.first != 'ok') {
      throw StateError('Kiosk database failed integrity check.');
    }
    await db.pendingCount();
  } catch (_) {
    try {
      await db.close();
    } catch (_) {}
    rethrow;
  }
  final svc = KioskOfflineImpl(
    db: db,
    remote: remote,
    readerUsbSerial: readerUsbSerial,
    rules: TapRules(tapOutMinWait: tapOutMinWait),
  );
  await svc.start();
  return svc;
}
