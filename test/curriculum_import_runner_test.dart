import 'dart:convert';
import 'dart:io';

import 'package:capstone_dashboard/data/curriculum_import/curriculum_file_parser.dart';
import 'package:capstone_dashboard/data/curriculum_import_runner.dart';
import 'package:capstone_dashboard/data/schedule_import/xlsx_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal in-memory stand-in for the three tables + one RPC the curriculum
/// upload touches, speaking PostgREST over a real local HTTP socket — so the
/// real [CurriculumImportRunner] and real supabase client run end to end
/// without touching any actual database.
class _FakePostgrest {
  late final HttpServer _server;
  final subjectsByCode = <String, Map<String, dynamic>>{};
  final entriesByKey = <String, Map<String, dynamic>>{};
  final requests = <String>[];
  var _nextId = 1;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    final body = await utf8.decodeStream(req);
    requests.add('${req.method} $path');
    Object? out;
    var status = 200;

    if (path == '/rest/v1/program_aliases' && req.method == 'GET') {
      out = [
        {'alias': 'BSIT', 'canonical_program': 'BS Information Technology'},
      ];
    } else if (path == '/rest/v1/subjects' && req.method == 'POST') {
      for (final r in (jsonDecode(body) as List).cast<Map<String, dynamic>>()) {
        final code = r['code'] as String;
        subjectsByCode.update(
          code,
          (old) => {...old, ...r},
          ifAbsent: () => {'id': 'subj-${_nextId++}', ...r},
        );
      }
      status = 201;
      out = null;
    } else if (path == '/rest/v1/subjects' && req.method == 'GET') {
      final inFilter = req.uri.queryParameters['code'] ?? '';
      final wanted = RegExp(r'"?([A-Z0-9]+)"?')
          .allMatches(inFilter.replaceFirst('in.', ''))
          .map((m) => m.group(1)!)
          .toSet();
      out = [
        for (final c in wanted)
          if (subjectsByCode.containsKey(c))
            {'id': subjectsByCode[c]!['id'], 'code': c},
      ];
    } else if (path == '/rest/v1/curriculum_entries' && req.method == 'POST') {
      for (final r in (jsonDecode(body) as List).cast<Map<String, dynamic>>()) {
        entriesByKey['${r['program']}|${r['subject_id']}'] = r;
      }
      status = 201;
      out = null;
    } else if (path == '/rest/v1/curriculum_entries' && req.method == 'GET') {
      final byId = {
        for (final s in subjectsByCode.values) s['id']: s,
      };
      out = [
        for (final e in entriesByKey.values)
          {...e, 'subjects': byId[e['subject_id']]},
      ];
    } else if (path == '/rest/v1/rpc/merge_auto_subjects') {
      out = 0;
    } else {
      status = 404;
      out = {'message': 'unexpected ${req.method} $path'};
    }

    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json;
    if (out != null) req.response.write(jsonEncode(out));
    await req.response.close();
  }
}

void main() {
  const samplePath = 'sample_data/curriculum/curriculum_upload_sample.xlsx';

  test('the sample .xlsx parses to the same 274 courses as the CSV', () {
    final xlsxRows = readFirstSheetRows(File(samplePath).readAsBytesSync());
    final fromXlsx = parseCurriculumRows(xlsxRows)!;
    final fromCsv = parseCurriculumRows(parseCsvText(
      File('sample_data/curriculum/curriculum_upload_template.csv')
          .readAsStringSync(),
    ))!;

    expect(fromXlsx.errors, isEmpty);
    expect(fromXlsx.rows, hasLength(274));
    expect(fromXlsx.rows.map((r) => r.program).toSet(), hasLength(5));
    for (var i = 0; i < fromCsv.rows.length; i++) {
      final a = fromXlsx.rows[i];
      final b = fromCsv.rows[i];
      expect(
        [a.program, a.yearLevel, a.term, a.code, a.title, a.units,
            a.prerequisites],
        [b.program, b.yearLevel, b.term, b.code, b.title, b.units,
            b.prerequisites],
        reason: 'row ${i + 2} differs between xlsx and csv',
      );
    }
    // Electives (year/term 0) survive the round trip.
    expect(fromXlsx.rows.where((r) => r.yearLevel == 0), isNotEmpty);
  });

  group('CurriculumImportRunner uploading the sample .xlsx', () {
    late _FakePostgrest db;
    late SupabaseClient client;

    setUp(() async {
      db = _FakePostgrest();
      await db.start();
      client = SupabaseClient(db.url, 'anon-key');
    });

    tearDown(() async {
      await client.dispose();
      await db.stop();
    });

    test('writes every subject and placement, and is safe to re-upload',
        () async {
      final bytes = File(samplePath).readAsBytesSync();
      final parsed = parseCurriculumRows(readFirstSheetRows(bytes))!;
      final distinctCodes = parsed.rows.map((r) => r.code).toSet().length;
      final distinctPlacements =
          parsed.rows.map((r) => '${r.program}|${r.code}').toSet().length;

      final summary = await CurriculumImportRunner(client)
          .run(bytes: bytes, fileName: 'Curriculum_Upload_Sample.xlsx');

      // ignore: avoid_print
      print('UPLOAD RESULT: ${summary.subjects} subjects, '
          '${summary.placements} placements, programs=${summary.programs}, '
          'skipped rows=${summary.errors.length}');

      expect(summary.errors, isEmpty);
      expect(summary.subjects, distinctCodes);
      expect(summary.placements, distinctPlacements);
      expect(summary.programs, [
        'BS Accounting Information System',
        'BS Business Administration',
        'BS Hospitality Management',
        'BS Information Technology',
        'BS Tourism Management',
      ]);

      // What actually reached the "database".
      expect(db.subjectsByCode, hasLength(distinctCodes));
      expect(db.entriesByKey, hasLength(distinctPlacements));
      expect(db.subjectsByCode['CITE1004']!['title'], 'Introduction to Computing');
      expect(db.subjectsByCode['CITE1004']!['units'], 3);
      expect(db.requests, contains('POST /rest/v1/rpc/merge_auto_subjects'));

      // And the Curriculum tab can read it back.
      final view = await CurriculumImportRunner(client).fetchCurriculum();
      expect(view, hasLength(distinctPlacements));
      final intro = view.firstWhere(
          (e) => e.code == 'CITE1004' && e.program == 'BS Information Technology');
      expect([intro.yearLevel, intro.term, intro.units], [1, 1, 3]);

      // Re-uploading the same file adds nothing (upserts).
      await CurriculumImportRunner(client)
          .run(bytes: bytes, fileName: 'Curriculum_Upload_Sample.xlsx');
      expect(db.subjectsByCode, hasLength(distinctCodes));
      expect(db.entriesByKey, hasLength(distinctPlacements));
    });
  });
}
