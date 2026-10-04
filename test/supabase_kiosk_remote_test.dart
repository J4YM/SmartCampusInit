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

  group('fetchAllPages', () {
    Future<({List<int> items, int totalCount})> Function(int) source(
      int total,
      int pageSize,
      List<int> calls,
    ) {
      return (page) async {
        calls.add(page);
        final start = (page - 1) * pageSize;
        final end = (start + pageSize).clamp(0, total);
        return (
          items: [for (var i = start; i < end; i++) i],
          totalCount: total,
        );
      };
    }

    test('collects several pages in order', () async {
      final calls = <int>[];
      final all = await fetchAllPages<int>(source(1250, 500, calls));
      expect(all.length, 1250);
      expect(all.first, 0);
      expect(all.last, 1249);
      expect(calls, [1, 2, 3]);
    });

    test('an exact multiple of the page size stops via totalCount', () async {
      final calls = <int>[];
      final all = await fetchAllPages<int>(source(1000, 500, calls));
      expect(all.length, 1000);
      expect(calls, [1, 2]);
    });

    test('empty source returns an empty list after one call', () async {
      final calls = <int>[];
      expect(await fetchAllPages<int>(source(0, 500, calls)), isEmpty);
      expect(calls, [1]);
    });

    test('stops on a short page even if totalCount is larger', () async {
      final calls = <int>[];
      final all = await fetchAllPages<int>((page) async {
        calls.add(page);
        return (items: page == 1 ? List.filled(500, 1) : List.filled(10, 1), totalCount: 99999);
      });
      expect(all.length, 510);
      expect(calls, [1, 2]);
    });

    test('stops at totalCount even when every page is full', () async {
      final calls = <int>[];
      final all = await fetchAllPages<int>((page) async {
        calls.add(page);
        return (items: List.filled(500, 1), totalCount: 1000);
      });
      expect(all.length, 1000);
      expect(calls, [1, 2]);
    });
  });
}
