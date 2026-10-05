import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:capstone_dashboard/data/enrollment_import/enrollment_import_row.dart';
import 'package:capstone_dashboard/data/enrollment_import_repository.dart';
import 'package:capstone_dashboard/data/enrollment_import_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _dummyClient() =>
    SupabaseClient('https://example.invalid', 'anon-key');

/// Fakes just enough of [EnrollmentImportRepository] to drive
/// [EnrollmentImportRunner] without a real Supabase project — matches
/// _FakeScheduleImportRepository's own convention in
/// schedule_import_runner_test.dart.
class _FakeEnrollmentImportRepository extends EnrollmentImportRepository {
  _FakeEnrollmentImportRepository() : super(_dummyClient());

  final Map<String, List<SectionCandidate>> candidatesByProgramLevel = {};
  final calls = <({EnrollmentImportRow row, String sectionId, String course, int yearLevel})>[];
  final existingStudentNumbers = <String>{};
  String? errorForStudentNumber;

  @override
  Future<List<SectionCandidate>> fetchSectionCandidates({
    required String course,
    required int yearLevel,
  }) async {
    return candidatesByProgramLevel['$course::$yearLevel'] ?? [];
  }

  @override
  Future<bool> upsertStudent(
    EnrollmentImportRow row, {
    required String sectionId,
    required String course,
    required int yearLevel,
  }) async {
    if (row.studentNumber == errorForStudentNumber) {
      throw StateError('Could not create an auth identity for ${row.studentNumber}.');
    }
    calls.add((row: row, sectionId: sectionId, course: course, yearLevel: yearLevel));
    return !existingStudentNumbers.contains(row.studentNumber);
  }
}

Uint8List _buildXlsx(String sheetXml) {
  final archive = Archive();
  archive.addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheetXml)));
  return ZipEncoder().encodeBytes(archive);
}

/// Two students sharing Program=BSIT/Level=1, plus a third row with no
/// Program/Level at all (to exercise the "can't place, no fallback"
/// error path — there's no longer a batch-level chosen section to fall
/// back to).
const _sheetXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="inlineStr"><is><t>Student ID</t></is></c>
      <c r="B1" t="inlineStr"><is><t>Last Name</t></is></c>
      <c r="C1" t="inlineStr"><is><t>First Name</t></is></c>
      <c r="D1" t="inlineStr"><is><t>Program</t></is></c>
      <c r="E1" t="inlineStr"><is><t>Level</t></is></c>
    </row>
    <row r="2">
      <c r="A2" t="inlineStr"><is><t>2026-0001</t></is></c>
      <c r="B2" t="inlineStr"><is><t>Dela Cruz</t></is></c>
      <c r="C2" t="inlineStr"><is><t>Juan</t></is></c>
      <c r="D2" t="inlineStr"><is><t>BSIT</t></is></c>
      <c r="E2" t="inlineStr"><is><t>1</t></is></c>
    </row>
    <row r="3">
      <c r="A3" t="inlineStr"><is><t>2026-0002</t></is></c>
      <c r="B3" t="inlineStr"><is><t>Santos</t></is></c>
      <c r="C3" t="inlineStr"><is><t>Pedro</t></is></c>
      <c r="D3" t="inlineStr"><is><t>BSIT</t></is></c>
      <c r="E3" t="inlineStr"><is><t>1</t></is></c>
    </row>
    <row r="4">
      <c r="A4" t="inlineStr"><is><t>2026-0003</t></is></c>
      <c r="B4" t="inlineStr"><is><t>Reyes</t></is></c>
      <c r="C4" t="inlineStr"><is><t>Ana</t></is></c>
    </row>
  </sheetData>
