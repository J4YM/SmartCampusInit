import 'package:capstone_dashboard/data/parent_portal_repository.dart';
import 'package:capstone_dashboard/data/student_portal_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

void main() {
  late RecordingServer server;
  late SupabaseClient client;

  setUp(() async {
    server = RecordingServer();
    server.respond = (r) => r.path.endsWith('/rest/v1/missed_tap_outs')
        ? (200, [
            {'school_day': '2026-10-20'},
            {'school_day': '2026-10-22'},
          ])
        : null;
    await server.start();
    client = SupabaseClient(server.url, 'anon-key');
  });

  tearDown(() async {
    await client.dispose();
    await server.stop();
  });

  final from = DateTime(2026, 10, 1);
  final to = DateTime(2026, 10, 31);

  test('the student reads the days they did not tap out', () async {
    final days = await StudentPortalRepository(client)
        .fetchMissedTapOutDays('s1', from: from, to: to);

    expect(days, {DateTime(2026, 10, 20), DateTime(2026, 10, 22)});
    final q = server.requestTo('/rest/v1/missed_tap_outs').uri.queryParameters;
    expect(q['student_id'], 'eq.s1');
    expect(q['school_day'], isNotNull);
  });

  test('the parent reads their child\'s days the same way', () async {
    final days = await ParentPortalRepository(client)
        .fetchMissedTapOutDays('s1', from: from, to: to);

    expect(days, {DateTime(2026, 10, 20), DateTime(2026, 10, 22)});
  });

  test('a table that is not migrated yet reads as no days', () async {
    server.respond = (r) => (404, {'code': '42P01', 'message': 'no table'});
    expect(
        await StudentPortalRepository(client)
            .fetchMissedTapOutDays('s1', from: from, to: to),
        isEmpty);
  });
}
