// scripts/generate_mock_upload_xlsx.dart
//
// Produces two mock spreadsheets in the exact formats the Registrar's
// upload buttons already parse:
//
//   sample_data/mock_students_enrollment.xlsx
//     -> lib/data/enrollment_import/enrollment_file_parser.dart
//        (Student ID, Last Name, Suffix, First Name, Middle Name, Program,
//         Level, Campus Email Address, Parent/s, Parent/s Email)
//   sample_data/mock_professors_classes.xlsx
//     -> parseClassesAndProfessorList in schedule_import/schedule_file_parser.dart
//        (Class No, Course Code, Description, Course Unit, Instructor ID,
//         Last Name, First Name, Middle Name) — professors are created from
//         this file by the schedule import (resolveProfessorId).
//
// Deterministic (no randomness), so re-running yields identical files.
// Student IDs use the 02000 9xxxxx range and professor IDs a MOCKP prefix so
// they can't collide with real records.
//
// Usage: dart run scripts/generate_mock_upload_xlsx.dart

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

String _colLetter(int i) => String.fromCharCode('A'.codeUnitAt(0) + i);

String _esc(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

List<int> _buildXlsx(String sheetName, List<List<String?>> rows) {
  final sheetRows = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    final cells = StringBuffer();
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v == null || v.isEmpty) continue;
      cells.write('<c r="${_colLetter(c)}${r + 1}" t="inlineStr">'
          '<is><t>${_esc(v)}</t></is></c>');
    }
    sheetRows.write('<row r="${r + 1}">$cells</row>');
  }
  final sheetXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>$sheetRows</sheetData></worksheet>';

  const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '</Types>';
  const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';
  final workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="$sheetName" sheetId="1" r:id="rId1"/></sheets></workbook>';
  const workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '</Relationships>';

  final archive = Archive()
    ..addFile(ArchiveFile.bytes('[Content_Types].xml', utf8.encode(contentTypes)))
    ..addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode(rootRels)))
    ..addFile(ArchiveFile.bytes('xl/workbook.xml', utf8.encode(workbook)))
    ..addFile(ArchiveFile.bytes('xl/_rels/workbook.xml.rels', utf8.encode(workbookRels)))
    ..addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheetXml)));
  return ZipEncoder().encodeBytes(archive);
}

const _firstNames = [
  'Juan', 'Maria', 'Jose', 'Ana', 'Mark', 'Angelica', 'Paolo', 'Katrina',
  'Miguel', 'Bianca', 'Carlo', 'Nicole', 'Daniel', 'Patricia', 'Gabriel',
  'Sofia', 'Rafael', 'Camille', 'Joshua', 'Danielle',
];
const _middleNames = [
  'Santos', 'Reyes', 'Cruz', 'Garcia', 'Mendoza', 'Flores', 'Ramos', 'Torres',
];
const _lastNames = [
  'Dela Cruz', 'Bautista', 'Villanueva', 'Aquino', 'Castillo', 'Navarro',
  'Domingo', 'Fernandez', 'Salazar', 'Pascual', 'Manalo', 'Soriano', 'Ocampo',
  'Valdez', 'Mercado', 'Del Rosario', 'Lim', 'Tan', 'Gonzales', 'Ignacio',
];
const _programs = [
  'BS Information Technology',
  'BS Hospitality Management',
  'BS Tourism Management',
  'BS Business Administration',
];

