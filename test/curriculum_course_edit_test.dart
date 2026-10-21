import 'dart:convert';
import 'dart:io';

import 'package:capstone_dashboard/data/curriculum_import_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory PostgREST stand-in for `subjects` and `curriculum_entries`
/// (insert / upsert / patch / delete / select, plus the unique constraints the
/// real tables have), reached over a real local socket.
class _FakeDb {
  late final HttpServer _server;
  final subjects = <String, Map<String, dynamic>>{}; // id -> row
  final entries = <String, Map<String, dynamic>>{}; // id -> row
  var _n = 0;

  /// Makes writes to this table look like row-level security filtered them
  /// all out (0 rows affected, no error), as PostgREST does.
  final blockedTables = <String>{};

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  String? _eq(HttpRequest r, String col) {
    final v = r.uri.queryParameters[col];
    return (v != null && v.startsWith('eq.')) ? v.substring(3) : null;
  }

  Future<void> _handle(HttpRequest req) async {
    final table = req.uri.pathSegments.last;
    final body = await utf8.decodeStream(req);
    final wantsObject =
        (req.headers.value('accept') ?? '').contains('vnd.pgrst.object');
    final wantsRows =
        (req.headers.value('prefer') ?? '').contains('return=representation');
    final rows = table == 'subjects' ? subjects : entries;
    var status = 200;
    Object? out;

    Map<String, dynamic>? clashingEntry(Map<String, dynamic> e, {String? except}) {
      for (final other in entries.values) {
        if (other['id'] != except &&
            other['program'] == e['program'] &&
            other['subject_id'] == e['subject_id']) {
          return other;
        }
      }
      return null;
    }

    Object respond(List<Map<String, dynamic>> r) =>
        wantsObject ? (r.isEmpty ? <String, dynamic>{} : r.first) : r;

    switch (req.method) {
      case 'POST':
        final incoming = jsonDecode(body);
        final list = incoming is List
            ? incoming.cast<Map<String, dynamic>>()
            : [incoming as Map<String, dynamic>];
        final written = <Map<String, dynamic>>[];
        for (final r in list) {
          if (table == 'subjects') {
            final existing = subjects.values
                .where((s) => s['code'] == r['code'])
                .firstOrNull;
            if (existing != null) {
              existing.addAll(r);
              written.add(existing);
            } else {
              final row = {'id': 's${++_n}', ...r};
              subjects[row['id'] as String] = row;
              written.add(row);
            }
          } else {
            final row = {'id': 'e${++_n}', ...r};
            if (clashingEntry(row) != null) {
              status = 409;
              out = {'code': '23505', 'message': 'duplicate key'};
              break;
            }
            entries[row['id'] as String] = row;
            written.add(row);
          }
        }
        if (status == 200) {
          status = 201;
          out = wantsRows ? respond(written) : null;
        }
      case 'PATCH':
        final id = _eq(req, 'id');
        final target = rows[id];
        if (blockedTables.contains(table) || target == null) {
          out = <Map<String, dynamic>>[];
          break;
        }
        final patch = jsonDecode(body) as Map<String, dynamic>;
        final merged = {...target, ...patch};
        if (table == 'subjects' &&
            subjects.values.any((s) => s['id'] != id && s['code'] == merged['code'])) {
          status = 409;
          out = {'code': '23505', 'message': 'duplicate key'};
          break;
        }
        if (table == 'curriculum_entries' && clashingEntry(merged, except: id) != null) {
          status = 409;
          out = {'code': '23505', 'message': 'duplicate key'};
          break;
        }
        target.addAll(patch);
        out = respond([target]);
      case 'DELETE':
        final id = _eq(req, 'id');
        if (blockedTables.contains(table) || rows[id] == null) {
          out = <Map<String, dynamic>>[];
          break;
        }
        out = respond([rows.remove(id)!]);
      case 'GET':
        var found = rows.values.toList();
        for (final col in ['program', 'subject_id', 'id', 'code']) {
          final v = _eq(req, col);
          if (v != null) found = found.where((r) => r[col] == v).toList();
        }
        if (table == 'curriculum_entries') {
          found = [
            for (final e in found) {...e, 'subjects': subjects[e['subject_id']]},
          ];
        }
        if (wantsObject && found.isEmpty) {
          status = 406;
          out = {'code': 'PGRST116', 'message': 'no rows'};
        } else {
          out = respond(found);
        }
    }

    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json;
    if (out != null) req.response.write(jsonEncode(out));
    await req.response.close();
  }
}

