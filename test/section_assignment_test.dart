import 'package:capstone_dashboard/data/enrollment_import_repository.dart';
import 'package:capstone_dashboard/data/enrollment_import_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

// Plain tests only: this talks to a real local socket.
void main() {
  late RecordingServer server;
  late SupabaseClient client;

  /// Answers the queries assignSection makes. [sections] are the rows for the
  /// program/year; [counts] is how many students sit in each section id.
  void serve({
    required List<Map<String, dynamic>> sections,
    Map<String, int> counts = const {},
  }) {
    server.respond = (r) {
      if (r.method == 'POST' && r.path.endsWith('/sections')) {
        return (201, {'id': 'new-section'});
      }
      if (r.path.endsWith('/sections')) {
        // createSection asks for names only; the candidate fetch for more.
        return (200, sections);
      }
      if (r.path.endsWith('/students')) {
        return (200, [
          for (final e in counts.entries)
            for (var i = 0; i < e.value; i++) {'section_id': e.key},
        ]);
      }
      return (200, []);
    };
  }

  Map<String, dynamic> section(String id, String name) => {
        'id': id,
        'name': name,
        'program': 'BS Information Technology',
      };

  setUp(() async {
    server = RecordingServer();
    await server.start();
    client = SupabaseClient(server.url, 'anon-key');
  });
  tearDown(() async {
    await client.dispose();
    await server.stop();
  });

  test('picks the least-full existing section', () async {
    serve(
      sections: [section('a', 'BSIT 1A'), section('b', 'BSIT 1B')],
      counts: {'a': 20, 'b': 5},
    );
    final chosen = await EnrollmentImportRepository(client)
        .assignSection(course: 'BS Information Technology', yearLevel: 1);
    expect(chosen.id, 'b');
    expect(chosen.name, 'BSIT 1B');
  });

  test('opens the next section when every one is at the cap', () async {
    serve(
      sections: [section('a', 'BSIT 1A')],
      counts: {'a': kSectionCapTarget},
    );
    final chosen = await EnrollmentImportRepository(client)
        .assignSection(course: 'BS Information Technology', yearLevel: 1);
    expect(chosen.id, 'new-section');
    final created = server.requests.lastWhere(
        (r) => r.method == 'POST' && r.path.endsWith('/sections'));
    expect(created.json['name'], 'BSIT 1B');
    expect(created.json['year_level'], 1);
  });

  test('opens the first section when none exists yet', () async {
    serve(sections: const []);
    final chosen = await EnrollmentImportRepository(client)
        .assignSection(course: 'BS Information Technology', yearLevel: 2);
    expect(chosen.id, 'new-section');
    final created = server.requests.lastWhere(
        (r) => r.method == 'POST' && r.path.endsWith('/sections'));
    expect(created.json['name'], 'BSIT 2A');
  });

  test('a section just below the cap is still used', () async {
    serve(
      sections: [section('a', 'BSIT 1A')],
      counts: {'a': kSectionCapTarget - 1},
    );
    final chosen = await EnrollmentImportRepository(client)
        .assignSection(course: 'BS Information Technology', yearLevel: 1);
    expect(chosen.id, 'a');
    expect(server.requests.where((r) => r.method == 'POST'), isEmpty);
  });
}