List<List<String?>> _studentRows() {
  final rows = <List<String?>>[
    [
      'Student ID', 'Last Name', 'Suffix', 'First Name', 'Middle Name',
      'Program', 'Level', 'Campus Email Address', 'Parent/s', 'Parent/s Email',
    ],
  ];
  const count = 60;
  for (var i = 0; i < count; i++) {
    final number = 900001 + i;
    final last = _lastNames[(i * 7) % _lastNames.length];
    final first = _firstNames[(i * 3) % _firstNames.length];
    final middle = _middleNames[i % _middleNames.length];
    final suffix = i % 25 == 24 ? 'Jr.' : null;
    // 60% BSIT, the rest spread across the other programs.
    final program = _programs[i % 10 < 6 ? 0 : (i % 10 - 6) % 3 + 1];
    final level = (i % 4) + 1;
    final id = '02000$number';
    final slug = last.toLowerCase().replaceAll(' ', '.');
    // Every third student shares a guardian with the previous one (siblings),
    // which exercises the "one guardian, several children" path.
    final guardianIndex = i % 3 == 2 ? i - 1 : i;
    final guardianLast = _lastNames[(guardianIndex * 7) % _lastNames.length];
    final guardianFirst = _firstNames[(guardianIndex * 5 + 2) % _firstNames.length];
    rows.add([
      id,
      last,
      suffix,
      first,
      middle,
      program,
      '$level',
      '$slug.$number@baliuag.sti.edu.ph',
      '$guardianFirst $guardianLast',
      'mock.guardian${guardianIndex + 1}@example.com',
    ]);
  }
  return rows;
}

List<List<String?>> _professorRows() {
  // (code, description, units) — real codes from sample_data/curriculum.
  const subjects = [
    ('CITE1004', 'Introduction to Computing', '3'),
    ('CITE1003', 'Computer Programming 1', '3'),
    ('CITE1006', 'Computer Programming 2', '3'),
    ('COSC1003', 'Data Structures and Algorithms', '3'),
    ('COSC1007', 'Human-Computer Interaction', '3'),
    ('COSC1008', 'Platform Technology (Operating Systems)', '3'),
    ('CITE1011', 'Information Management', '3'),
    ('INTE1006', 'Systems Administration and Maintenance', '3'),
    ('GEDC1002', 'The Contemporary World', '3'),
    ('GEDC1016', 'Purposive Communication', '3'),
    ('GEDC1005', 'Mathematics in the Modern World', '3'),
    ('GEDC1008', 'Understanding the Self', '3'),
    ('GEDC1009', 'Ethics', '3'),
    ('GEDC1006', 'Readings in Philippine History', '3'),
    ('PHED1005', 'P.E./PATHFIT 1: Movement Competency Training', '2'),
    ('STIC1002', 'Euthenics 1', '1'),
  ];
  const professors = [
    ('Villanueva', 'Ramon', 'Cruz'),
    ('Santiago', 'Elena', 'Reyes'),
    ('Magsaysay', 'Antonio', 'Dizon'),
    ('Rivera', 'Liza', 'Bello'),
    ('Concepcion', 'Marco', 'Lopez'),
    ('Hernandez', 'Teresa', 'Aguilar'),
    ('Pangilinan', 'Roberto', 'Silva'),
    ('Estrada', 'Cecilia', 'Morales'),
  ];

  final rows = <List<String?>>[
    ['STI COLLEGE BALIUAG'],
    ['Course and Grade Monitoring — Classes and Professors (MOCK DATA)'],
    [],
    [
      'Class No', 'Course Code', 'Description', 'Course Unit', 'Instructor ID',
      'Last Name', 'First Name', 'Middle Name',
    ],
  ];
  var classNo = 5001;
  for (var s = 0; s < subjects.length; s++) {
    final prof = professors[s % professors.length];
    final subject = subjects[s];
    rows.add([
      '${classNo++}',
      subject.$1,
      subject.$2,
      subject.$3,
      'MOCKP${(s % professors.length + 1).toString().padLeft(3, '0')}',
      prof.$1,
      prof.$2,
      prof.$3,
    ]);
  }
  return rows;
}

void main() {
  final outDir = Directory('sample_data');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  final students = _studentRows();
  File('sample_data/mock_students_enrollment.xlsx')
      .writeAsBytesSync(_buildXlsx('Students', students));
  // ignore: avoid_print
  print('Wrote sample_data/mock_students_enrollment.xlsx '
      '(${students.length - 1} students)');

  final professors = _professorRows();
  File('sample_data/mock_professors_classes.xlsx')
      .writeAsBytesSync(_buildXlsx('Classes', professors));
  // ignore: avoid_print
  print('Wrote sample_data/mock_professors_classes.xlsx '
      '(${professors.length - 4} class rows, 8 professors)');
}
