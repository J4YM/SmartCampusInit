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

  /// One page of students (1-indexed) plus the total row count matching
  /// [course]/[yearLevel] — used by the Student Directory so the dashboard
  /// never has to load the whole table (potentially hundreds of rows) just
  /// to show one screenful.
  ///
  /// Free-text search isn't included here: it stays client-side, scoped to
  /// whatever page is currently loaded (searching a name across every page
  /// would need filtering through the `profiles` embed, which Postgrest
  /// only applies correctly with an inner-join hint — left as a follow-up
  /// rather than risking a silently-wrong filter).
  Future<({List<StudentRecord> items, int totalCount})> fetchPage({
    required int page,
    int pageSize = 25,
    String? course,
    int? yearLevel,
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
    }, onConflict: 'id');

    await _client.from('students').insert({
      'id': id,
      'student_number': studentNumber.trim(),
      'rfid_uid': rfidUid.trim().isEmpty ? null : rfidUid.trim(),
      'course': course,
      'year_level': yearLevel,
      'section_id': sectionId,
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

    await _client.from('students').update({
      'student_number': studentNumber.trim(),
      'rfid_uid': rfidUid.trim().isEmpty ? null : rfidUid.trim(),
      'course': course,
      'year_level': yearLevel,
      'section_id': sectionId,
    }).eq('id', id);

    await _client.from('profiles').update({
      'first_name': StudentRecord.composeFirstName(firstName, middleInitial),
      'last_name': lastName.trim(),
    }).eq('id', id);

    return _fetchById(id);
  }

  Future<void> deleteById(String id) async {
    await _client.from('students').delete().eq('id', id);
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
