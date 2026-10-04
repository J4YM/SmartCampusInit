/// Pure-Dart port of the decision rules in `public.record_rfid_tap`
/// (supabase/fix_rfid_school_day_timezone.sql). Keep in lock-step with that
/// function: a SQL rule change needs a matching change here and in the
/// shared vectors in test/tap_rules_test.dart.
const Duration _manilaOffset = Duration(hours: 8); // Asia/Manila, no DST
const Duration _schoolDayShift = Duration(hours: 5, minutes: 30);

/// The school day a tap belongs to: Manila wall-clock shifted by 5 h 30 min,
/// so the day rolls over at 6:30 PM Manila, not midnight. Independent of the
/// machine's own timezone.
String schoolDayOf(DateTime instant) {
  final s = instant.toUtc().add(_manilaOffset + _schoolDayShift);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${s.year.toString().padLeft(4, '0')}-${two(s.month)}-${two(s.day)}';
}

/// The student's latest tap on the same school day.
class PriorTap {
  const PriorTap({required this.direction, required this.tappedAt});

  /// `'in'` or `'out'`.
  final String direction;
  final DateTime tappedAt;
}

sealed class TapDecision {
  const TapDecision();
}

/// Record a new tap with this direction.
final class TapAccepted extends TapDecision {
  const TapAccepted(this.direction);
  final String direction;
}

/// Accidental double tap: echo the previous tap, record nothing new.
final class TapEchoed extends TapDecision {
  const TapEchoed(this.direction);
  final String direction;
}

/// Refused by a business rule; [message] is a complete student-facing sentence.
final class TapDenied extends TapDecision {
  const TapDenied(this.message);
  final String message;
}

class TapRules {
  const TapRules({
    this.tapOutMinWait = const Duration(hours: 1),
    this.debounce = const Duration(seconds: 5),
  });

  /// Minimum time between tap-in and tap-out. Must match the live SQL.
  final Duration tapOutMinWait;
  final Duration debounce;

  String get _waitLabel {
    final secs = tapOutMinWait.inSeconds;
    if (secs % 3600 == 0) {
      final h = secs ~/ 3600;
      return h == 1 ? '1 hour' : '$h hours';
    }
    return '$secs seconds';
  }

  TapDecision decide({
    required DateTime tappedAt,
    required bool studentKnown,
    PriorTap? lastTapToday,
  }) {
    // Unrecognised card: the rules only apply to a resolved student.
    if (!studentKnown) return const TapAccepted('in');

    final last = lastTapToday;
    if (last == null) return const TapAccepted('in');

    final elapsed = tappedAt.difference(last.tappedAt);
    if (elapsed < debounce) return TapEchoed(last.direction);

    if (last.direction == 'in') {
      if (elapsed < tapOutMinWait) {
        return TapDenied(
          'Please wait at least $_waitLabel after tapping in before tapping out.',
        );
      }
      return const TapAccepted('out');
    }
    return const TapDenied('You have already tapped in and out for today.');
  }
}
