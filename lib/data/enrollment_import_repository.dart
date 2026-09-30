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
/// One candidate section a batch-enrolled student could land in — same
/// (program, year_level) as the student, with however many students are
/// *currently* enrolled there. [currentCount] is deliberately mutable:
/// EnrollmentImportRunner increments it in place as it assigns students
/// from the same batch, so the 2nd/3rd/... student for a given program+
/// level sees the 1st/2nd/...'s assignment reflected immediately, instead
/// of every row in the batch racing for whichever section looked
/// least-full at the start of the whole import.
class SectionCandidate {
  SectionCandidate({
    required this.id,
    required this.name,
    required this.currentCount,
  });

  final String id;
  final String name;
  int currentCount;
}

class EnrollmentImportRepository {
  EnrollmentImportRepository(this._client);
  final SupabaseClient _client;

  /// Derives the school email `lastname.NNNNNN@baliuag.sti.edu.ph`
  /// (matching `handle_new_auth_user`'s regex in
  /// add_oauth_role_approval_schema.sql) from a row's own last name and
  /// student number, rather than trusting the file's own "Campus Email
  /// Address" column — that column's real-world values don't reliably
  /// match the regex a student actually needs to sign in and later "claim"
  /// this record via Microsoft. The 6-digit number is always the LAST six
  /// digits of the student number's digits (confirmed against real data:
  /// a real Student ID like "02000250559" embeds it that way), regardless
  /// of what punctuation/prefix the file's own Student ID column uses.
  /// Returns null when the row doesn't carry at least 6 digits to derive
  /// from — callers leave the email untouched in that case rather than
  /// writing a garbage address.
  static String? deriveSchoolEmail({
    required String lastName,
    required String studentNumber,
  }) {
    final digits = studentNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) return null;
    final number = digits.substring(digits.length - 6);

    final namePart = lastName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z\s]'), '')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join('.');
    if (namePart.isEmpty) return null;

    return '$namePart.$number@baliuag.sti.edu.ph';
  }

  /// Every section for [course]/[yearLevel], with how many students are
  /// currently assigned to each — the pool EnrollmentImportRunner picks
  /// the least-full section from for every row sharing that program/year.
  /// Empty when no section exists at all for that combination (the
  /// Registrar needs to create one first — via the Class Schedule tab or
  /// a CFL/Room Schedule upload — before this program/level can be
  /// batch-enrolled).
  Future<List<SectionCandidate>> fetchSectionCandidates({
    required String course,
    required int yearLevel,
  }) async {
    final sections = await _client
        .from('sections')
        .select('id, name')
        .eq('program', course)
        .eq('year_level', yearLevel);
    final sectionRows = sections as List;
    if (sectionRows.isEmpty) return [];

    final sectionIds = [for (final s in sectionRows) s['id'] as String];
    final students = await _client
        .from('students')
        .select('section_id')
        .inFilter('section_id', sectionIds);

    final counts = <String, int>{for (final id in sectionIds) id: 0};
    for (final row in students as List) {
      final sectionId = row['section_id'] as String?;
      if (sectionId != null) counts[sectionId] = (counts[sectionId] ?? 0) + 1;
    }

    return [
      for (final s in sectionRows)
        SectionCandidate(
          id: s['id'] as String,
          name: s['name'] as String,
          currentCount: counts[s['id'] as String] ?? 0,
        ),
    ];
  }

  /// Returns true if [row] was newly created, false if an existing
  /// student (matched by `student_number`) was updated instead. Name and
  /// the derived school email (see [deriveSchoolEmail]) always overwrite —
  /// the batch file is the source of truth, including over a name a
  /// student may have entered via self-registration. Fields this row
  /// simply has no column for at all (RFID card, guardian contact number)
  /// are left untouched either way; a re-upload must never blank those out
  /// just because this format doesn't carry them.
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
    final derivedEmail = deriveSchoolEmail(
      lastName: row.lastName,
      studentNumber: row.studentNumber,
    );

    if (existing != null) {
      final id = existing['id'] as String;
      await _client.from('students').update({
        'course': course,
        'year_level': yearLevel,
        'section_id': sectionId,
      }).eq('id', id);
      // The batch file always overwrites — including a name or email a
      // student may have set via self-registration — so a re-upload can't
      // be defeated by tampered-with names already on file.
      await _client.from('profiles').update({
        'first_name': composedFirst,
        'last_name': lastName,
        if (derivedEmail != null) 'email': derivedEmail,
      }).eq('id', id);
      await _linkGuardian(
        studentId: id,
        guardianName: row.guardianName,
        guardianEmail: row.guardianEmail,
      );
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
      if (derivedEmail != null) 'email': derivedEmail,
    }, onConflict: 'id');

    await _client.from('students').insert({
      'id': id,
      'student_number': row.studentNumber.trim(),
      'course': course,
      'year_level': yearLevel,
      'section_id': sectionId,
    });

    await _client.auth.signOut();

    // Runs after signOut(): linking a guardian mints its own, separate
    // anonymous identity (when the guardian has no account yet) and must
    // not happen while the client is still signed in as the student.
    await _linkGuardian(
      studentId: id,
      guardianName: row.guardianName,
      guardianEmail: row.guardianEmail,
    );
    return true;
  }

  /// Creates (or reuses) a Parent [profiles] row for [guardianEmail] and
  /// links it to [studentId] via `parent_student_links` — the same
  /// anonymous-sign-in primitive `StudentsRepository.create()` already uses
  /// for students, since there's no service-role API from a client app to
  /// mint an auth identity any other way. A no-op when the row carries no
  /// guardian email at all (not every batch file row has one).
  ///
  /// Silently declines to touch a profile whose email is already on file
  /// under a different role (e.g. staff) — an email collision there means
  /// this isn't actually the same person, so guessing would risk linking a
  /// student to a stranger's staff account.
  Future<void> _linkGuardian({
    required String studentId,
    String? guardianName,
    String? guardianEmail,
  }) async {
    final email = guardianEmail?.trim().toLowerCase();
    if (email == null || email.isEmpty) return;
    final name = guardianName?.trim();

    final existing = await _client
        .from('profiles')
        .select('id, role')
        .eq('email', email)
        .maybeSingle();

    final String parentId;
    if (existing != null) {
      final role = existing['role'] as String?;
      if (role != null && role != 'Parent') return;
      parentId = existing['id'] as String;
      if (name != null && name.isNotEmpty) {
        await _client.from('profiles').update({
          'first_name': name,
          'last_name': '',
        }).eq('id', parentId);
      }
    } else {
      final authRes = await _client.auth.signInAnonymously(
        data: {'guardian_email': email},
      );
      final user = authRes.user;
      if (user == null || authRes.session == null) {
        throw StateError('Could not create a parent account for $email.');
      }
      parentId = user.id;
      await _client.from('profiles').upsert({
        'id': parentId,
        'first_name': (name != null && name.isNotEmpty) ? name : 'Guardian',
        'last_name': '',
        'role': 'Parent',
        'email': email,
      }, onConflict: 'id');
      await _client.auth.signOut();
    }

    final existingLink = await _client
        .from('parent_student_links')
        .select('parent_id')
        .eq('parent_id', parentId)
        .eq('student_id', studentId)
        .maybeSingle();
    if (existingLink == null) {
      await _client.from('parent_student_links').insert({
        'parent_id': parentId,
        'student_id': studentId,
      });
    }
  }
}
