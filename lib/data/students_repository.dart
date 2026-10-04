import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../models/student_record.dart';

class StudentsRepositoryException implements Exception {
  StudentsRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A staff member resolved from a kiosk RFID tap — see
/// [StudentsRepository.fetchStaffByRfidCardId].
class StaffRfidRecord {
  const StaffRfidRecord({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.role,
  });

  /// `profiles.id`.
  final String id;
  final String firstName;
  final String lastName;

  /// Raw `app_role` db value (e.g. `'Security'`) — not yet mapped to
  /// [AppRole]/[AppRoleLabel] since this repository doesn't depend on
  /// `lib/auth/app_role.dart` (kept dependency-free like the rest of this
  /// file); callers map it themselves.
  final String role;

  String get fullName => '${firstName.trim()} ${lastName.trim()}'.trim();
}

/// One distinct (program, year, section) combination that at least one
/// student actually has — see [StudentsRepository.fetchStudentFilterFacets].
class StudentFilterFacet {
  const StudentFilterFacet({
    required this.program,
    required this.yearLevel,
    this.sectionId,
    this.sectionName,
  });

  /// Full program name as stored on `students.course`, e.g.
  /// 'BS Information Technology'.
  final String program;
  final int yearLevel;

  /// Null for a student with no section assigned.
  final String? sectionId;

  /// e.g. 'BSIT-3A'.
  final String? sectionName;
}

class StudentsRepository {
  StudentsRepository(this._client);

  final SupabaseClient _client;

  static const _selectEmbed = '''
id,
student_number,
rfid_uid,
course,
year_level,
section_id,
photo_path,
guardian_contact_no,
guardian_name,
signature_path,
created_at,
profiles (
  first_name,
  last_name,
  role
),
sections (
  name,
  program,
  year_level
),
parent_student_links (
  profiles!parent_student_links_parent_id_fkey (
    first_name,
    last_name
  )
)
''';

  Future<List<StudentRecord>> fetchAll() async {
    final response = await _client
        .from('students')
        .select(_selectEmbed)
        .order('created_at', ascending: false);

    final rows = response as List<dynamic>;
    return rows
        .map((e) => StudentRecord.fromSupabase(e as Map<String, dynamic>))
        .toList();
  }

  /// One page of students (1-indexed) plus the total row count matching the
  /// given filters — used by the Student Directory and IT Technician
  /// Student Records tab so neither ever has to load the whole table
  /// (potentially hundreds of rows) just to show one screenful.
  ///
  /// [studentNumberQuery] is a server-side `ilike` prefix match on
  /// `student_number` only — matching [searchByStudentNumberPrefix]'s own
  /// documented caution, full-name search against the embedded `profiles`
  /// table needs PostgREST's inner-join hint syntax to apply correctly,
  /// which isn't worth risking a silently-wrong filter for here.
  ///
  /// [courses]/[yearLevels]/[sectionIds] are the multi-select counterparts
  /// of [course]/[yearLevel]/[sectionId] (an `in` filter each); null or
  /// empty means "don't filter on this". Both forms can be combined.
  Future<({List<StudentRecord> items, int totalCount})> fetchPage({
    required int page,
    int pageSize = 25,
    String? course,
    int? yearLevel,
    String? sectionId,
    List<String>? courses,
    List<int>? yearLevels,
    List<String>? sectionIds,
    String? studentNumberQuery,
  }) async {
    final from = (page - 1) * pageSize;
    final to = from + pageSize - 1;

    var query = _client.from('students').select(_selectEmbed);
    if (course != null && course.isNotEmpty) {
      query = query.eq('course', course);
    }
    if (yearLevel != null) {
      query = query.eq('year_level', yearLevel);
    }
    if (sectionId != null && sectionId.isNotEmpty) {
      query = query.eq('section_id', sectionId);
    }
    if (courses != null && courses.isNotEmpty) {
      query = query.inFilter('course', courses);
    }
    if (yearLevels != null && yearLevels.isNotEmpty) {
      query = query.inFilter('year_level', yearLevels);
    }
    if (sectionIds != null && sectionIds.isNotEmpty) {
      query = query.inFilter('section_id', sectionIds);
    }
    if (studentNumberQuery != null && studentNumberQuery.trim().isNotEmpty) {
      query = query.ilike('student_number', '${studentNumberQuery.trim()}%');
    }

    final response = await query
        .order('created_at', ascending: false)
        .range(from, to)
        .count(CountOption.exact);

    final rows = response.data as List<dynamic>;
    return (
      items: rows
          .map((e) => StudentRecord.fromSupabase(e as Map<String, dynamic>))
          .toList(),
      totalCount: response.count,
    );
  }

