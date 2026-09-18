import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:capstone_dashboard/data/registrar_repository.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_file_parser.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';
import 'package:capstone_dashboard/data/schedule_import_repository.dart';
import 'package:capstone_dashboard/data/schedule_import_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _dummyClient() =>
    SupabaseClient('https://example.invalid', 'anon-key');

/// Fakes just enough of [ScheduleImportRepository] to drive
/// [ScheduleImportRunner] without a real Supabase project — a plain
/// subclass overriding every method the runner calls, matching this
/// repo's existing "construct with a dummy client" signature-guard
/// pattern (see e.g. test/registrar_repository_class_sections_test.dart)
/// but going further since this orchestration logic is new and non-trivial.
class _FakeScheduleImportRepository extends ScheduleImportRepository {
  _FakeScheduleImportRepository() : super(_dummyClient());

  final subjectIdsByTitle = <String, String>{};
  final professorIdsByName = <String, String>{};
  final sectionIdsByName = <String, String>{};
  final roomAliases = <String, String>{};
  final resolveSubjectCalls = <String>[];
  final commitCalls = <(String, List<ScheduleImportRow>)>[];
  String? subjectResolutionErrorFor;

  @override
  Future<String> resolveSubjectId({required String title, String? code}) async {
    resolveSubjectCalls.add(title);
    if (title == subjectResolutionErrorFor) {
      throw StateError('No subject found for "$title" and no code was supplied.');
    }
    return subjectIdsByTitle.putIfAbsent(title, () => 'subject-${subjectIdsByTitle.length + 1}');
  }

  @override
  Future<String> resolveProfessorId({String? instructorId, String? fullName}) async {
    final key = fullName ?? instructorId ?? '';
    return professorIdsByName.putIfAbsent(key, () => 'professor-${professorIdsByName.length + 1}');
  }

  @override
  Future<String> resolveSectionId(String rawSectionName) async {
    return sectionIdsByName.putIfAbsent(rawSectionName, () => 'section-${sectionIdsByName.length + 1}');
  }

  @override
  Future<String> resolveRoomCanonicalName(String rawRoomName) async {
    return roomAliases[rawRoomName] ?? rawRoomName;
  }

  @override
  Future<void> commitMeetings({
    required String classSectionId,
    required List<ScheduleImportRow> meetings,
  }) async {
    commitCalls.add((classSectionId, meetings));
  }
}

class _FakeRegistrarRepository extends RegistrarRepository {
  _FakeRegistrarRepository() : super(_dummyClient());

  int nextId = 1;
  final findOrCreateCalls = <Map<String, String>>[];

  @override
  Future<String> findOrCreateClassSection({
    required String subjectId,
    required String sectionId,
    required String professorId,
    required String schoolYear,
    required String term,
  }) async {
    findOrCreateCalls.add({
      'subjectId': subjectId,
      'sectionId': sectionId,
      'professorId': professorId,
      'schoolYear': schoolYear,
      'term': term,
    });
    return 'class-section-${nextId++}';
  }
}

const _cflSheetXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>Confirmation of Faculty Loading</t></is></c></row>
    <row r="2">
      <c r="A2" t="inlineStr"><is><t>Instructor:</t></is></c>
      <c r="B2" t="inlineStr"><is><t>Faculty Member</t></is></c>
    </row>
    <row r="3">
      <c r="A3" t="inlineStr"><is><t>SUBJECT</t></is></c>
      <c r="B3" t="inlineStr"><is><t>Units</t></is></c>
      <c r="C3" t="inlineStr"><is><t>M</t></is></c>
      <c r="D3" t="inlineStr"><is><t>T</t></is></c>
      <c r="E3" t="inlineStr"><is><t>W</t></is></c>
      <c r="F3" t="inlineStr"><is><t>TH</t></is></c>
      <c r="G3" t="inlineStr"><is><t>F</t></is></c>
      <c r="H3" t="inlineStr"><is><t>S</t></is></c>
      <c r="I3" t="inlineStr"><is><t>Room</t></is></c>
      <c r="J3" t="inlineStr"><is><t>Section</t></is></c>
    </row>
    <row r="4">
      <c r="A4" t="inlineStr"><is><t>Human Computer Interaction</t></is></c>
      <c r="J4" t="inlineStr"><is><t>BSIT 2A</t></is></c>
    </row>
    <row r="5">
      <c r="A5" t="inlineStr"><is><t>Lecture</t></is></c>
      <c r="B5" t="inlineStr"><is><t>2</t></is></c>
      <c r="D5" t="inlineStr"><is><t>7:00 - 9:00</t></is></c>
      <c r="I5" t="inlineStr"><is><t>LR 203</t></is></c>
    </row>
    <row r="6">
      <c r="A6" t="inlineStr"><is><t>Laboratory (3 hours)</t></is></c>
      <c r="B6" t="inlineStr"><is><t>1</t></is></c>
      <c r="F6" t="inlineStr"><is><t>7:00 - 10:00</t></is></c>
      <c r="I6" t="inlineStr"><is><t>ComLab 1</t></is></c>
    </row>
  </sheetData>
