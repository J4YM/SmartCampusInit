import 'package:capstone_dashboard/kiosk/supabase_kiosk_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  bool permanent(String? code) => SupabaseKioskRemote.isPermanentPostgrestError(
        PostgrestException(message: 'm', code: code),
      );

  test('raise exception from record_rfid_tap (P0001) is a permanent rejection', () {
    expect(permanent('P0001'), isTrue);
  });

  test('permission and data errors are permanent', () {
    expect(permanent('42501'), isTrue);
    expect(permanent('22P02'), isTrue);
    expect(permanent('23503'), isTrue);
  });

  test('server/gateway errors are transient', () {
    expect(permanent('500'), isFalse);
    expect(permanent('502'), isFalse);
    expect(permanent('503'), isFalse);
    expect(permanent('504'), isFalse);
    expect(permanent(null), isFalse);
  });

  test('every PGRST code is transient (JWT expiry, stale schema cache, ...)', () {
    for (final c in [
      'PGRST000', 'PGRST002', 'PGRST116', 'PGRST202', 'PGRST301', 'PGRST302', 'PGRST303',
    ]) {
      expect(permanent(c), isFalse, reason: c);
    }
  });

  group('fetchAllKeyset', () {
    // Fake table of ids "000".."N-1", ordered by id, keyset-paged.
    Future<List<String>> Function(String?) table(int total, List<String?> calls,
        {int pageSize = 500}) {
      final ids = [for (var i = 0; i < total; i++) i.toString().padLeft(5, '0')];
      return (after) async {
        calls.add(after);
        return ids.where((i) => after == null || i.compareTo(after) > 0).take(pageSize).toList();
      };
    }

    test('collects several pages in order', () async {
      final calls = <String?>[];
      final all = await fetchAllKeyset<String>(table(1250, calls), (s) => s);
      expect(all.length, 1250);
      expect(all.first, '00000');
      expect(all.last, '01249');
      expect(calls.length, 3);
    });

    test('an exact multiple of the page size ends on an empty page', () async {
      final calls = <String?>[];
      final all = await fetchAllKeyset<String>(table(1000, calls), (s) => s);
      expect(all.length, 1000);
      expect(calls.length, 3);
    });

    test('empty source returns an empty list after one call', () async {
      final calls = <String?>[];
      expect(await fetchAllKeyset<String>(table(0, calls), (s) => s), isEmpty);
      expect(calls.length, 1);
    });

    test('stops on a short page', () async {
      final calls = <String?>[];
      final all = await fetchAllKeyset<String>(table(510, calls), (s) => s);
      expect(all.length, 510);
      expect(calls.length, 2);
    });

    test('duplicate ids across pages are collapsed to one', () async {
      final pages = [
        ['a', 'b', 'c'],
        ['c', 'd', 'e'],
        ['f'],
      ];
      var i = 0;
      final all = await fetchAllKeyset<String>(
        (after) async => pages[i++],
        (s) => s,
        pageSize: 3,
      );
      expect(all, ['a', 'b', 'c', 'd', 'e', 'f']);
    });

    test('no infinite loop when a page keeps returning the same rows', () async {
      var calls = 0;
      final all = await fetchAllKeyset<String>(
        (after) async {
          calls++;
          return ['a', 'b', 'c'];
        },
        (s) => s,
        pageSize: 3,
      );
      expect(all, ['a', 'b', 'c']);
      expect(calls, 2);
    });
  });
}