  /// Returns a student row when [rfidUid] matches `students.rfid_uid` and the linked
  /// profile role is [AppEnv.profileRoleStudent] (when `profiles.role` is present).
  Future<StudentRecord?> fetchStudentByRfidUid(String rfidUid) async {
    final normalized = rfidUid.trim();
    if (normalized.isEmpty) return null;

    final response = await _client
        .from('students')
        .select(_selectEmbed)
        .eq('rfid_uid', normalized)
        .maybeSingle();

    if (response == null) return null;
    final row = Map<String, dynamic>.from(response);

    final profiles = row['profiles'];
    if (profiles is Map<String, dynamic>) {
      final role = profiles['role'] as String?;
      if (role != null && role != AppEnv.profileRoleStudent) {
        return null;
      }
    }

    return StudentRecord.fromSupabase(row);
  }

  /// Looks up an existing `students` row by student number, regardless of
  /// which auth identity it's linked to — used by the post-Microsoft-login
  /// setup gate to decide whether to show the registration form or the
  /// "claim my record" prompt (see `complete_student_registration` /
  /// `claim_preregistered_student` in
  /// supabase/add_student_self_registration_schema.sql).
  Future<StudentRecord?> fetchByStudentNumber(String studentNumber) async {
    final normalized = studentNumber.trim();
    if (normalized.isEmpty) return null;

    final response = await _client
        .from('students')
        .select(_selectEmbed)
        .eq('student_number', normalized)
        .maybeSingle();

    if (response == null) return null;
    return StudentRecord.fromSupabase(Map<String, dynamic>.from(response));
  }

  /// Up to [limit] students whose `student_number` starts with [query] —
  /// backs the Security Personnel kiosk report's "file on behalf of" search.
  /// Scoped to `student_number` only (not name): filtering on the `profiles`
  /// embed needs PostgREST's inner-join hint syntax to apply correctly,
  /// which [fetchPage]'s doc comment already flags as a follow-up rather
  /// than risk a silently-wrong filter — same caution applies here.
  Future<List<StudentRecord>> searchByStudentNumberPrefix(
    String query, {
    int limit = 8,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];

    final response = await _client
        .from('students')
        .select(_selectEmbed)
        .ilike('student_number', '$normalized%')
        .order('student_number')
        .limit(limit);

    return (response as List<dynamic>)
        .map((e) => StudentRecord.fromSupabase(e as Map<String, dynamic>))
        .toList();
  }

  /// Resolves a scanned RFID card to a staff member via `profiles.rfid_card_id`
  /// (distinct from `students.rfid_uid` — see add_oauth_role_approval_schema.sql)
  /// — used by the kiosk's staff/security tap branch. Returns null for a
  /// Student/Parent profile (those tap in via `fetchStudentByRfidUid`
  /// instead) or an unapproved profile.
  Future<StaffRfidRecord?> fetchStaffByRfidCardId(String cardId) async {
    final normalized = cardId.trim();
    if (normalized.isEmpty) return null;

    final response = await _client
        .from('profiles')
        .select('id, first_name, last_name, role, status')
        .eq('rfid_card_id', normalized)
        .maybeSingle();

    if (response == null) return null;
    final row = Map<String, dynamic>.from(response);

    final role = row['role'] as String?;
    if (role == null ||
        role == AppEnv.profileRoleStudent ||
        role == 'Parent' ||
        row['status'] != 'approved') {
      return null;
    }

    return StaffRfidRecord(
      id: row['id'] as String,
      firstName: (row['first_name'] as String?) ?? '',
      lastName: (row['last_name'] as String?) ?? '',
      role: role,
    );
  }

  /// Section names for a given program + year level, for the setup gate's
  /// section dropdown (narrower than free-text entry, so it can't typo past
  /// `findSectionId`'s exact match).
  Future<List<String>> fetchSectionNames({
    required String program,
    required int yearLevel,
  }) async {
    final rows = await _client
        .from('sections')
        .select('name')
        .eq('program', program)
        .eq('year_level', yearLevel)
        .order('name');
    return (rows as List<dynamic>)
        .map((e) => (e as Map<String, dynamic>)['name'] as String)
        .toList();
  }

