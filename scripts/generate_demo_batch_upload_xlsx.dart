// scripts/generate_demo_batch_upload_xlsx.dart
//
// Demo-day batch upload files (deterministic):
//   Student_Information_Demo_Batch10.xlsx     -> enrollment_file_parser.dart
//   Course_and_Professor_Assignment_Demo.xlsx -> parseClassesAndProfessorList
//   Academic_Honors_Demo_Batch10.xlsx         -> grade_file_parser.dart
//
// Reads the existing demo files in the target folder for layout and to skip
// subjects that are already assigned. Run from the repo root:
//   dart run scripts/generate_demo_batch_upload_xlsx.dart [outDir] [existingDir]

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:capstone_dashboard/data/schedule_import/xlsx_reader.dart';

const _defaultDir =
    r'E:\DOWNLOADS WALANG SPACE SA MAIN\samplereports\TO UPLOAD';

String _col(int i) {
  var s = '';
  var n = i + 1;
  while (n > 0) {
    s = String.fromCharCode(65 + (n - 1) % 26) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

String _esc(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

List<int> _xlsx(String sheetName, List<List<String?>> rows) =>
    _xlsxMulti({sheetName: rows});

String _sheetXml(List<List<String?>> rows) {
  final sb = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    final cells = StringBuffer();
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v == null || v.isEmpty) continue;
      cells.write(
          '<c r="${_col(c)}${r + 1}" t="inlineStr"><is><t xml:space="preserve">${_esc(v)}</t></is></c>');
    }
    sb.write('<row r="${r + 1}">$cells</row>');
  }
  return sb.toString();
}

List<int> _xlsxMulti(Map<String, List<List<String?>>> sheets) {
  final names = sheets.keys.toList();
  const h = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  const ns = 'http://schemas.openxmlformats.org/';
  final files = {
    '[Content_Types].xml':
        '$h<Types xmlns="${ns}package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${[
      for (var i = 0; i < names.length; i++)
        '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    ].join()}</Types>',
    '_rels/.rels':
        '$h<Relationships xmlns="${ns}package/2006/relationships"><Relationship Id="rId1" Type="${ns}officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml':
        '$h<workbook xmlns="${ns}spreadsheetml/2006/main" xmlns:r="${ns}officeDocument/2006/relationships"><sheets>${[
      for (var i = 0; i < names.length; i++)
        '<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'
    ].join()}</sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '$h<Relationships xmlns="${ns}package/2006/relationships">${[
      for (var i = 0; i < names.length; i++)
        '<Relationship Id="rId${i + 1}" Type="${ns}officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'
    ].join()}</Relationships>',
    for (var i = 0; i < names.length; i++)
      'xl/worksheets/sheet${i + 1}.xml':
          '$h<worksheet xmlns="${ns}spreadsheetml/2006/main"><sheetData>${_sheetXml(sheets[names[i]]!)}</sheetData></worksheet>',
  };
  final a = Archive();
  files.forEach((k, v) => a.addFile(ArchiveFile.bytes(k, utf8.encode(v))));
  return ZipEncoder().encodeBytes(a);
}

// ---------------------------------------------------------------- students
class _S {
  _S(this.id, this.first, this.middle, this.last, this.prog, this.year,
      this.sex);
  final String id, first, middle, last, prog, sex;
  final int year;
  String get email =>
      '${last.toLowerCase().replaceAll(' ', '')}.${id.substring(5)}@baliuag.sti.edu.ph';
}

const _progFull = {
  'BSIT': 'BS Information Technology',
  'BSBA': 'BS Business Administration',
  'BSHM': 'BS Hospitality Management',
  'BSTM': 'BS Tourism Management',
  'BSAIS': 'BS Accounting Information System',
};

