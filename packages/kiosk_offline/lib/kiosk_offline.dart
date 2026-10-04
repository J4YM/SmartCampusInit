/// Offline-first cache, tap rules and sync outbox for the Windows kiosk.
///
/// `openKioskOffline` is a conditional export: the real SQLite-backed
/// implementation on `dart:io` platforms, a `null`-returning stub on web, so
/// the web build never pulls in `dart:ffi`.
library kiosk_offline;

export 'src/kiosk_offline_api.dart';
export 'src/kiosk_remote.dart';
export 'src/models.dart';
export 'src/open_stub.dart' if (dart.library.io) 'src/open_io.dart';