  /// Every distinct program/year/section combination in use by at least one
  /// student, for building Program -> Year -> Section filter choices and
  /// resolving a picked block letter to `section_id`s for [fetchPage].
  ///
  /// Read from `students`, not `sections`: the `sections` table also holds
  /// rows no student belongs to (e.g. schedule-import rows whose `program`
  /// is a code like 'BSIT' rather than `students.course`'s full name),
  /// which would otherwise surface as duplicate/dead-end filter choices.
  /// Reads three narrow columns in 1000-row pages (PostgREST's default row
  /// cap), de-duplicated client-side.
  Future<List<StudentFilterFacet>> fetchStudentFilterFacets() async {
    const batch = 1000;
    final seen = <String>{};
    final facets = <StudentFilterFacet>[];
    for (var from = 0;; from += batch) {
      final rows = await _client
          .from('students')
          .select('course, year_level, section_id, sections ( name )')
          .order('id')
          .range(from, from + batch - 1);
      final list = rows as List<dynamic>;
      for (final e in list) {
        final row = e as Map<String, dynamic>;
        final program = row['course'] as String?;
        final year = (row['year_level'] as num?)?.toInt();
        if (program == null || year == null) continue;
        final sectionId = row['section_id'] as String?;
        if (!seen.add('$program|$year|$sectionId')) continue;
        facets.add(StudentFilterFacet(
          program: program,
          yearLevel: year,
          sectionId: sectionId,
          sectionName: (row['sections'] as Map<String, dynamic>?)?['name']
              as String?,
        ));
      }
      if (list.length < batch) break;
    }
    return facets;
  }

  /// First-login self-registration for a Microsoft-authenticated student
  /// profile with no `students` row yet. The student number is derived
  /// server-side from the caller's own verified email (never taken from the
  /// form) — see `complete_student_registration` in
  /// supabase/add_student_self_registration_schema.sql.
  Future<void> completeSelfRegistration({
    required String firstName,
    required String middleInitial,
    required String lastName,
    required String course,
    required int yearLevel,
    required String sectionName,
  }) async {
    final sectionId = await findSectionId(
      program: course,
      yearLevel: yearLevel,
      sectionName: sectionName,
    );
    if (sectionId == null) {
      throw StudentsRepositoryException(
        'No section named "$sectionName" for program "$course" and year $yearLevel '
        '(expected `sections.name`, `sections.program`, `sections.year_level`). '
        'Confirm the row exists in Supabase Table Editor and that RLS allows SELECT on '
        '`sections` for role `authenticated`.',
      );
    }

    try {
      await _client.rpc('complete_student_registration', params: {
        'p_first_name': firstName.trim(),
        'p_middle_initial': middleInitial.trim(),
        'p_last_name': lastName.trim(),
        'p_course': course,
        'p_year_level': yearLevel,
        'p_section_id': sectionId,
      });
    } on PostgrestException catch (e) {
      throw StudentsRepositoryException(e.message);
    }
  }

  /// Re-homes a pre-registered (RFID-Manager-created) student record onto
  /// the currently signed-in Microsoft account, when both share the same
  /// (email-derived) student number. See `claim_preregistered_student` in
  /// supabase/add_student_self_registration_schema.sql.
  Future<void> claimPreregisteredStudent() async {
    try {
      await _client.rpc('claim_preregistered_student');
    } on PostgrestException catch (e) {
      throw StudentsRepositoryException(e.message);
    }
  }

  Future<String?> findSectionId({
    required String program,
    required int yearLevel,
    required String sectionName,
  }) async {
    final row = await _client
        .from('sections')
        .select('id')
        .eq('program', program)
        .eq('year_level', yearLevel)
        .eq('name', sectionName.trim())
        .maybeSingle();
    return row?['id'] as String?;
  }