</worksheet>
''';

void main() {
  test('distributes students across the least-full matching section, '
      'updating the count within the same run — and errors a row with no '
      'Program/Level at all (no batch-level section to fall back to)',
      () async {
    final repo = _FakeEnrollmentImportRepository();
    repo.candidatesByProgramLevel['BSIT::1'] = [
      SectionCandidate(id: 'sec-a', name: 'BSIT-1A', currentCount: 5),
      SectionCandidate(id: 'sec-b', name: 'BSIT-1B', currentCount: 3),
    ];
    final runner = EnrollmentImportRunner(repo);

    final summary = await runner.run(xlsxBytes: _buildXlsx(_sheetXml));

    expect(summary.created, 2);
    expect(summary.errors, hasLength(1));
    expect(summary.errors.single, contains('2026-0003'));
    expect(summary.errors.single, contains('Program/Level'));

    expect(repo.calls, hasLength(2));
    // Both go to BSIT-1B: it started less-full (3 < 5), and stays
    // less-full after the first assignment bumps it to 4.
    expect(repo.calls[0].sectionId, 'sec-b');
    expect(repo.calls[1].sectionId, 'sec-b');
  });

  test('counts an already-existing student number as updated, not created', () async {
    final repo = _FakeEnrollmentImportRepository()
      ..candidatesByProgramLevel['BSIT::1'] = [
        SectionCandidate(id: 'sec-a', name: 'BSIT-1A', currentCount: 0),
      ]
      ..existingStudentNumbers.add('2026-0001');
    final runner = EnrollmentImportRunner(repo);

    final summary = await runner.run(xlsxBytes: _buildXlsx(_sheetXml));

    expect(summary.created, 1);
    expect(summary.updated, 1);
  });

  test('a row that fails to commit is reported as an error without aborting the whole import',
      () async {
    final repo = _FakeEnrollmentImportRepository()
      ..candidatesByProgramLevel['BSIT::1'] = [
        SectionCandidate(id: 'sec-a', name: 'BSIT-1A', currentCount: 0),
      ]
      ..errorForStudentNumber = '2026-0001';
    final runner = EnrollmentImportRunner(repo);

    final summary = await runner.run(xlsxBytes: _buildXlsx(_sheetXml));

    expect(summary.created, 1);
    // The auth-identity failure plus the missing-Program/Level row.
    expect(summary.errors, hasLength(2));
    expect(summary.errors.any((e) => e.contains('2026-0001')), isTrue);
  });

  test('errors every row whose program/level has no section at all', () async {
    final repo = _FakeEnrollmentImportRepository(); // no candidates registered
    final runner = EnrollmentImportRunner(repo);

    final summary = await runner.run(xlsxBytes: _buildXlsx(_sheetXml));

    expect(summary.created, 0);
    expect(summary.errors, hasLength(3));
    expect(summary.errors.any((e) => e.contains('No section exists')), isTrue);
  });

  test('assigns anyway (with a cap warning) once every matching section is '
      'already at or past the target cap', () async {
    final repo = _FakeEnrollmentImportRepository()
      ..candidatesByProgramLevel['BSIT::1'] = [
        SectionCandidate(id: 'sec-a', name: 'BSIT-1A', currentCount: kSectionCapTarget),
      ];
    final runner = EnrollmentImportRunner(repo);

    final summary = await runner.run(xlsxBytes: _buildXlsx(_sheetXml));

    expect(repo.calls.first.sectionId, 'sec-a'); // still assigned, not blocked
    expect(summary.capWarnings, hasLength(2)); // both BSIT/1 rows warn
    expect(summary.capWarnings.first, contains('BSIT-1A'));
  });

  test('throws when the file has no recognizable Student ID rows', () async {
    final repo = _FakeEnrollmentImportRepository();
    final runner = EnrollmentImportRunner(repo);
    final bytes = _buildXlsx('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>Not an enrollment file</t></is></c></row>
  </sheetData>
</worksheet>
''');

    expect(
      () => runner.run(xlsxBytes: bytes),
      throwsA(isA<EnrollmentImportException>()),
    );
  });
}
