/// One parsed student row from the registrar's "Candidates for Academic
/// Honors" GPA export — see grade_file_parser.dart's own doc comment for
/// the exact source column layout. Deliberately carries only the fields
/// [GradeImportRepository.upsertGpaRecord] actually writes to
/// `student_gpa_records`; the file's free-text per-course grade slots
/// (Course 1..10) have no reliable mapping to a real subject/class_section
/// and aren't needed for the GPA-trend data this feeds — see that table's
/// own migration comment.
class GradeImportRow {
  const GradeImportRow({
    required this.studentNumber,
    required this.firstName,
    required this.lastName,
    this.middleName,
    this.suffix,
    this.transferUnits,
    this.failedCoursesCount,
    this.cumulativeUnitsTaken,
    this.cumulativeGpa,
    this.currentTermUnitsTaken,
    this.currentTermGpa,
  });

  final String studentNumber;
  final String firstName;
  final String lastName;
  final String? middleName;
  final String? suffix;

  final double? transferUnits;
  final int? failedCoursesCount;
  final double? cumulativeUnitsTaken;

  /// Philippine 1.00-5.00 scale, 1.00 = best — NOT the 0-100 scale
  /// `grades.grade` uses.
  final double? cumulativeGpa;

  final double? currentTermUnitsTaken;
  final double? currentTermGpa;
}

/// [parseGradeFile]'s result — the school-year/term the whole file was
/// exported for (from its "SY & Term:" banner row, shared by every student
/// row in the file) plus the parsed rows themselves.
class ParsedGradeFile {
  const ParsedGradeFile({
    required this.schoolYear,
    required this.term,
    required this.rows,
  });

  final String schoolYear;
  final String term;
  final List<GradeImportRow> rows;
}