  Future<StudentRecord> create({
    required String studentNumber,
    required String rfidUid,
    required String firstName,
    required String middleInitial,
    required String lastName,
    required String course,
    required int yearLevel,
    required String sectionName,
    required String guardianContactNo,
    String guardianName = '',
    String? email,
    String? phoneNumber,
  }) async {
    final sectionId = await findSectionId(
      program: course,
      yearLevel: yearLevel,
      sectionName: sectionName,
    );
    if (sectionId == null) {
      throw StudentsRepositoryException(
        'No section named "$sectionName" for program "$course" and year $yearLevel '
        '(expected `sections.name`, `sections.program`, `sections.year_level`). '
        'Confirm the row exists in Supabase Table Editor and that RLS allows SELECT on '
        '`sections` for role `anon` (see supabase/rls_sections_select.sql).',
      );
    }

    final authRes = await _client.auth.signInAnonymously(
      data: {'student_number': studentNumber.trim()},
    );
    final user = authRes.user;
    if (user == null || authRes.session == null) {
      throw StudentsRepositoryException(
        'Could not create a test auth user. In Supabase: Authentication → '
        'Sign In / Providers → enable Anonymous sign-ins.',
      );
    }

    final id = user.id;
    final composedFirst =
        StudentRecord.composeFirstName(firstName, middleInitial);

    await _client.from('profiles').upsert({
      'id': id,
      'first_name': composedFirst,
      'last_name': lastName.trim(),
      'role': AppEnv.profileRoleStudent,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
        'phone_number': phoneNumber.trim(),
    }, onConflict: 'id');

    await _client.from('students').insert({
      'id': id,
      'student_number': studentNumber.trim(),
      'rfid_uid': rfidUid.trim().isEmpty ? null : rfidUid.trim(),
      'course': course,
      'year_level': yearLevel,
      'section_id': sectionId,
      'guardian_contact_no':
          guardianContactNo.trim().isEmpty ? null : guardianContactNo.trim(),
      'guardian_name':
          guardianName.trim().isEmpty ? null : guardianName.trim(),
    });

    final created = await _fetchById(id);
    await _client.auth.signOut();

    return created;
  }

  Future<StudentRecord> update({
    required String id,
    required String studentNumber,
    required String rfidUid,
    required String firstName,
    required String middleInitial,
    required String lastName,
    required String course,
    required int yearLevel,
    required String sectionName,
    required String guardianContactNo,
    String? guardianName,
  }) async {
    final sectionId = await findSectionId(
      program: course,
      yearLevel: yearLevel,
      sectionName: sectionName,
    );
    if (sectionId == null) {
      throw StudentsRepositoryException(
        'No section named "$sectionName" for program "$course" and year $yearLevel. '
        'Check Table Editor + RLS on `sections` (see supabase/rls_sections_select.sql).',
      );
    }

    final updated = await _client
        .from('students')
        .update({
          'student_number': studentNumber.trim(),
          'rfid_uid': rfidUid.trim().isEmpty ? null : rfidUid.trim(),
          'course': course,
          'year_level': yearLevel,
          'section_id': sectionId,
          'guardian_contact_no': guardianContactNo.trim().isEmpty
              ? null
              : guardianContactNo.trim(),
          // null = caller doesn't manage the guardian name: leave it untouched.
          if (guardianName != null)
            'guardian_name':
                guardianName.trim().isEmpty ? null : guardianName.trim(),
        })
        .eq('id', id)
        .select('id');
    // RLS-blocked updates return success with zero rows (see
    // supabase/add_students_update_policy.sql) — surface that instead of
    // letting the form close as if the save worked.
    if ((updated as List<dynamic>).isEmpty) {
      throw StudentsRepositoryException(
        'The student record was not updated. Run '
        'supabase/add_students_update_policy.sql so your account may edit '
        'students.',
      );
    }

    await _client.from('profiles').update({
      'first_name': StudentRecord.composeFirstName(firstName, middleInitial),
      'last_name': lastName.trim(),
    }).eq('id', id);

    return _fetchById(id);
  }

  /// The Registrar's "Edit Student Details": personal + guardian fields only.
  /// Narrower than [update] on purpose — it never touches course/year/section
  /// (the separate "Change Section" action owns those, as one consistent
  /// unit) or the RFID card, so saving this form can't clobber either.
  ///
  /// Each write is checked for matching a row. A blocked update (RLS, or a
  /// stale id) otherwise comes back as success with nothing changed — see
  /// supabase/add_students_update_policy.sql — which would show the
  /// Registrar a false "saved".
  Future<void> updateDetails({
    required String id,
    required String studentNumber,
    required String firstName,
    required String middleInitial,
    required String lastName,
    required String email,
    required String phoneNumber,
    required String guardianName,
    required String guardianContactNo,
  }) async {
    try {
      final studentRows = await _client
          .from('students')
          .update({
            'student_number': studentNumber.trim(),
            'guardian_name':
                guardianName.trim().isEmpty ? null : guardianName.trim(),
            'guardian_contact_no': guardianContactNo.trim().isEmpty
                ? null
                : guardianContactNo.trim(),
          })
          .eq('id', id)
          .select('id');
      if ((studentRows as List<dynamic>).isEmpty) {
        throw StudentsRepositoryException(
          'The student record was not updated. Check that your account may '
          'edit students (supabase/add_students_update_policy.sql).',
        );
      }

      final profileRows = await _client
          .from('profiles')
          .update({
            'first_name':
                StudentRecord.composeFirstName(firstName, middleInitial),
            'last_name': lastName.trim(),
            'email': email.trim().isEmpty ? null : email.trim(),
            'phone_number':
                phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
          })
          .eq('id', id)
          .select('id');
      if ((profileRows as List<dynamic>).isEmpty) {
        throw StudentsRepositoryException(
          'The student\'s name/contact were not updated. Run '
          'supabase/add_student_guardian_name.sql so staff may edit student '
          'profiles.',
        );
      }
    } on PostgrestException catch (e) {
      final duplicate = e.code == '23505';
      throw StudentsRepositoryException(
        duplicate
            ? 'That student number or email is already used by another student.'
            : e.message,
      );
    }
  }

