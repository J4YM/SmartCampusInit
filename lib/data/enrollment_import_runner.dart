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
    this.sectionsCreated = const [],
  });

  final int created;
  final int updated;

  /// One human-readable message per row that failed to commit — the rest
  /// of the file is still imported; matches ScheduleImportSummary's own
  /// "here's what didn't make it in" convention rather than aborting the
  /// whole batch over one bad row. A row with no Program/Level, or one
  /// whose section couldn't be found or created, ends up here — there's no
  /// section id to assign in either case.
  final List<String> errors;

  /// One message per student who WAS assigned into a section already at or
  /// past the target per-section cap ([kSectionCapTarget]) because a new
  /// section couldn't be created (normally one is, so this stays empty).
  /// Not an error: the student is enrolled, this is just a "you may want
  /// to rebalance" flag for the Registrar.
  final List<String> capWarnings;

  /// Names of the sections this run created (no section existed for a
  /// program/level, or every one was at [kSectionCapTarget]).
  final List<String> sectionsCreated;
}

/// How many students a section holds before the import opens the next one
/// ("BSIT 1A" -> "BSIT 1B"). If a new section can't be created the
/// least-full existing one is still used (see
/// [EnrollmentImportSummary.capWarnings]) rather than leaving the student
/// unplaced.
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
/// piling into whichever one section a Registrar happened to pick. When a
/// program/level has no section yet, or every one already holds
/// [kSectionCapTarget] students, the next section is created on the spot.
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
    final sectionsCreated = <String>[];
    final candidatesByProgramLevel = <String, List<SectionCandidate>>{};

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
        candidates.sort((a, b) => a.currentCount.compareTo(b.currentCount));
        var chosen = candidates.isEmpty ? null : candidates.first;

        // No section yet, or every one is at the cap: open the next one
        // ("BSIT 1A" -> "BSIT 1B") instead of overfilling or skipping the
        // student. It joins `candidates`, so the rest of the batch fills it.
        if (chosen == null || chosen.currentCount >= kSectionCapTarget) {
          try {
            final created = await _repository.createSection(
              course: course,
              yearLevel: yearLevel,
              existing: candidates,
            );
            candidates.add(created);
            sectionsCreated.add(created.name);
            chosen = created;
          } catch (e) {
            if (chosen == null) {
              throw StateError(
                'No section exists yet for $course year $yearLevel and a '
                'new one could not be created: $e',
              );
            }
            capWarnings.add(
              '$label: enrolled into ${chosen.name}, which already has '
              '${chosen.currentCount} student(s) (target cap is '
              '$kSectionCapTarget) — every section for $course year '
              '$yearLevel is at or past that target and a new one could '
              'not be created: $e',
            );
          }
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
      } catch (e) {
        errors.add('$label: $e');
      }
    }

    return EnrollmentImportSummary(
      created: created,
      updated: updated,
      errors: errors,
      capWarnings: capWarnings,
      sectionsCreated: sectionsCreated,
    );
  }
}
