import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Must match windows/runner/flutter_window.cpp exactly.
const _channel = MethodChannel('sti_baliuag/window_lockdown');

/// Every window this repo's native Windows runner creates starts locked
/// down (fullscreen, no title bar/close button, Alt+F4 blocked — see
/// windows/runner/win32_window.cpp's EnterFullscreenKioskMode) since the
/// kiosk build (lib/main_kiosk.dart) needs that and native window
/// creation happens before any Dart entrypoint gets a say. Call this from
/// every OTHER entrypoint (lib/main.dart, lib/main_it_technician.dart) to
/// restore a normal, closable, resizable window — never from
/// lib/main_kiosk.dart, which must stay locked down so a student can't
/// close it.
///
/// A no-op on any platform other than Windows, and swallows the channel
/// call failing (e.g. running under `flutter test`, where no native
/// window/channel exists at all).
///
/// `kIsWeb` must be checked *before* touching `dart:io`'s `Platform` —
/// every member of that class, including `Platform.isWindows` itself,
/// throws `Unsupported operation` when running under a web compile
/// target (Platform is a native/VM-only API), which previously crashed
/// this app's entire startup on web before the first frame ever rendered.
Future<void> disableKioskLockdownOnWindows() async {
  if (kIsWeb || !Platform.isWindows) return;
  try {
    await _channel.invokeMethod('disableKioskLockdown');
  } on PlatformException catch (_) {
  } on MissingPluginException catch (_) {}
}