List<_S> _students() {
  const mid = [
    'Santos',
    'Reyes',
    'Cruz',
    'Garcia',
    'Mendoza',
    'Flores',
    'Ramos',
    'Torres'
  ];
  const males = [
    'Paolo',
    'Miguel',
    'Daniel',
    'Gabriel',
    'Rafael',
    'Joshua',
    'Mark',
    'Jericho',
    'Adrian',
    'Kenneth',
    'Luis',
    'Emmanuel'
  ];
  const females = [
    'Bianca',
    'Nicole',
    'Patricia',
    'Sofia',
    'Camille',
    'Danielle',
    'Katrina',
    'Angelica',
    'Trisha',
    'Erica',
    'Hannah',
    'Jasmine'
  ];
  const lasts = [
    'Bautista',
    'Aquino',
    'Castillo',
    'Navarro',
    'Domingo',
    'Fernandez',
    'Salazar',
    'Pascual',
    'Manalo',
    'Soriano',
    'Ocampo',
    'Valdez',
    'Mercado',
    'Gonzales',
    'Santiago',
    'Roxas',
    'Evangelista',
    'Macaraeg',
    'Dizon',
    'Enriquez',
    'Panganiban',
    'Natividad',
    'Villegas',
    'Cabrera',
    'Magno',
    'Samonte',
    'Tolentino',
    'Buenaventura',
    'Concepcion',
  ];
  const progs = [
    'BSIT',
    'BSIT',
    'BSIT',
    'BSBA',
    'BSHM',
    'BSTM',
    'BSAIS',
    'BSIT'
  ];
  final out = <_S>[
    _S('02000338958', 'Carl Vinson', 'L.', 'Ventura', 'BSIT', 4, 'Male'),
  ];
  for (var i = 0; i < 9; i++) {
    final male = i.isEven;
    final first = male
        ? males[(i ~/ 2) % males.length]
        : females[(i ~/ 2) % females.length];
    final num =
        500000 + i * 13711; // 6 digits, distinct, clear of the demo file's ids
    out.add(_S('02000$num', first, mid[i % mid.length], lasts[i],
        progs[i % progs.length], (i % 4) + 1, male ? 'Male' : 'Female'));
  }
  return out;
}

List<List<String?>> _studentRows(List<String?> header, List<_S> ss) {
  final rows = <List<String?>>[header];
  final idx = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    final h = header[i];
    if (h != null) idx.putIfAbsent(h, () => i);
  }
  for (var n = 0; n < ss.length; n++) {
    final s = ss[n];
    final row = List<String?>.filled(header.length, null);
    void put(String h, String v) {
      final i = idx[h];
      if (i != null) row[i] = v;
    }

    final admit = 2026 - s.year + 1;
    put('Student ID', s.id);
    put('LRN', '${100000000000 + n * 7919317}');
    put('Last Name', s.last);
    put('First Name', s.first);
    put('Middle Name', s.middle);
    put('Program', s.prog);
    put('Level', '${s.year}${const ['st', 'nd', 'rd', 'th'][s.year - 1]} Year');
    put('Units in Progress', '21');
    put('Admit Term', '1st Sem SY $admit-${admit + 1}');
    put('Requirement Term', '1st Sem SY $admit-${admit + 1}');
    put('Campus Email Address', s.email);
    put('Address',
        '${100 + n * 7} Mabini St., Brgy. Poblacion, Baliuag, Bulacan');
    put('City', 'Baliuag, Bulacan');
    put('Sex', s.sex);
    put('Age', '${17 + s.year}');
    put('Parent/s', 'Mr. & Mrs. ${s.last}');
    put('Parent/s Email',
        'parent.${s.last.toLowerCase()}.${s.id.substring(7)}@example.com');
    rows.add(row);
  }
  return rows;
}

// ----------------------------------------------------- classes/professors
class _Subj {
  _Subj(this.code, this.title, this.units, this.prog, this.year);
  final String code, title, units, prog;
  final int year;
}

typedef _Prof = (String id, String last, String first, String mi);

const _profs = <String, List<_Prof>>{
  'BS Information Technology': [
    ('DEMO-PROF-0001', 'Villanueva', 'Ramon', ''),
    ('02000900002', 'Santiago', 'Elena', 'R.'),
  ],
  'BS Business Administration': [
    ('02000900003', 'Magsaysay', 'Antonio', 'D.'),
    ('02000900004', 'Rivera', 'Liza', 'B.'),
  ],
  'BS Hospitality Management': [
    ('02000900005', 'Concepcion', 'Marco', 'L.'),
    ('02000900006', 'Hernandez', 'Teresa', 'A.'),
  ],
  'BS Tourism Management': [
    ('02000900007', 'Pangilinan', 'Roberto', 'S.'),
    ('02000900008', 'Estrada', 'Cecilia', 'M.'),
  ],
  'BS Accounting Information System': [
    ('02000900009', 'Dimaculangan', 'Joel', 'P.'),
    ('02000900010', 'Reyes', 'Marites', 'C.'),
  ],
};

/// Remaining 1st-term subjects, each paired with its professor (alternating
/// between the program's two professors). Shared by the class list and CFL.
List<(_Subj, _Prof)> _assignments(Set<String> already) {
  final lines = File('sample_data/curriculum/curriculum_seed.txt')
      .readAsLinesSync()
      .skip(1);
  final seen = <String>{...already};
  final out = <(_Subj, _Prof)>[];
  final turn = <String, int>{};
  for (final l in lines) {
    final p = l.split('|');
    if (p.length < 6 || p[1] == '0' || p[2] != '1') continue;
    if (!seen.add(p[3])) continue;
    final s = _Subj(p[3], p[4], p[5], p[0], int.parse(p[1]));
    final t = turn.update(s.prog, (v) => v + 1, ifAbsent: () => 0);
    out.add((s, _profs[s.prog]![t % 2]));
  }
  return out;
}

