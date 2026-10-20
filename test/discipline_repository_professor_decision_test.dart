import 'dart:convert';
import 'dart:io';

import 'package:capstone_dashboard/data/discipline_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serves `student_violations` over a real local socket. When
/// [hasDecisionColumns] is false it answers any select naming
/// `professor_decision` the way PostgREST does for a missing column.
class _FakeDb {
  late final HttpServer _server;
  bool hasDecisionColumns = true;
  final selects = <String>[];

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final select = req.uri.queryParameters['select'] ?? '';
      selects.add(select);
      req.response.headers.contentType = ContentType.json;
      if (select == 'student_id') {
        req.response.write(jsonEncode([
          {'student_id': 's1'},
          {'student_id': 's1'},
        ]));
      } else if (!hasDecisionColumns && select.contains('professor_decision')) {
        req.response.statusCode = 400;
        req.response.write(jsonEncode({
          'code': '42703',
          'message': 'column student_violations.professor_decision does not exist',
        }));
      } else {
        req.response.write(jsonEncode([_row(withDecision: hasDecisionColumns)]));
      }
      await req.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);

  Map<String, dynamic> _row({required bool withDecision}) => {
        'id': 'v1',
        'student_id': 's1',
        'is_escalated': false,
        'status': 'Pending',
        'created_at': '2026-10-01T08:00:00Z',
        'students': {
          'student_number': '2024-0001',
          'profiles': {'first_name': 'Jane', 'last_name': 'Doe'},
          'sections': {'name': 'BSIT 3-A'},
        },
        'handbook_offenses': {'description': 'Improper uniform', 'category': 'Minor'},
        'profiles': {'first_name': 'Kiosk', 'last_name': 'System'},
        'professor': {'first_name': 'Ana', 'last_name': 'Cruz'},
        if (withDecision) ...{
          'professor_id': 'p1',
          'reported_by': 'kiosk',
          'professor_decision': 'Denied',
          'professor_decision_note': 'Not in my class',
        },
      };
}

void main() {
  late _FakeDb db;
  late SupabaseClient client;

  setUp(() async {
    db = _FakeDb();
    await db.start();
    client = SupabaseClient(db.url, 'anon-key');
  });

  tearDown(() async {
    await client.dispose();
    await db.stop();
  });

  test('the professor\'s decision and note reach the case model', () async {
    final cases = await DisciplineRepository(client).fetchActiveViolations();
    expect(cases.single.professorName, 'Ana Cruz');
    expect(cases.single.professorDecision, 'Denied');
    expect(cases.single.professorDecisionNote, 'Not in my class');
    expect(cases.single.professorFiled, isFalse);
  });

  test('a database without the decision columns still loads the list',
      () async {
    db.hasDecisionColumns = false;
    final cases = await DisciplineRepository(client).fetchActiveViolations();

    expect(cases.single.studentName, 'Jane Doe');
    expect(cases.single.professorName, 'Ana Cruz');
    expect(cases.single.professorDecision, isNull); // reads as "awaiting"
    // It tried the new columns first, then retried without them.
    final caseSelects = db.selects.where((s) => s != 'student_id').toList();
    expect(caseSelects.first, contains('professor_decision'));
    expect(caseSelects.last, isNot(contains('professor_decision')));
  });
}
