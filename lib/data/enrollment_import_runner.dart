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
  });

  final int created;
  final int updated;

  /// One human-readable message per row that failed to commit — the rest
  /// of the file is still imported; matches ScheduleImportSummary's own
  /// "here's what didn't make it in" convention rather than aborting the
  /// whole batch over one bad row.
  final List<String> errors;
}

/// Ties the pure-Dart enrollment file parser
/// (enrollment_import/enrollment_file_parser.dart) to
/// [EnrollmentImportRepository]'s Supabase create-or-update — the same
/// "upload a file, get real rows" shape as ScheduleImportRunner. Every
/// student in the file is assigned to the ONE section the Registrar
/// picked before uploading (this format's own "Program"/"Level" columns
/// are used for a row's `course`/`year_level` when present, falling back
/// to that chosen section's own program/year when a cell is blank or
/// unparseable — see EnrollmentImportRow's own doc comment for why they
/// need not agree exactly).
class EnrollmentImportRunner {
  EnrollmentImportRunner(this._repository);
  final EnrollmentImportRepository _repository;

  Future<EnrollmentImportSummary> run({
    required Uint8List xlsxBytes,
    required String sectionId,
    required String sectionProgram,
    required int sectionYearLevel,
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
    for (final row in parsed) {
      try {
        final isNew = await _repository.upsertStudent(
          row,
          sectionId: sectionId,
          course: row.course ?? sectionProgram,
          yearLevel: row.yearLevel ?? sectionYearLevel,
        );
        if (isNew) {
          created++;
        } else {
          updated++;
        }
      } catch (e) {
        errors.add(
          '${row.studentNumber} (${row.firstName} ${row.lastName}): $e',
        );
      }
    }

    return EnrollmentImportSummary(
      created: created,
      updated: updated,
      errors: errors,
    );
  }
}
