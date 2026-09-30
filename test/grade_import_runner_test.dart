import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:capstone_dashboard/data/grade_import/grade_import_row.dart';
import 'package:capstone_dashboard/data/grade_import_repository.dart';
import 'package:capstone_dashboard/data/grade_import_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _dummyClient() =>
    SupabaseClient('https://example.invalid', 'anon-key');

/// Fakes just enough of [GradeImportRepository] to drive [GradeImportRunner]
/// without a real Supabase project — matches
/// _FakeEnrollmentImportRepository's own convention in
/// enrollment_import_runner_test.dart.
class _FakeGradeImportRepository extends GradeImportRepository {
  _FakeGradeImportRepository() : super(_dummyClient());

  final calls = <({GradeImportRow row, String schoolYear, String term})>[];
  final unknownStudentNumbers = <String>{};
  String? errorForStudentNumber;

  @override
  Future<bool> upsertGpaRecord(
    GradeImportRow row, {
    required String schoolYear,
    required String term,
  }) async {
    if (row.studentNumber == errorForStudentNumber) {
      throw StateError('Could not write a GPA record for ${row.studentNumber}.');
    }
    calls.add((row: row, schoolYear: schoolYear, term: term));
    return !unknownStudentNumbers.contains(row.studentNumber);
  }
}

Uint8List _buildXlsx(String sheetXml) {
  final archive = Archive();
  archive.addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheetXml)));
  return ZipEncoder().encodeBytes(archive);
}

/// Two students' worth of the real export's fixed column layout (see
/// grade_file_parser.dart's own doc comment for the column index map):
/// A=Student ID, B=First Name, E=Last Name, L=Transfer Units,
/// M=No of Failed Courses, N=Units Taken (cumulative), P=GPA (cumulative),
/// R=Units Taken (current term), W=GPA (current term).
const _sheetXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="inlineStr"><is><t>SY &amp; Term:</t></is></c>
      <c r="C1" t="inlineStr"><is><t>2025-2026/2nd Term</t></is></c>
    </row>
    <row r="2">
      <c r="A2" t="inlineStr"><is><t>Student ID</t></is></c>
      <c r="B2" t="inlineStr"><is><t>First Name</t></is></c>
      <c r="E2" t="inlineStr"><is><t>Last Name</t></is></c>
      <c r="L2" t="inlineStr"><is><t>Transfer Units</t></is></c>
      <c r="M2" t="inlineStr"><is><t>No of Failed Courses</t></is></c>
      <c r="N2" t="inlineStr"><is><t>Units Taken</t></is></c>
      <c r="P2" t="inlineStr"><is><t>GPA</t></is></c>
      <c r="R2" t="inlineStr"><is><t>Units Taken</t></is></c>
      <c r="W2" t="inlineStr"><is><t>GPA</t></is></c>
    </row>
    <row r="3">
      <c r="A3" t="inlineStr"><is><t>2026-0001</t></is></c>
      <c r="B3" t="inlineStr"><is><t>Juan</t></is></c>
      <c r="E3" t="inlineStr"><is><t>Dela Cruz</t></is></c>
      <c r="L3" t="inlineStr"><is><t>0.000</t></is></c>
      <c r="M3" t="inlineStr"><is><t>0</t></is></c>
      <c r="N3" t="inlineStr"><is><t>21.000</t></is></c>
      <c r="P3" t="inlineStr"><is><t>1.500</t></is></c>
      <c r="R3" t="inlineStr"><is><t>6.000</t></is></c>
      <c r="W3" t="inlineStr"><is><t>1.250</t></is></c>
    </row>
    <row r="4">
      <c r="A4" t="inlineStr"><is><t>2026-0002</t></is></c>
      <c r="B4" t="inlineStr"><is><t>Pedro</t></is></c>
      <c r="E4" t="inlineStr"><is><t>Santos</t></is></c>
      <c r="L4" t="inlineStr"><is><t>0.000</t></is></c>
      <c r="M4" t="inlineStr"><is><t>1</t></is></c>
      <c r="N4" t="inlineStr"><is><t>21.000</t></is></c>
      <c r="P4" t="inlineStr"><is><t>1.800</t></is></c>
      <c r="R4" t="inlineStr"><is><t>6.000</t></is></c>
      <c r="W4" t="inlineStr"><is><t>1.600</t></is></c>
    </row>
  </sheetData>
</worksheet>
''';

void main() {
  test('imports every row, tagging each with the file\'s shared school year/term',
      () async {
    final repo = _FakeGradeImportRepository();
    final runner = GradeImportRunner(repo);

    final summary = await runner.run(xlsxBytes: _buildXlsx(_sheetXml));

    expect(summary.schoolYear, '2025-2026');
    expect(summary.term, '2nd Term');
    expect(summary.imported, 2);
    expect(summary.skipped, 0);
    expect(summary.errors, isEmpty);

    expect(repo.calls, hasLength(2));
    expect(repo.calls[0].row.studentNumber, '2026-0001');
    expect(repo.calls[0].row.cumulativeGpa, 1.500);
    expect(repo.calls[0].row.currentTermGpa, 1.250);
    expect(repo.calls[0].schoolYear, '2025-2026');
    expect(repo.calls[0].term, '2nd Term');
    expect(repo.calls[1].row.failedCoursesCount, 1);
  });

  test('counts a row with no matching student yet as skipped, not an error',
      () async {
    final repo = _FakeGradeImportRepository()
      ..unknownStudentNumbers.add('2026-0002');
    final runner = GradeImportRunner(repo);

    final summary = await runner.run(xlsxBytes: _buildXlsx(_sheetXml));

    expect(summary.imported, 1);
    expect(summary.skipped, 1);
    expect(summary.errors, isEmpty);
  });

  test('a row that fails to commit is reported as an error without aborting the whole import',
      () async {
    final repo = _FakeGradeImportRepository()
      ..errorForStudentNumber = '2026-0001';
    final runner = GradeImportRunner(repo);

    final summary = await runner.run(xlsxBytes: _buildXlsx(_sheetXml));

    expect(summary.imported, 1);
    expect(summary.errors, hasLength(1));
    expect(summary.errors.single, contains('2026-0001'));
  });

  test('throws when the file has no recognizable SY & Term / Student ID rows',
      () async {
    final repo = _FakeGradeImportRepository();
    final runner = GradeImportRunner(repo);
    final bytes = _buildXlsx('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>Not a grade file</t></is></c></row>
  </sheetData>
</worksheet>
''');

    expect(
      () => runner.run(xlsxBytes: bytes),
      throwsA(isA<GradeImportException>()),
    );
  });
}