</worksheet>
''';

Uint8List _buildXlsx(String sheetXml) {
  final archive = Archive();
  archive.addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheetXml)));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('ScheduleImportRunner with a CFL file', () {
    late _FakeScheduleImportRepository scheduleImportRepo;
    late _FakeRegistrarRepository registrarRepo;
    late ScheduleImportRunner runner;

    setUp(() {
      scheduleImportRepo = _FakeScheduleImportRepository();
      registrarRepo = _FakeRegistrarRepository();
      runner = ScheduleImportRunner(
        scheduleImportRepository: scheduleImportRepo,
        registrarRepository: registrarRepo,
      );
    });

    test('detects the format, creates one offering, and commits both meetings', () async {
      final summary = await runner.run(
        xlsxBytes: _buildXlsx(_cflSheetXml),
        schoolYear: '2026-2027',
        term: '1st Semester',
      );

      expect(summary.format, ScheduleFileFormat.facultyLoading);
      expect(summary.offeringsCommitted, 1);
      expect(summary.meetingsCommitted, 2);
      expect(summary.errors, isEmpty);

      expect(registrarRepo.findOrCreateCalls, hasLength(1));
      expect(registrarRepo.findOrCreateCalls.single['schoolYear'], '2026-2027');
      expect(registrarRepo.findOrCreateCalls.single['term'], '1st Semester');

      expect(scheduleImportRepo.commitCalls, hasLength(1));
      final (classSectionId, meetings) = scheduleImportRepo.commitCalls.single;
      expect(classSectionId, 'class-section-1');
      expect(meetings, hasLength(2));
      expect(meetings.map((m) => m.component), containsAll([
        ScheduleComponent.lecture,
        ScheduleComponent.laboratory,
      ]));
    });

    test('resolves the professor by the CFL Instructor: name for both meeting rows', () async {
      await runner.run(
        xlsxBytes: _buildXlsx(_cflSheetXml),
        schoolYear: '2026-2027',
        term: '1st Semester',
      );

      expect(scheduleImportRepo.professorIdsByName.keys, ['Faculty Member']);
    });

    test('an unresolvable subject is reported as an error without aborting the whole import', () async {
      scheduleImportRepo.subjectResolutionErrorFor = 'Human Computer Interaction';

      final summary = await runner.run(
        xlsxBytes: _buildXlsx(_cflSheetXml),
        schoolYear: '2026-2027',
        term: '1st Semester',
      );

      expect(summary.offeringsCommitted, 0);
      expect(summary.errors, hasLength(1));
      expect(summary.errors.single, contains('Human Computer Interaction'));
      expect(registrarRepo.findOrCreateCalls, isEmpty);
    });
  });

  test('an unrecognized file throws ScheduleImportException', () async {
    final runner = ScheduleImportRunner(
      scheduleImportRepository: _FakeScheduleImportRepository(),
      registrarRepository: _FakeRegistrarRepository(),
    );
    final bytes = _buildXlsx('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>Just some random data</t></is></c></row>
  </sheetData>
</worksheet>
''');

    expect(
      () => runner.run(xlsxBytes: bytes, schoolYear: '2026-2027', term: '1st Semester'),
      throwsA(isA<ScheduleImportException>()),
    );
  });
}
