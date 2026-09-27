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

  final calls = <({EnrollmentImportRow row, String sectionId, String course, int yearLevel})>[];
  final existingStudentNumbers = <String>{};
  String? errorForStudentNumber;

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
    </row>
  </sheetData>
</worksheet>
''';

void main() {
  test('creates new students and counts them, falling back to the chosen '
      'section\'s own program/year when a row leaves Program/Level blank',
      () async {
    final repo = _FakeEnrollmentImportRepository();
    final runner = EnrollmentImportRunner(repo);

    final summary = await runner.run(
      xlsxBytes: _buildXlsx(_sheetXml),
      sectionId: 'section-1',
      sectionProgram: 'BSIT',
      sectionYearLevel: 3,
    );

    expect(summary.created, 2);
    expect(summary.updated, 0);
    expect(summary.errors, isEmpty);
    expect(repo.calls, hasLength(2));

    // Row 1 supplied its own Program/Level — used as-is.
    expect(repo.calls[0].course, 'BSIT');
    expect(repo.calls[0].yearLevel, 1);
    expect(repo.calls[0].sectionId, 'section-1');

    // Row 2 left Program/Level blank — falls back to the chosen section.
    expect(repo.calls[1].course, 'BSIT');
    expect(repo.calls[1].yearLevel, 3);
  });

  test('counts an already-existing student number as updated, not created', () async {
    final repo = _FakeEnrollmentImportRepository()
      ..existingStudentNumbers.add('2026-0001');
    final runner = EnrollmentImportRunner(repo);

    final summary = await runner.run(
      xlsxBytes: _buildXlsx(_sheetXml),
      sectionId: 'section-1',
      sectionProgram: 'BSIT',
      sectionYearLevel: 3,
    );

    expect(summary.created, 1);
    expect(summary.updated, 1);
  });

  test('a row that fails to commit is reported as an error without aborting the whole import',
      () async {
    final repo = _FakeEnrollmentImportRepository()
      ..errorForStudentNumber = '2026-0001';
    final runner = EnrollmentImportRunner(repo);

    final summary = await runner.run(
      xlsxBytes: _buildXlsx(_sheetXml),
      sectionId: 'section-1',
      sectionProgram: 'BSIT',
      sectionYearLevel: 3,
    );

    expect(summary.created, 1);
    expect(summary.errors, hasLength(1));
    expect(summary.errors.single, contains('2026-0001'));
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
      () => runner.run(
        xlsxBytes: bytes,
        sectionId: 'section-1',
        sectionProgram: 'BSIT',
        sectionYearLevel: 3,
      ),
      throwsA(isA<EnrollmentImportException>()),
    );
  });
}
