import 'dart:js_interop';

/// A short two-note chime, synthesized with the browser's Web Audio API — the
/// web build has no OS alert to ask for (`SystemSound` does nothing there) and
/// this needs neither a bundled audio file nor an audio package.

@JS('AudioContext')
extension type _AudioContext._(JSObject _) implements JSObject {
  external _AudioContext();
  external double get currentTime;
  external JSObject get destination;
  external _Oscillator createOscillator();
  external _Gain createGain();
  external JSPromise<JSAny?> resume();
}

extension type _Param._(JSObject _) implements JSObject {
  external set value(double v);
  external void setValueAtTime(double value, double time);
  external void exponentialRampToValueAtTime(double value, double time);
}

extension type _Oscillator._(JSObject _) implements JSObject {
  external _Param get frequency;
  external set type(String t);
  external void connect(JSObject destination);
  external void start(double when);
  external void stop(double when);
}

extension type _Gain._(JSObject _) implements JSObject {
  external _Param get gain;
  external void connect(JSObject destination);
}

_AudioContext? _context;

Future<void> playNotificationSound() async {
  try {
    final ctx = _context ??= _AudioContext();
    // A context created before the person has touched the page starts
    // suspended (autoplay policy); by the time a notification arrives they
    // have signed in, so this lets it run.
    ctx.resume();
    final start = ctx.currentTime;

    void tone(double hz, double at, double length) {
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = hz;
      // A soft attack and a quick fade, so it chimes rather than clicks.
      gain.gain.setValueAtTime(0.0001, at);
      gain.gain.exponentialRampToValueAtTime(0.22, at + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, at + length);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(at);
      osc.stop(at + length + 0.02);
    }

    tone(880, start, 0.18);
    tone(1318.5, start + 0.14, 0.32);
  } catch (_) {
    // A sound is a nicety; never let it break a refresh.
  }
}
