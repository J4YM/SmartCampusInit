import 'dart:typed_data';

import 'registrar_repository.dart';
import 'schedule_import/schedule_file_parser.dart';
import 'schedule_import/schedule_import_row.dart';
import 'schedule_import/xlsx_reader.dart';
import 'schedule_import_repository.dart';

class ScheduleImportException implements Exception {
  ScheduleImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One (subject, section, professor) offering's meetings, grouped out of a
/// parsed file's flat row list — everything [ScheduleImportRepository]
/// needs to resolve and commit one `class_sections` row at a time.
class _Offering {
  _Offering({
    required this.subjectTitle,
    this.subjectCode,
    this.sectionName,
    this.professorName,
    this.instructorId,
  });

  final String subjectTitle;
  final String? subjectCode;
  final String? sectionName;
  final String? professorName;
  final String? instructorId;
  final List<ScheduleImportRow> meetings = [];
}

/// Result of one [ScheduleImportRunner.run] call — enough for the import
/// dialog to show a plain-language summary without the caller having to
/// inspect individual repository exceptions itself.
class ScheduleImportSummary {
  const ScheduleImportSummary({
    required this.format,
    required this.offeringsCommitted,
    required this.meetingsCommitted,
    required this.errors,
  });

  final ScheduleFileFormat format;
  final int offeringsCommitted;
  final int meetingsCommitted;

  /// One human-readable message per offering that failed to resolve/commit
  /// (e.g. a new subject with no course code) — the rest of the file is
  /// still committed; this isn't a review-and-fix-everything screen, just
  /// a "here's what didn't make it in" report.
  final List<String> errors;
}

/// Ties the pure-Dart parser (lib/data/schedule_import/) and
/// [ScheduleImportRepository]'s Supabase resolution/commit together into
/// the single "upload a file, get a schedule" operation the Registrar's
/// Import Schedule dialog drives. Deliberately not itself a review screen:
/// every offering is matched/created automatically using the same rules
/// [ScheduleImportRepository] already implements (exact code match,
/// normalized name match, placeholder-professor auto-create); anything
/// that still can't resolve is reported back as an error rather than
/// asked about interactively — a fuller conflict-resolution UI is a later
/// enhancement, not required for the import to actually work.
class ScheduleImportRunner {
  ScheduleImportRunner({
    required this.scheduleImportRepository,
    required this.registrarRepository,
  });

  final ScheduleImportRepository scheduleImportRepository;
  final RegistrarRepository registrarRepository;

  Future<ScheduleImportSummary> run({
    required Uint8List xlsxBytes,
    required String schoolYear,
    required String term,
  }) async {
    final rows = readFirstSheetRows(xlsxBytes);
    final format = detectScheduleFileFormat(rows);

    final List<ScheduleImportRow> parsed;
    switch (format) {
      case ScheduleFileFormat.classesAndProfessorList:
        parsed = parseClassesAndProfessorList(rows);
      case ScheduleFileFormat.facultyLoading:
        parsed = parseFacultyLoading(rows);
      case ScheduleFileFormat.roomSchedule:
        parsed = parseRoomSchedule(rows);
      case ScheduleFileFormat.classSchedule:
      case ScheduleFileFormat.unknown:
        throw ScheduleImportException(
          'Unrecognized file — expected a Classes+Professor list, '
          'Confirmation of Faculty Loading, or Room Schedule export.',
        );
    }

    final offerings = _groupIntoOfferings(parsed);
    var offeringsCommitted = 0;
    var meetingsCommitted = 0;
    final errors = <String>[];

    for (final offering in offerings) {
      try {
        final subjectId = await scheduleImportRepository.resolveSubjectId(
          title: offering.subjectTitle,
          code: offering.subjectCode,
        );
        final professorId = await scheduleImportRepository.resolveProfessorId(
          instructorId: offering.instructorId,
          fullName: offering.professorName,
        );

        // The Classes+Professor list carries no section/room/day/time at
        // all (see ScheduleImportRow's own doc comment) — it establishes
        // the subject+professor pairing only ("assign classes to
        // professors"); there is no schedule to commit for it.
        if (offering.sectionName == null) {
          offeringsCommitted++;
          continue;
        }

        final sectionId = await scheduleImportRepository
            .resolveSectionId(offering.sectionName!);
        final classSectionId =
            await registrarRepository.findOrCreateClassSection(
          subjectId: subjectId,
          sectionId: sectionId,
          professorId: professorId,
          schoolYear: schoolYear,
          term: term,
        );

        final resolvedMeetings = <ScheduleImportRow>[];
        for (final meeting in offering.meetings) {
          final room = meeting.room == null
              ? null
              : await scheduleImportRepository
                  .resolveRoomCanonicalName(meeting.room!);
          resolvedMeetings.add(ScheduleImportRow(
            subjectTitle: meeting.subjectTitle,
            component: meeting.component,
            day: meeting.day,
            startTime: meeting.startTime,
            endTime: meeting.endTime,
            room: room,
          ));
        }
        if (resolvedMeetings.isNotEmpty) {
          await scheduleImportRepository.commitMeetings(
            classSectionId: classSectionId,
            meetings: resolvedMeetings,
          );
          meetingsCommitted += resolvedMeetings.length;
        }
        offeringsCommitted++;
      } catch (e) {
        errors.add(
          '${offering.subjectTitle}'
          '${offering.sectionName == null ? '' : ' (${offering.sectionName})'}: $e',
        );
      }
    }

    return ScheduleImportSummary(
      format: format,
      offeringsCommitted: offeringsCommitted,
      meetingsCommitted: meetingsCommitted,
      errors: errors,
    );
  }

  /// Groups a flat parsed-row list into one [_Offering] per distinct
  /// (subject, section, professor) — a CFL/Room Schedule file's Lecture
  /// and Laboratory rows (and any same-component multi-day-range rows)
  /// for the same offering arrive as separate [ScheduleImportRow]s that
  /// all belong under one `class_sections` id.
  List<_Offering> _groupIntoOfferings(List<ScheduleImportRow> rows) {
    final offerings = <String, _Offering>{};
    for (final row in rows) {
      final key = [
        row.subjectTitle.trim().toLowerCase(),
        row.section?.trim().toLowerCase() ?? '',
        row.professorName?.trim().toLowerCase() ??
            row.instructorId?.trim() ??
            '',
      ].join('::');
      final offering = offerings.putIfAbsent(
        key,
        () => _Offering(
          subjectTitle: row.subjectTitle,
          subjectCode: row.subjectCode,
          sectionName: row.section,
          professorName: row.professorName,
          instructorId: row.instructorId,
        ),
      );
      // A roster-only row (no day/time at all) has nothing to add as a
      // meeting — it IS the offering itself.
      if (row.day != null && row.startTime != null && row.endTime != null) {
        offering.meetings.add(row);
      }
    }
    return offerings.values.toList();
  }
}