void main() {
  late _FakeDb db;
  late SupabaseClient client;
  late CurriculumImportRunner runner;

  setUp(() async {
    db = _FakeDb();
    await db.start();
    client = SupabaseClient(db.url, 'anon-key');
    runner = CurriculumImportRunner(client);
  });

  tearDown(() async {
    await client.dispose();
    await db.stop();
  });

  Future<void> add(String program, String code,
          {String title = 'Intro', int year = 1, int term = 1, String? prereq}) =>
      runner.saveCourse(
        program: program,
        yearLevel: year,
        term: term,
        code: code,
        title: title,
        units: 3,
        prerequisites: prereq,
      );

  group('CurriculumImportRunner course editing', () {
    test('adding a course creates the subject and its placement', () async {
      await add('BSIT', 'cite 1003', title: 'Computer Programming 1', prereq: ' ');

      expect(db.subjects.values.single,
          containsPair('code', 'CITE1003')); // normalized like an upload
      expect(db.subjects.values.single['title'], 'Computer Programming 1');
      final placement = db.entries.values.single;
      expect([placement['program'], placement['year_level'], placement['term']],
          ['BSIT', 1, 1]);
      expect(placement['prerequisites'], isNull); // blank -> null

      final view = await runner.fetchCurriculum();
      expect(view.single.code, 'CITE1003');
      expect(view.single.id, placement['id']);
      expect(view.single.subjectId, db.subjects.keys.single);
    });

    test('adding a code another program already has reuses the subject',
        () async {
      await add('BSIT', 'GEDC1002');
      await add('BSTM', 'GEDC1002', year: 2);
      expect(db.subjects, hasLength(1));
      expect(db.entries, hasLength(2));
    });

    test('adding a course the program already lists is refused', () async {
      await add('BSIT', 'CITE1003');
      await expectLater(
        add('BSIT', 'CITE1003'),
        throwsA(isA<CurriculumImportException>()
            .having((e) => e.message, 'message', contains('already has'))),
      );
      expect(db.entries, hasLength(1));
    });

    test('editing changes the subject and the placement', () async {
      await add('BSIT', 'CITE1003', title: 'Old title');
      final view = (await runner.fetchCurriculum()).single;

      await runner.saveCourse(
        entryId: view.id,
        subjectId: view.subjectId,
        program: 'BS Information Technology',
        yearLevel: 2,
        term: 2,
        code: 'cite1010',
        title: 'New title',
        units: 4,
        prerequisites: 'CITE1004',
      );

      final subject = db.subjects.values.single;
      expect([subject['code'], subject['title'], subject['units']],
          ['CITE1010', 'New title', 4]);
      final placement = db.entries.values.single;
      expect(placement['program'], 'BS Information Technology');
      expect([placement['year_level'], placement['term']], [2, 2]);
      expect(placement['prerequisites'], 'CITE1004');
    });

    test('editing to a code another subject uses gives a readable error',
        () async {
      await add('BSIT', 'AAA1');
      await add('BSIT', 'BBB2');
      final b = (await runner.fetchCurriculum()).firstWhere((e) => e.code == 'BBB2');

      await expectLater(
        runner.saveCourse(
          entryId: b.id,
          subjectId: b.subjectId,
          program: 'BSIT',
          yearLevel: 1,
          term: 1,
          code: 'AAA1',
          title: 'x',
          units: 3,
        ),
        throwsA(isA<CurriculumImportException>()
            .having((e) => e.message, 'message', contains('AAA1'))),
      );
    });

    test('an edit blocked by row-level security is reported, not swallowed',
        () async {
      await add('BSIT', 'AAA1');
      final a = (await runner.fetchCurriculum()).single;
      db.blockedTables.add('subjects');
      await expectLater(
        runner.saveCourse(
          entryId: a.id,
          subjectId: a.subjectId,
          program: 'BSIT',
          yearLevel: 1,
          term: 1,
          code: 'AAA1',
          title: 'Changed',
          units: 3,
        ),
        throwsA(isA<CurriculumImportException>()),
      );
    });

    test('deleting removes the placement but keeps the subject', () async {
      await add('BSIT', 'AAA1');
      final a = (await runner.fetchCurriculum()).single;

      await runner.deleteEntry(a.id!);

      expect(db.entries, isEmpty);
      expect(db.subjects, hasLength(1)); // class schedules may still use it
      expect(await runner.fetchCurriculum(), isEmpty);
    });

    test('a delete blocked by row-level security is reported', () async {
      await add('BSIT', 'AAA1');
      final a = (await runner.fetchCurriculum()).single;
      db.blockedTables.add('curriculum_entries');
      await expectLater(
          runner.deleteEntry(a.id!), throwsA(isA<CurriculumImportException>()));
      expect(db.entries, hasLength(1));
    });
  });
}
