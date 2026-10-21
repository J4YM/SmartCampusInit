import 'package:capstone_dashboard/auth/login_attempt_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Typing a name that belongs to no account must never lock anyone out:
/// only failed passwords for accounts that exist count toward the lockout.
/// (Supabase is not configured in tests, so this exercises the local counter.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('many wrong attempts for names that do not exist never lock', () async {
    for (var i = 0; i < 8; i++) {
      final status =
          await LoginAttemptGuard.recordFailure('nobody$i', accountExists: false);
      expect(status.locked, isFalse, reason: 'attempt $i');
      expect(status.remaining, LoginAttemptGuard.maxAttempts);
    }
    expect((await LoginAttemptGuard.check()).locked, isFalse);
  });

  test('wrong passwords for an account that exists still lock after the limit',
      () async {
    for (var i = 1; i < LoginAttemptGuard.maxAttempts; i++) {
      final s = await LoginAttemptGuard.recordFailure('do.demo');
      expect(s.locked, isFalse);
    }
    final last = await LoginAttemptGuard.recordFailure('do.demo');
    expect(last.locked, isTrue);
    expect(last.minutesLeft, greaterThan(0));
  });

  test('unknown names in between do not use up or reset the real count',
      () async {
    await LoginAttemptGuard.recordFailure('do.demo');
    await LoginAttemptGuard.recordFailure('typo.name', accountExists: false);
    final second = await LoginAttemptGuard.recordFailure('do.demo');
    expect(second.remaining, LoginAttemptGuard.maxAttempts - 2);
    await LoginAttemptGuard.recordFailure('another.typo', accountExists: false);
    final third = await LoginAttemptGuard.recordFailure('do.demo');
    expect(third.locked, isTrue);
  });

  test('a session that is already locked stays locked for unknown names too',
      () async {
    for (var i = 0; i < LoginAttemptGuard.maxAttempts; i++) {
      await LoginAttemptGuard.recordFailure('do.demo');
    }
    final status =
        await LoginAttemptGuard.recordFailure('nobody', accountExists: false);
    expect(status.locked, isTrue);
  });

  test('accountExists defaults to true, so existing callers keep counting',
      () async {
    for (var i = 0; i < LoginAttemptGuard.maxAttempts; i++) {
      await LoginAttemptGuard.recordFailure('someone');
    }
    expect((await LoginAttemptGuard.check()).locked, isTrue);
  });
}
