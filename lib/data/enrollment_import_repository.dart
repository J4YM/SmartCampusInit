import 'package:supabase_flutter/supabase_flutter.dart';

import 'enrollment_import/enrollment_import_row.dart';
import '../env.dart';
import '../models/student_record.dart';

/// Resolves/commits one [EnrollmentImportRow] at a time against
/// `students`/`profiles` — the Supabase half of the batch enrollment
/// import, mirroring ScheduleImportRepository's own split from its
/// pure-Dart parser (enrollment_import/enrollment_file_parser.dart).
///
/// A brand-new student needs the same "sign in anonymously, write the
/// row, sign out" dance StudentsRepository.create() already does for the
/// Registrar's single "Add New Student" form: RLS on `students`/
/// `profiles` expects a real `auth.uid()` matching the row's own id, and
/// there's no service-role API available from a client app to mint one
/// directly. Reusing the exact same primitive here (rather than inventing
/// a bulk-safe alternative) matches this codebase's usual "don't redesign
/// beyond what's asked" bar — it's already the accepted, shipped
/// behavior for creating a student, just looped once per new row in the
/// file instead of once per form submission.
class EnrollmentImportRepository {
  EnrollmentImportRepository(this._client);
  final SupabaseClient _client;

  /// Returns true if [row] was newly created, false if an existing
  /// student (matched by `student_number`) was updated instead. An
  /// update only ever touches fields this row actually carries — a batch
  /// file re-upload must never blank out an already-assigned RFID card or
  /// guardian contact number just because this format doesn't carry
  /// either.
  Future<bool> upsertStudent(
    EnrollmentImportRow row, {
    required String sectionId,
    required String course,
    required int yearLevel,
  }) async {
    final existing = await _client
        .from('students')
        .select('id')
        .eq('student_number', row.studentNumber)
        .maybeSingle();

    final middleName = row.middleName?.trim();
    final middleInitial =
        (middleName != null && middleName.isNotEmpty) ? middleName[0] : '';
    final composedFirst =
        StudentRecord.composeFirstName(row.firstName, middleInitial);
    final lastName =
        row.suffix == null ? row.lastName.trim() : '${row.lastName.trim()} ${row.suffix}';
    final email = row.email?.trim();

    if (existing != null) {
      final id = existing['id'] as String;
      await _client.from('students').update({
        'course': course,
        'year_level': yearLevel,
        'section_id': sectionId,
      }).eq('id', id);
      await _client.from('profiles').update({
        'first_name': composedFirst,
        'last_name': lastName,
        if (email != null && email.isNotEmpty) 'email': email,
      }).eq('id', id);
      return false;
    }

    final authRes = await _client.auth.signInAnonymously(
      data: {'student_number': row.studentNumber.trim()},
    );
    final user = authRes.user;
    if (user == null || authRes.session == null) {
      throw StateError(
        'Could not create an auth identity for ${row.studentNumber} — '
        'in Supabase: Authentication → Sign In / Providers → enable '
        'Anonymous sign-ins.',
      );
    }
    final id = user.id;

    await _client.from('profiles').upsert({
      'id': id,
      'first_name': composedFirst,
      'last_name': lastName,
      'role': AppEnv.profileRoleStudent,
      if (email != null && email.isNotEmpty) 'email': email,
    }, onConflict: 'id');

    await _client.from('students').insert({
      'id': id,
      'student_number': row.studentNumber.trim(),
      'course': course,
      'year_level': yearLevel,
      'section_id': sectionId,
    });

    await _client.auth.signOut();
    return true;
  }
}
