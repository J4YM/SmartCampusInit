/// The Certificate of Good Moral request slip, field by field.
///
/// Stored as `good_moral_requests.form_data` (supabase/add_good_moral_form_data.sql)
/// next to the older `remarks` text block, so the Discipline Officer can compare
/// each answer with what the school has on record.
class GoodMoralFormData {
  const GoodMoralFormData({
    this.lastName = '',
    this.firstName = '',
    this.middleName = '',
    this.address = '',
    this.studentNumber = '',
    this.section = '',
    this.contactNumber = '',
    this.ayStarted = '',
    this.ayLastAttended = '',
    this.schoolStatus = '',
    this.reason = '',
  });

  final String lastName;
  final String firstName;
  final String middleName;
  final String address;
  final String studentNumber;

  /// Strand / course / section.
  final String section;
  final String contactNumber;

  /// A.Y./term started in STI.
  final String ayStarted;

  /// A.Y./term last attended in STI.
  final String ayLastAttended;

  /// `Enrolled`, `Transferred`, `SHS Graduate` or `College Graduate`.
  final String schoolStatus;

  /// The purpose: a listed reason, or the text written under "other".
  final String reason;

  factory GoodMoralFormData.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] as String?)?.trim() ?? '';
    return GoodMoralFormData(
      lastName: read('last_name'),
      firstName: read('first_name'),
      middleName: read('middle_name'),
      address: read('address'),
      studentNumber: read('student_number'),
      section: read('section'),
      contactNumber: read('contact_number'),
      ayStarted: read('ay_started'),
      ayLastAttended: read('ay_last_attended'),
      schoolStatus: read('school_status'),
      reason: read('reason'),
    );
  }

  Map<String, dynamic> toJson() => {
        'last_name': lastName,
        'first_name': firstName,
        'middle_name': middleName,
        'address': address,
        'student_number': studentNumber,
        'section': section,
        'contact_number': contactNumber,
        'ay_started': ayStarted,
        'ay_last_attended': ayLastAttended,
        'school_status': schoolStatus,
        'reason': reason,
      };

  /// The labelled text block the certificate and older screens read
  /// (`good_moral_requests.remarks`).
  String remarksText() {
    final middle = middleName.trim();
    final fullName = '${lastName.trim()}, ${firstName.trim()}'
        '${middle.isEmpty ? '' : ' $middle'}';
    return [
      'Name: $fullName',
      'Address: ${address.trim()}',
      'Student Number: ${studentNumber.trim()}',
      'Strand/Course/Section: ${section.trim()}',
      'Contact Number: ${contactNumber.trim()}',
      'A.Y./TERM started in STI: ${ayStarted.trim()}',
      'A.Y./TERM last attended in STI: ${ayLastAttended.trim()}',
      'School Status: ${schoolStatus.trim()}',
    ].join('\n');
  }
}

/// What the school has on record for the requesting student. Anything the
/// school does not hold is left null/empty and compares as "not on record".
class GoodMoralRecord {
  const GoodMoralRecord({
    this.firstName = '',
    this.lastName = '',
    this.studentNumber = '',
    this.section = '',
    this.contactNumber = '',
    this.enrollmentYear,
  });

  final String firstName;
  final String lastName;
  final String studentNumber;
  final String section;
  final String contactNumber;

  /// `students.enrollment_year`.
  final int? enrollmentYear;
}

enum FieldMatch { match, mismatch, notOnRecord }

/// One row of the DO's slip-versus-record comparison.
class GoodMoralFieldCheck {
  const GoodMoralFieldCheck({
    required this.label,
    required this.submitted,
    required this.onRecord,
    required this.match,
  });

  final String label;
  final String submitted;

  /// What the school has; empty when [match] is [FieldMatch.notOnRecord].
  final String onRecord;
  final FieldMatch match;
}

String _letters(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _name(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9ñ ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _lastTenDigits(String s) {
  final digits = s.replaceAll(RegExp(r'\D'), '');
  return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
}

GoodMoralFieldCheck _check(
  String label,
  String submitted,
  String onRecord,
  bool Function(String submitted, String onRecord) same,
) {
  if (onRecord.trim().isEmpty) {
    return GoodMoralFieldCheck(
        label: label, submitted: submitted, onRecord: '', match: FieldMatch.notOnRecord);
  }
  return GoodMoralFieldCheck(
    label: label,
    submitted: submitted,
    onRecord: onRecord,
    match: same(submitted, onRecord) ? FieldMatch.match : FieldMatch.mismatch,
  );
}

GoodMoralFieldCheck _noRecord(String label, String submitted) =>
    GoodMoralFieldCheck(
        label: label, submitted: submitted, onRecord: '', match: FieldMatch.notOnRecord);

/// Compares each answer on the slip with the school's record. Names, student
/// number, section, contact number and A.Y. started are checked; the fields
/// the school holds nothing for (middle name, address, last attended, school
/// status) are listed as not on record and never count as a mismatch.
List<GoodMoralFieldCheck> compareGoodMoralForm(
  GoodMoralFormData form,
  GoodMoralRecord record,
) {
  final year = record.enrollmentYear?.toString() ?? '';
  return [
    _check('Last name', form.lastName, record.lastName,
        (a, b) => _name(a) == _name(b)),
    _check('First name', form.firstName, record.firstName,
        (a, b) => _name(a) == _name(b)),
    _noRecord('Middle name', form.middleName),
    _noRecord('Address', form.address),
    _check('Student number', form.studentNumber, record.studentNumber,
        (a, b) => _letters(a) == _letters(b)),
    _check('Course/Section', form.section, record.section,
        (a, b) => _letters(a) == _letters(b)),
    _check('Contact number', form.contactNumber, record.contactNumber,
        (a, b) => _lastTenDigits(a) == _lastTenDigits(b)),
    // "2024-2025" starts in 2024: judge the first year written.
    _check('A.Y./Term started', form.ayStarted, year,
        (a, b) => RegExp(r'\d{4}').firstMatch(a)?.group(0) == b),
    _noRecord('A.Y./Term last attended', form.ayLastAttended),
    _noRecord('School status', form.schoolStatus),
  ];
}