List<List<String?>> _classRows(Set<String> already) {
  final rows = <List<String?>>[
    ['Career', ':', 'Baccalaureate'],
    [],
    ['SY & Term', ':', '2026-2027/1st Term'],
    [],
    [],
    [],
    [
      'Campus',
      null,
      null,
      'Class No',
      'Career',
      'Course ID',
      null,
      'Course Code',
      'Description',
      'Course Unit',
      'Instructor ID',
      'Last Name',
      'First Name',
      'Middle Name'
    ],
  ];
  var classNo = 9801;
  for (final (s, p) in _assignments(already)) {
    rows.add([
      'Baliuag',
      null,
      null,
      '${classNo++}',
      'BCT',
      null,
      null,
      s.code,
      s.title,
      s.units,
      p.$1,
      p.$2.toUpperCase(),
      p.$3.toUpperCase(),
      p.$4
    ]);
  }
  return rows;
}

// -------------------------------------------------------------------- CFL
const _abbr = {
  'BS Information Technology': 'BSIT',
  'BS Business Administration': 'BSBA',
  'BS Hospitality Management': 'BSHM',
  'BS Tourism Management': 'BSTM',
  'BS Accounting Information System': 'BSAIS',
};
// Day indexes into the sheet's M,T,W,TH,F,S columns.
const _dayPairs = [
  [0, 3],
  [1, 4],
  [0, 2],
  [2, 4],
  [1, 3],
  [0, 4],
  [3, 5],
  [4, 5],
  [0, 1],
  [2, 3],
  [1, 2],
  [3, 4],
  [1, 5],
  [2, 5],
];
// Slot starts in minutes from midnight (7:00 .. 4:00 PM).
const _starts = [420, 510, 600, 690, 780, 870, 960, 1020];
const _rooms = [
  'RM 101',
  'RM 102',
  'RM 103',
  'RM 201',
  'RM 202',
  'RM 203',
  'RM 301',
  'RM 302',
  'LAB 1',
  'LAB 2',
];

String _t(int m) {
  var h = m ~/ 60;
  final mm = (m % 60).toString().padLeft(2, '0');
  if (h > 12) h -= 12;
  return '$h:$mm';
}

/// One CFL sheet per professor. Greedy slotting so no professor, section or
/// room is double-booked.
Map<String, List<List<String?>>> _cflSheets(Set<String> already) {
  final busy = <String>{};
  final sheets = <String, List<List<String?>>>{};
  final byProf = <_Prof, List<_Subj>>{};
  for (final (s, p) in _assignments(already)) {
    byProf.putIfAbsent(p, () => []).add(s);
  }
  for (final e in byProf.entries) {
    final p = e.key;
    final full = '${p.$3} ${p.$2}';
    final rows = <List<String?>>[
      ['STI COLLEGE BALIUAG'],
      ['Tertiary'],
      ['Confirmation of Faculty Loading'],
      ['First Semester  SY 2026-2027'],
      [null, null, null, null, null, 'Instructor:', full],
      [],
      ['SUBJECT', 'Units', 'M', 'T', 'W', 'TH', 'F', 'S', 'Room', 'Section'],
    ];
    for (final s in e.value) {
      final units = int.parse(s.units);
      final len = units >= 3 ? 90 : 60;
      final nDays = units >= 2 ? 2 : 1;
      final section = '${_abbr[s.prog]} ${s.year}A';
      var placed = false;
      for (final room in _rooms) {
        for (final pair in _dayPairs) {
          if (placed) break;
          final days = pair.take(nDays).toList();
          for (final start in _starts) {
            final keys = [
              for (final d in days)
                for (var m = start; m < start + len; m += 30) ...[
                  'P|${p.$1}|$d|$m',
                  'S|$section|$d|$m',
                  'R|$room|$d|$m',
                ],
            ];
            if (keys.any(busy.contains)) continue;
            busy.addAll(keys);
            final row = List<String?>.filled(10, null);
            row[0] = s.title;
            row[1] = s.units;
            for (final d in days) {
              row[2 + d] = '${_t(start)} - ${_t(start + len)}';
            }
            row[8] = room;
            row[9] = section;
            rows.add(row);
            placed = true;
            break;
          }
        }
        if (placed) break;
      }
      if (!placed) stderr.writeln('UNPLACED ${s.code} for $full');
    }
    sheets[full] = rows;
  }
  return sheets;
}