  /// Reassigns [studentId] to a different section — the Registrar's
  /// "override" action for a student who landed in the wrong section
  /// after a batch enrollment upload (see EnrollmentImportRunner's
  /// automatic per-program/level placement). Narrower than [update]: only
  /// `course`/`year_level`/`section_id` change, since the caller already
  /// has a resolved section (id + its own program/year) rather than
  /// needing to re-resolve one from typed-in text — and this action has
  /// nothing to do with the student's name, RFID, or guardian contact.
  Future<void> updateSection({
    required String studentId,
    required String sectionId,
    required String course,
    required int yearLevel,
  }) async {
    await _client.from('students').update({
      'section_id': sectionId,
      'course': course,
      'year_level': yearLevel,
    }).eq('id', studentId);
  }

  Future<void> deleteById(String id) async {
    await _client.from('students').delete().eq('id', id);
  }

  /// Attaches [rfidUid] to an already-known student without touching any
  /// of their other fields — backs the IT Technician's "Assign" action on
  /// a pending RFID request, where course/section/guardian info are
  /// already correct and only the card number is missing. [update] covers
  /// the full Student Records edit form instead, where every field can
  /// change at once.
  Future<void> updateRfidUid({
    required String studentId,
    required String rfidUid,
  }) async {
    await _client.from('students').update({
      'rfid_uid': rfidUid.trim().isEmpty ? null : rfidUid.trim(),
    }).eq('id', studentId);
  }

  static const _photoBucket = 'student-photos';

  /// Uploads a freshly-captured ID photo and records its path on the
  /// student's row — backs the IT Technician's webcam capture for ID card
  /// printing. Returns the stored path (same shape as
  /// [StudentRecord.photoPath]).
  Future<String> uploadStudentPhoto({
    required String studentId,
    required Uint8List bytes,
  }) async {
    final path = '$studentId.jpg';
    await _client.storage.from(_photoBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    await _client.from('students').update({'photo_path': path}).eq('id', studentId);
    return path;
  }

  /// Resolves [photoPath] (a Storage object path, not a URL — the bucket is
  /// private) to a time-limited signed URL, or null if [photoPath] is null.
  Future<String?> fetchStudentPhotoUrl(String? photoPath) async {
    if (photoPath == null || photoPath.isEmpty) return null;
    return _client.storage.from(_photoBucket).createSignedUrl(photoPath, 3600);
  }

  static const _signatureBucket = 'student-signatures';

  /// Uploads a freshly-captured signature and records its path on the
  /// student's row — mirrors [uploadStudentPhoto] exactly, backing the
  /// Print ID flow's signature-capture step.
  Future<String> uploadStudentSignature({
    required String studentId,
    required Uint8List bytes,
  }) async {
    final path = '$studentId.png';
    await _client.storage.from(_signatureBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );
    await _client
        .from('students')
        .update({'signature_path': path}).eq('id', studentId);
    return path;
  }

  /// Resolves [signaturePath] to a time-limited signed URL, or null if
  /// [signaturePath] is null — mirrors [fetchStudentPhotoUrl] exactly.
  Future<String?> fetchStudentSignatureUrl(String? signaturePath) async {
    if (signaturePath == null || signaturePath.isEmpty) return null;
    return _client.storage
        .from(_signatureBucket)
        .createSignedUrl(signaturePath, 3600);
  }

  Future<StudentRecord> _fetchById(String id) async {
    final row = await _client
        .from('students')
        .select(_selectEmbed)
        .eq('id', id)
        .single();
    return StudentRecord.fromSupabase(row);
  }
}
