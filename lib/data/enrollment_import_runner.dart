import 'dart:typed_data';

import 'enrollment_import/enrollment_file_parser.dart';
import 'enrollment_import_repository.dart';
import 'schedule_import/xlsx_reader.dart';

class EnrollmentImportException implements Exception {
  EnrollmentImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Result of one [EnrollmentImportRunner.run] call.
class EnrollmentImportSummary {
  const EnrollmentImportSummary({
    required this.created,
    required this.updated,
    required this.errors,
    required this.capWarnings,
    this.rateLimitMessage,
  });

  final int created;
  final int updated;

  /// One human-readable message per row that failed to commit — the rest
  /// of the file is still imported; matches ScheduleImportSummary's own
  /// "here's what didn't make it in" convention rather than aborting the
  /// whole batch over one bad row. A row with no Program/Level, or one
  /// whose program+level has no section at all, ends up here — there's no
  /// section id to assign in either case. Never includes the rate-limit
  /// stop message — see [rateLimitMessage].
  final List<String> errors;

  /// Non-null when the import stopped partway through because Supabase
  /// Auth's account-creation rate limit was hit and stayed active past
  /// [EnrollmentImportRepository]'s own retries — every remaining new-
  /// student/new-guardian row needs the identical signInAnonymously call
  /// and would fail the same way, so the runner stops immediately instead
  /// of recording dozens of identical failures. Kept separate from
  /// [errors] (rather than appended to it) since rows processed earlier
  /// may have already added their own unrelated errors — this field is
  /// always exactly the one stop reason, regardless of list order.
  /// [created]/[updated] still reflect everything that succeeded before
  /// the limit was hit. Re-running the same file later picks up where
  /// this left off: a row already created is recognized as existing (an
  /// update, no new auth call needed) and only the still-missing rows
  /// attempt to create a new account again.
  final String? rateLimitMessage;

  /// One message per student who WAS assigned, but into a section already
  /// at or past the target per-section cap ([kSectionCapTarget]) — every
  /// section for that program/level was already full, so the least-full
  /// one was used anyway rather than leaving the student unplaced. Not an
  /// error: the student is enrolled, this is just a "you may want to
  /// rebalance" flag for the Registrar.
  final List<String> capWarnings;
}

/// The per-section target used to decide when a section counts as "full"
/// for [EnrollmentImportSummary.capWarnings] purposes. Not a hard limit —
/// every program/level's sections still get filled (least-full first)
/// even once every one of them is at or past this count; there just isn't
/// anywhere better left to put the student.
const kSectionCapTarget = 30;

/// Ties the pure-Dart enrollment file parser
/// (enrollment_import/enrollment_file_parser.dart) to
/// [EnrollmentImportRepository]'s Supabase create-or-update — the same
/// "upload a file, get real rows" shape as ScheduleImportRunner.
///
/// Each student's section is chosen automatically from their own row's
/// Program/Level columns — NOT a single section picked upfront for the
/// whole batch: within the sections that already exist for that program/
/// level, the least-currently-enrolled one is used, so a batch spanning
/// several sections' worth of students spreads across them instead of
/// piling into whichever one section a Registrar happened to pick. A
/// program/level with no matching section at all (never created via the
/// Class Schedule tab or a CFL/Room Schedule upload) fails that row with
/// a clear error rather than guessing.
class EnrollmentImportRunner {
  EnrollmentImportRunner(this._repository);
  final EnrollmentImportRepository _repository;

  Future<EnrollmentImportSummary> run({
    required Uint8List xlsxBytes,
  }) async {
    final rows = readFirstSheetRows(xlsxBytes);
    final parsed = parseEnrollmentFile(rows);
    if (parsed.isEmpty) {
      throw EnrollmentImportException(
        'No student rows found — expected a "Student ID" column header '
        'somewhere in the file, followed by one row per student.',
      );
    }

    var created = 0;
    var updated = 0;
    final errors = <String>[];
    final capWarnings = <String>[];
    final candidatesByProgramLevel = <String, List<SectionCandidate>>{};
    String? rateLimitMessage;

    for (final row in parsed) {
      final label = '${row.studentNumber} (${row.firstName} ${row.lastName})';
      try {
        final course = row.course;
        final yearLevel = row.yearLevel;
        if (course == null || yearLevel == null) {
          throw StateError(
            'Missing or unrecognized Program/Level in the file — cannot '
            'determine which section to assign.',
          );
        }

        final key = '$course::$yearLevel';
        var candidates = candidatesByProgramLevel[key];
        if (candidates == null) {
          candidates = await _repository.fetchSectionCandidates(
            course: course,
            yearLevel: yearLevel,
          );
          candidatesByProgramLevel[key] = candidates;
        }
        if (candidates.isEmpty) {
          throw StateError(
            'No section exists yet for $course year $yearLevel — create '
            'one (Class Schedule tab, or a CFL/Room Schedule upload) '
            'before batch-enrolling this program/level.',
          );
        }

        candidates.sort((a, b) => a.currentCount.compareTo(b.currentCount));
        final chosen = candidates.first;
        if (chosen.currentCount >= kSectionCapTarget) {
          capWarnings.add(
            '$label: enrolled into ${chosen.name}, which already has '
            '${chosen.currentCount} student(s) (target cap is '
            '$kSectionCapTarget) — every section for $course year '
            '$yearLevel is at or past that target.',
          );
        }
        chosen.currentCount++;

        final isNew = await _repository.upsertStudent(
          row,
          sectionId: chosen.id,
          course: course,
          yearLevel: yearLevel,
        );
        if (isNew) {
          created++;
        } else {
          updated++;
        }
      } on EnrollmentRateLimitExceeded {
        rateLimitMessage =
            'Stopped at $label: Supabase\'s account-creation rate limit was '
            'reached after $created new student(s) (and any linked '
            'guardians). The remaining rows were not attempted. Wait a few '
            'minutes, then re-upload this same file — students already '
            'created are recognized as existing and only the rest will be '
            'processed. If this keeps happening, raise the "Anonymous '
            'sign-ins" rate limit for this project in the Supabase '
            'dashboard (Authentication → Rate Limits).';
        break;
      } catch (e) {
        errors.add('$label: $e');
      }
    }

    return EnrollmentImportSummary(
      created: created,
      updated: updated,
      errors: errors,
      capWarnings: capWarnings,
      rateLimitMessage: rateLimitMessage,
    );
  }
}
