import 'package:flutter/services.dart';

/// Plays the platform's alert sound — the Windows "default beep", the
/// Android/iOS notification tone. No audio package or bundled file: the
/// Flutter engine already knows how to ask the OS for it.
Future<void> playNotificationSound() async {
  try {
    await SystemSound.play(SystemSoundType.alert);
  } catch (_) {
    // A sound is a nicety; never let it break a refresh.
  }
}
