import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../models/student_record.dart';

class StudentsRepositoryException implements Exception {
  StudentsRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
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
