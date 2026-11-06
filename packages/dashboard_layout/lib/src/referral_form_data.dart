/// The choices on STI's External Referral Form (FT-SDW-164-00), in the order
/// the paper form lists them. Shared by the Student Portal (which fills the
/// form in on a self referral) and the Guidance dashboard (which views and
/// prints it).
class ReferralFormOptions {
  const ReferralFormOptions._();

  /// "Referral to:" — `others` carries a free-text name.
  static const referralTo = [
    'Guidance Counselor',
    'Psychologist',
    'Psychiatrist',
  ];

  static const academic = [
    'Absenteeism',
    'Academic Stress',
    'Adjustment Issues',
    'Concentration Difficulty',
    'Excessive tardiness',
    'Faculty Concerns',
    'Failed course/s',
    'Feeling overwhelmed',
    'Learning disability',
    'Lack of interest',
    'Loss of motivation',
    'Perfectionism',
    'Planning to withdraw',
    'Procrastination',
    'Repeating year level',
    'Test anxiety',
    'Time management',
    'Underachievement',
  ];

  static const personal = [
    'Abuse',
    'Addiction',
    'Anxiety',
    'Bullying',
    'Depression',
    'Hopelessness',
    'Homesickness',
    'Identity concerns',
    'Eating Habits',
    'Financial',
    'Lack of sleep',
    'Lacking energy',
    'Loss of motivation',
    'Legal',
    'Loneliness',
    'Low confidence or self-esteem',
    'Managing emotions',
    'Pregnancy',
    'Relationship/s',
    'Self-Image',
    'Self-harm',
    'Suicidal ideations or tendencies',
    'Suicidal attempt',
  ];

  static const career = [
    'Decision-Making',
    'Employment',
    'Exploration',
    'Goal Setting',
    'Shifting',
  ];
}

/// What the student picks and fills in on a self referral, kept with the
/// referral (`student_referrals.form`, supabase/add_referral_form.sql) so the
/// form can be shown and printed later by the student and by Guidance.
///
/// The identity block (name, number, section, contact, address, birthdate,
/// program) is a snapshot taken when the referral was sent.
class ReferralFormData {
  const ReferralFormData({
    this.studentName = '',
    this.studentNumber = '',
    this.section = '',
    this.contactNumber = '',
    this.address = '',
    this.birthdate = '',
    this.program = '',
    this.referralTo = const ['Guidance Counselor'],
    this.referralToOther = '',
    this.academic = const [],
    this.personal = const [],
    this.career = const [],
    this.otherAcademic = '',
    this.otherPersonal = '',
    this.otherCareer = '',
  });

  final String studentName;
  final String studentNumber;

  /// "Grade/Year Level & Section".
  final String section;
  final String contactNumber;
  final String address;
  final String birthdate;
  final String program;

  /// Entries of [ReferralFormOptions.referralTo]; "Others" is
  /// [referralToOther] when not empty.
  final List<String> referralTo;
  final String referralToOther;

  final List<String> academic;
  final List<String> personal;
  final List<String> career;
  final String otherAcademic;
  final String otherPersonal;
  final String otherCareer;

  /// Every specific concern the student picked or wrote, in the form's order.
  List<String> get pickedConcerns => [
        ...academic,
        if (otherAcademic.isNotEmpty) otherAcademic,
        ...personal,
        if (otherPersonal.isNotEmpty) otherPersonal,
        ...career,
        if (otherCareer.isNotEmpty) otherCareer,
      ];

  bool get hasPickedConcerns => pickedConcerns.isNotEmpty;

  ReferralFormData copyWith({
    String? studentName,
    String? studentNumber,
    String? section,
    String? contactNumber,
    String? address,
    String? birthdate,
    String? program,
    List<String>? referralTo,
    String? referralToOther,
    List<String>? academic,
    List<String>? personal,
    List<String>? career,
    String? otherAcademic,
    String? otherPersonal,
    String? otherCareer,
  }) =>
      ReferralFormData(
        studentName: studentName ?? this.studentName,
        studentNumber: studentNumber ?? this.studentNumber,
        section: section ?? this.section,
        contactNumber: contactNumber ?? this.contactNumber,
        address: address ?? this.address,
        birthdate: birthdate ?? this.birthdate,
        program: program ?? this.program,
        referralTo: referralTo ?? this.referralTo,
        referralToOther: referralToOther ?? this.referralToOther,
        academic: academic ?? this.academic,
        personal: personal ?? this.personal,
        career: career ?? this.career,
        otherAcademic: otherAcademic ?? this.otherAcademic,
        otherPersonal: otherPersonal ?? this.otherPersonal,
        otherCareer: otherCareer ?? this.otherCareer,
      );

  Map<String, dynamic> toJson() => {
        'student_name': studentName,
        'student_number': studentNumber,
        'section': section,
        'contact_number': contactNumber,
        'address': address,
        'birthdate': birthdate,
        'program': program,
        'referral_to': referralTo,
        'referral_to_other': referralToOther,
        'academic': academic,
        'personal': personal,
        'career': career,
        'other_academic': otherAcademic,
        'other_personal': otherPersonal,
        'other_career': otherCareer,
      };

  /// Reads the stored form; a missing or malformed value gives an empty form
  /// (referrals sent before the form existed have none).
  factory ReferralFormData.fromJson(Object? raw) {
    if (raw is! Map) return const ReferralFormData(referralTo: []);
    String text(String key) => '${raw[key] ?? ''}'.trim();
    List<String> list(String key) => [
          for (final v in (raw[key] as List<dynamic>? ?? const []))
            if ('$v'.trim().isNotEmpty) '$v'.trim(),
        ];
    return ReferralFormData(
      studentName: text('student_name'),
      studentNumber: text('student_number'),
      section: text('section'),
      contactNumber: text('contact_number'),
      address: text('address'),
      birthdate: text('birthdate'),
      program: text('program'),
      referralTo: list('referral_to'),
      referralToOther: text('referral_to_other'),
      academic: list('academic'),
      personal: list('personal'),
      career: list('career'),
      otherAcademic: text('other_academic'),
      otherPersonal: text('other_personal'),
      otherCareer: text('other_career'),
    );
  }
}

/// Everything the printed External Referral Form shows: the student's form
/// plus what the referral itself holds.
class ReferralFormDocument {
  const ReferralFormDocument({
    required this.form,
    required this.referredOn,
    required this.concernLabel,
    required this.details,
    this.urgent = false,
    this.school = 'STI College Baliuag',
  });

  final ReferralFormData form;
  final DateTime referredOn;

  /// What the student said it is about, e.g. "Emotional / mental well-being".
  final String concernLabel;

  /// The student's own words, printed as the significant history.
  final String details;
  final bool urgent;
  final String school;

  /// The school year the referral falls in: June to May.
  String get schoolYear {
    final start = referredOn.month >= 6 ? referredOn.year : referredOn.year - 1;
    return '$start - ${start + 1}';
  }
}
