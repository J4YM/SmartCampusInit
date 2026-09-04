import 'package:attendance_display/reader_input_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 4, 12, 0, 0);
  const threshold = Duration(minutes: 5);

  test('falls back when delivering but no raw tap was ever recorded', () {
    expect(
      shouldFallBack(
        delivering: true,
        lastRawTapAt: null,
        now: now,
        threshold: threshold,
      ),
      isTrue,
    );
  });

  test('does not fall back when a recent raw tap was just recorded', () {
    expect(
      shouldFallBack(
        delivering: true,
        lastRawTapAt: now.subtract(const Duration(seconds: 30)),
        now: now,
        threshold: threshold,
      ),
      isFalse,
    );
  });

  test('falls back once the last raw tap is older than the threshold', () {
    expect(
      shouldFallBack(
        delivering: true,
        lastRawTapAt: now.subtract(const Duration(minutes: 10)),
        now: now,
        threshold: threshold,
      ),
      isTrue,
    );
  });

  test('never falls back when not currently delivering', () {
    // Nothing to correct: the text-field fallback is already active.
    expect(
      shouldFallBack(
        delivering: false,
        lastRawTapAt: null,
        now: now,
        threshold: threshold,
      ),
      isFalse,
    );
    expect(
      shouldFallBack(
        delivering: false,
        lastRawTapAt: now.subtract(const Duration(minutes: 10)),
        now: now,
        threshold: threshold,
      ),
      isFalse,
    );
  });
}
