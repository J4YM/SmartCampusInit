import 'package:capstone_dashboard/kiosk/capstone_kiosk_scan_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/kiosk_offline.dart';

void main() {
  test('Review Focus 5: a database that cannot open yields null, not a crash', () async {
    Object? reported;
    final result = await openOfflineOrNull(
      () async => throw StateError('database is locked'),
      onError: (e) => reported = e,
    );
    expect(result, isNull);
    expect(reported, isA<StateError>());
  });

  test('a null opener result (web) passes through', () async {
    expect(await openOfflineOrNull(() async => null), isNull);
  });

  test('a successful opener result is returned', () async {
    final fake = _NoopOffline();
    expect(await openOfflineOrNull(() async => fake), same(fake));
  });
}

class _NoopOffline implements KioskOffline {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
