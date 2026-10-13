import 'dart:typed_data';

import 'grade_import/grade_file_parser.dart';
import 'grade_import_repository.dart';
import 'schedule_import/xlsx_reader.dart';

class GradeImportException implements Exception {
  GradeImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Result of one [GradeImportRunner.run] call.
class GradeImportSummary {
  const GradeImportSummary({
    required this.schoolYear,
    required this.term,
    required this.imported,
    required this.skipped,
    required this.errors,
    this.skippedStudents = const [],
  });

  final String schoolYear;
  final String term;
  final int imported;

  /// Rows whose student number has no matching `students` row yet — not
  /// errors, see [GradeImportRepository.upsertGpaRecord]'s own doc comment.
  final int skipped;
  final List<String> errors;

  /// "number (First Last)" for each skipped row, so the Registrar can see
  /// exactly who still needs a batch enrollment (or a number correction).
  final List<String> skippedStudents;
}

/// Ties the pure-Dart GPA file parser (grade_import/grade_file_parser.dart)
/// to [GradeImportRepository]'s Supabase upsert — the same "upload a file,
/// get real rows" shape as EnrollmentImportRunner/ScheduleImportRunner.
class GradeImportRunner {
  GradeImportRunner(this._repository);
  final GradeImportRepository _repository;

  Future<GradeImportSummary> run({required Uint8List xlsxBytes}) async {
    final rows = readFirstSheetRows(xlsxBytes);
    final parsed = parseGradeFile(rows);
    if (parsed == null || parsed.rows.isEmpty) {
      throw GradeImportException(
        'No student GPA rows found — expected an "SY & Term:" row and a '
        '"Student ID" column header somewhere in the file, followed by one '
        'row per student.',
      );
    }

    var imported = 0;
    final skippedStudents = <String>[];
    final errors = <String>[];

    for (final row in parsed.rows) {
      final label = '${row.studentNumber} (${row.firstName} ${row.lastName})';
      try {
        final matched = await _repository.upsertGpaRecord(
          row,
          schoolYear: parsed.schoolYear,
          term: parsed.term,
        );
        if (matched) {
          imported++;
        } else {
          skippedStudents.add(label);
        }
      } catch (e) {
        errors.add('$label: $e');
      }
    }

    return GradeImportSummary(
      schoolYear: parsed.schoolYear,
      term: parsed.term,
      imported: imported,
      skipped: skippedStudents.length,
      errors: errors,
      skippedStudents: skippedStudents,
    );
  }
}
