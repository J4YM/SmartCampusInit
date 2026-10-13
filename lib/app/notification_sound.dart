import 'notification_sound_io.dart'
    if (dart.library.js_interop) 'notification_sound_web.dart' as platform;

/// The sound a new notification makes, on every platform the app runs on:
/// the OS alert on desktop/mobile, a synthesized chime in the browser.
Future<void> playNotificationSound() => platform.playNotificationSound();
