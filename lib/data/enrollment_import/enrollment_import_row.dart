/// One parsed row from the Registrar's "Student Information" batch
/// enrollment file. Only carries fields with a home in `students`/
/// `profiles` today — [course]/[yearLevel] here are just what the file
/// itself says (its own "Program"/"Level" columns); EnrollmentImportRunner
/// prefers the section actually chosen for this batch whenever a row
/// leaves either blank, since "importing into BSIT 3B" already implies
/// "these students are BSIT, year 3".
///
/// Every other column in the real export (LRN, ESC ID, Voucher Applicant
/// No, address/birth details, elementary/high-school/college history) has
/// no column to land in yet — the school's own registrar system is the
/// source of truth for those; nothing in this dashboard reads them, so
/// they're intentionally not parsed rather than growing the schema for
/// data nothing displays. Guardian name/email ARE parsed (below) since
/// EnrollmentImportRepository uses them to auto-create a Parent account.
class EnrollmentImportRow {
  const EnrollmentImportRow({
    required this.studentNumber,
    required this.firstName,
    required this.lastName,
    this.middleName,
    this.suffix,
    this.course,
    this.yearLevel,
    this.email,
    this.guardianName,
    this.guardianEmail,
  });

  final String studentNumber;
  final String firstName;
  final String lastName;

  /// Only its first letter is actually stored (`profiles.first_name`
  /// keeps just a middle *initial* — see StudentRecord.composeFirstName).
  final String? middleName;

  /// Appended to [lastName] (e.g. "Dela Cruz Jr.") when present.
  final String? suffix;

  final String? course;
  final int? yearLevel;
  final String? email;

  /// From "Parent/s" (e.g. "Christian Castillo / Bea Manalang Castillo"),
  /// falling back to "Guardian/s" when the file has no Parent/s name for
  /// this row. Stored as one free-form string rather than split into
  /// first/last — the source column itself is often more than one person
  /// separated by " / ", so there's no reliable way to decompose it, and
  /// StudentRecord.fromSupabase already renders a guardian's stored
  /// first+last as a single joined string anyway.
  final String? guardianName;

  /// From "Parent/s Email", falling back to "Guardian/s Email" — the one
  /// EnrollmentImportRepository actually keys the auto-created/linked
  /// Parent account on.
  final String? guardianEmail;
}