// ------------------------------------------------------------------ grades
List<List<String?>> _gradeRows(List<List<String?>> template, List<_S> ss) {
  final first = template.indexWhere((r) => (r.first ?? '').startsWith('0200'));
  final rows = [for (final r in template.take(first)) List<String?>.of(r)];
  final curr = <String, List<String>>{}; // "program|year" -> 1st-term titles
  for (final l in File('sample_data/curriculum/curriculum_seed.txt')
      .readAsLinesSync()
      .skip(1)) {
    final p = l.split('|');
    if (p.length < 6 || p[2] != '1' || p[1] == '0') continue;
    curr.putIfAbsent('${p[0]}|${p[1]}', () => []).add(p[4]);
  }
  const grades = [
    '1.000',
    '1.250',
    '1.500',
    '1.750',
    '2.000',
    '2.250',
    '2.500',
    '2.750',
    '3.000'
  ];
  for (var n = 0; n < ss.length; n++) {
    final s = ss[n];
    final titles = curr['${_progFull[s.prog]}|${s.year}'] ?? const <String>[];
    // Standing mix: most strong, some middling, a few struggling (one failed course).
    final tier = n % 6 == 5 ? 2 : (n % 3 == 2 ? 1 : 0);
    final row = List<String?>.filled(24 + 3 * 8, null);
    var total = 0.0;
    var failed = 0;
    var count = 0;
    for (var c = 0; c < 8 && c < titles.length; c++) {
      var g = grades[(n * 3 + c * 2 + tier * 3) %
          (tier == 0
              ? 4
              : tier == 1
                  ? 7
                  : 9)];
      if (tier == 2 && c == 1) g = '5.000';
      if (g == '5.000') failed++;
      row[24 + c * 3] = titles[c];
      row[25 + c * 3] = '-';
      row[26 + c * 3] = g;
      total += double.parse(g);
      count++;
    }
    final gpa = (count == 0 ? 0 : total / count).toStringAsFixed(2);
    row[0] = s.id;
    row[1] = s.first.toUpperCase();
    row[3] = s.middle.toUpperCase();
    row[4] = s.last.toUpperCase();
    row[5] = ' ';
    row[7] = s.sex == 'Male' ? 'M' : 'F';
    row[9] = s.prog;
    row[10] = '${s.year}Y1';
    row[11] = '0';
    row[12] = '$failed';
    row[13] = '${s.year * 21}';
    row[15] = gpa;
    row[17] = '21';
    row[18] = '21';
    row[19] = '0';
    row[20] = failed > 0 ? '18' : '21';
    row[21] = '0';
    row[22] = gpa;
    rows.add(row);
  }
  return rows;
}

void main(List<String> args) {
  final out = args.isNotEmpty ? args[0] : _defaultDir;
  final src = args.length > 1 ? args[1] : out;
  Directory(out).createSync(recursive: true);

  List<List<String?>> read(String f) =>
      readAllSheets(File('$src/$f').readAsBytesSync()).first.rows;
  final studentTemplate = read('Student_Information_Demo.xlsx');
  final honorsTemplate = read('Academic_Honors_Demo.xlsx');
  final existing = read('Course_and_Professor_Assignment.xlsx');
  // Third arg "all": cover every 1st-term subject (no exclusions) so the
  // demo needs no other professor file and ends with exactly 10 professors.
  final already = args.length > 2 && args[2] == 'all'
      ? <String>{}
      : <String>{
          for (final r in existing)
            if (r.length > 7 && r[7] != null) r[7]!.trim(),
        };

  final ss = _students();
  final sRows = _studentRows(studentTemplate.first, ss);
  final cRows = _classRows(already);
  final gRows = _gradeRows(honorsTemplate, ss);

  File('$out/Student_Information_Demo_Batch10.xlsx')
      .writeAsBytesSync(_xlsx('Student_Information', sRows));
  File('$out/Course_and_Professor_Assignment_Demo.xlsx')
      .writeAsBytesSync(_xlsx('Course_and_Grade_Monitoring', cRows));
  File('$out/Academic_Honors_Demo_Batch10.xlsx')
      .writeAsBytesSync(_xlsx('Academic_Honors', gRows));
  final cfl = _cflSheets(already);
  File('$out/CFL_Demo_Professors_1st_Sem_2026-2027.xlsx')
      .writeAsBytesSync(_xlsxMulti(cfl));
  stdout.writeln('cflSheets=${cfl.length}');
  stdout.writeln(
      'students=${ss.length} classes=${cRows.length - 7} gradeRows=${gRows.length - gRows.indexWhere((r) => (r.first ?? "").startsWith("0200"))}');
}
