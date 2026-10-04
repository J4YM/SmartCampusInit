import 'kiosk_offline_api.dart';
import 'kiosk_remote.dart';

/// Web (and any platform without `dart:io`): no local database, so the
/// caller keeps its existing online-only behaviour.
Future<KioskOffline?> openKioskOffline({
  required KioskRemote remote,
  required String readerUsbSerial,
  Duration tapOutMinWait = const Duration(hours: 1),
}) async =>
    null;
