/// Student row displayed in the RFID Management dashboard table.
class RfidStudentRow {
  const RfidStudentRow({
    required this.id,
    required this.rfidNo,
    required this.studentNumber,
    required this.firstName,
    required this.middleInitial,
    required this.lastName,
    required this.course,
    required this.yearLevel,
    required this.section,
    required this.guardianName,
    this.photoPath,
  });

  final String id;
  final String rfidNo;
  final String studentNumber;
  final String firstName;
  final String middleInitial;
  final String lastName;
  final String course;
  final String yearLevel;
  final String section;
  final String guardianName;

  /// `students.photo_path` — the Storage object path (not a URL, since the
  /// bucket is private) of this student's ID photo, if one's been captured.
  final String? photoPath;

  String get fullName {
    final mi = middleInitial.trim();
    final middle = mi.isEmpty ? '' : ' ${mi.toUpperCase()}.';
    return '${firstName.trim()}$middle ${lastName.trim()}'.replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }
}

/// Form payload submitted from the registration panel.
class RfidRegistrationForm {
  const RfidRegistrationForm({
    required this.rfidNo,
    required this.studentNumber,
    required this.firstName,
    required this.middleInitial,
    required this.lastName,
    required this.course,
    required this.yearLevel,
    required this.section,
    required this.guardianName,
  });

  final String rfidNo;
  final String studentNumber;
  final String firstName;
  final String middleInitial;
  final String lastName;
  final String course;
  final String yearLevel;
  final String section;
  final String guardianName;
}
