/// Row shape from `students` with embedded `profiles`, `sections`, and optional parents.
class StudentRecord {
  const StudentRecord({
    required this.id,
    required this.rfidUid,
    required this.studentNumber,
    required this.firstName,
    required this.middleInitial,
    required this.lastName,
    required this.course,
    required this.yearLevelInt,
    required this.section,
    required this.guardianName,
    this.photoPath,
  });

  final String id;
  final String rfidUid;
  final String studentNumber;
  final String firstName;
  final String middleInitial;
  final String lastName;
  final String course;
  final int yearLevelInt;
  final String section;
  final String guardianName;

  /// `students.photo_path` — the Storage object path (not a URL, since the
  /// bucket is private) of this student's ID photo, if one's been captured.
  final String? photoPath;

  /// Maps `rfid_uid` for the existing UI copy ("RFID No.").
  String get rfidNo => rfidUid;

  String get yearLevel => yearLevelToLabel(yearLevelInt);

  String get fullName {
    final mi = middleInitial.trim();
    final middle = mi.isEmpty ? '' : ' ${mi.toUpperCase()}.';
    return '${firstName.trim()}$middle ${lastName.trim()}'.replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }

  static String yearLevelToLabel(int y) {
    if (y >= 1 && y <= 6) {
      const labels = [
        '',
        '1st Year',
        '2nd Year',
        '3rd Year',
        '4th Year',
        '5th Year',
        '6th Year',
      ];
      return labels[y];
    }
    return 'Year $y';
  }

  static int yearLabelToInt(String label) {
    final i = [
      '1st Year',
      '2nd Year',
      '3rd Year',
      '4th Year',
      '5th Year',
      '6th Year',
    ].indexOf(label);
    return i >= 0 ? i + 1 : 1;
  }

  static String composeFirstName(String first, String middleInitial) {
    final t = middleInitial.trim();
    if (t.isEmpty) return first.trim();
    return '${first.trim()} ${t.toUpperCase()}.';
  }

  static (String first, String mi) splitStoredFirstName(String stored) {
    final s = stored.trim();
    final re = RegExp(r'^(.+?)\s+([A-Za-z])\.$');
    final m = re.firstMatch(s);
    if (m != null) {
      return (m.group(1)!, m.group(2)!);
    }
    return (s, '');
  }

  factory StudentRecord.fromSupabase(Map<String, dynamic> row) {
    final profiles = row['profiles'];
    var firstName = '';
    var lastName = '';
    var middleInitial = '';
    if (profiles is Map<String, dynamic>) {
      final rawFirst = (profiles['first_name'] as String?)?.trim() ?? '';
      lastName = (profiles['last_name'] as String?)?.trim() ?? '';
      final split = splitStoredFirstName(rawFirst);
      firstName = split.$1;
      middleInitial = split.$2;
    }

    final yearRaw = row['year_level'];
    final yearLevelInt = yearRaw is int
        ? yearRaw
        : (yearRaw is num ? yearRaw.toInt() : 1);

    final sections = row['sections'];
    var section = '';
    if (sections is Map<String, dynamic>) {
      section = (sections['name'] as String?)?.trim() ?? '';
    }

    var guardian = '';
    final links = row['parent_student_links'];
    if (links is List<dynamic>) {
      for (final link in links) {
        if (link is! Map<String, dynamic>) continue;
        final p = link['profiles'];
        if (p is Map<String, dynamic>) {
          final fn = (p['first_name'] as String?)?.trim() ?? '';
          final ln = (p['last_name'] as String?)?.trim() ?? '';
          final g = ('$fn $ln').trim();
          if (g.isNotEmpty) {
            guardian = g;
            break;
          }
        }
      }
    }

    final rfidRaw = row['rfid_uid'];
    final rfidUid = rfidRaw == null ? '' : rfidRaw as String;

    return StudentRecord(
      id: row['id'] as String,
      rfidUid: rfidUid,
      studentNumber: row['student_number'] as String,
      firstName: firstName,
      middleInitial: middleInitial,
      lastName: lastName,
      course: row['course'] as String,
      yearLevelInt: yearLevelInt,
      section: section,
      guardianName: guardian,
      photoPath: row['photo_path'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudentRecord && id == other.id && id.isNotEmpty;

  @override
  int get hashCode => id.hashCode;
}
