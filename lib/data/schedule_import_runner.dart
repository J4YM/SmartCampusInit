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

/// Included in [ScheduleImportException]'s message when no sheet's format
/// can be recognized — this is the only evidence available for diagnosing
/// a real upload's actual content without direct access to the file (the
/// person reporting the bug can only paste back what's on screen, not the
/// raw .xlsx bytes). One block per sheet, each with its row/column count
/// and first few non-empty cells, so a wrong-sheet, differently-worded-
/// title, or value-extraction problem is visible directly in the error
/// instead of requiring another guess.
String _diagnosticPreview(List<({String name, List<List<String?>> rows})> sheets) {
  if (sheets.isEmpty) return 'Found 0 worksheets in this file.';

  final buffer = StringBuffer('Found ${sheets.length} worksheet(s):');
  for (final sheet in sheets) {
    final rows = sheet.rows;
    final columnCount =
        rows.isEmpty ? 0 : rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    buffer.write('\n\n"${sheet.name}" — ${rows.length} row(s), $columnCount column(s) wide.');
    if (rows.isEmpty) continue;
    var shown = 0;
    for (var r = 0; r < rows.length && shown < 10; r++) {
      for (var c = 0; c < rows[r].length && shown < 10; c++) {
        final value = rows[r][c];
        if (value == null || value.trim().isEmpty) continue;
        buffer.write('\n  row ${r + 1}, col ${c + 1}: "$value"');
        shown++;
      }
    }
    if (shown == 0) buffer.write('\n  (every cell read as blank)');
  }
  return buffer.toString();
}

/// Included in [ScheduleImportException]'s message when a format was
/// detected but its parser still found nothing to extract — a full,
/// row-by-row dump (every cell, not just non-empty ones, so a blank
/// spacer row or an off-by-one is visible) of the first [maxRows], since
/// the structural shape right around the header row is exactly what a
/// row-by-row parser like parseFacultyLoading/parseRoomSchedule depends on.
String _fullRowDump(List<List<String?>> rows, {int maxRows = 20}) {
  if (rows.isEmpty) return '(0 rows)';
  final buffer = StringBuffer();
  for (var r = 0; r < rows.length && r < maxRows; r++) {
    final cells = [
      for (final value in rows[r]) if (value != null && value.trim().isNotEmpty) value else '·',
    ];
    buffer.write('row ${r + 1}: ${cells.join(' | ')}\n');
  }
  if (rows.length > maxRows) {
    buffer.write('... (${rows.length - maxRows} more row(s) not shown)');
  }
  return buffer.toString().trimRight();
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
    final sheets = readAllSheets(xlsxBytes);

    // Checks every tab for a recognized format, and — critically —
    // processes EVERY tab that matches, not just the first: a real CFL
    // "master" workbook has one tab per professor (confirmed against a
    // real upload — one tab was Ronald Christian Pallorina teaching
    // Human Computer Interaction/Advanced Database System/etc., a
    // completely different tab was a GE instructor teaching
    // "Understanding the Self"). Stopping at the first match here would
    // silently drop every other professor's/room's tab. Sheets are
    // matched against whichever format the FIRST matching sheet was —
    // a single workbook mixing CFL and Room Schedule tabs isn't a shape
    // this plan expects, so later sheets only join in if they agree.
    ScheduleFileFormat? format;
    final matchedSheets = <List<List<String?>>>[];
    for (final sheet in sheets) {
      final sheetFormat = detectScheduleFileFormat(sheet.rows);
      if (sheetFormat == ScheduleFileFormat.unknown ||
          sheetFormat == ScheduleFileFormat.classSchedule) {
        continue;
      }
      format ??= sheetFormat;
      if (sheetFormat == format) matchedSheets.add(sheet.rows);
    }

    if (format == null || matchedSheets.isEmpty) {
      throw ScheduleImportException(
        'Unrecognized file — expected a Classes+Professor list, '
        'Confirmation of Faculty Loading, or Room Schedule export.\n\n'
        '${_diagnosticPreview(sheets)}',
      );
    }

    final parsed = <ScheduleImportRow>[];
    for (final rows in matchedSheets) {
      switch (format) {
        case ScheduleFileFormat.classesAndProfessorList:
          parsed.addAll(parseClassesAndProfessorList(rows));
        case ScheduleFileFormat.facultyLoading:
          parsed.addAll(parseFacultyLoading(rows));
        case ScheduleFileFormat.roomSchedule:
          parsed.addAll(parseRoomSchedule(rows));
        case ScheduleFileFormat.classSchedule:
        case ScheduleFileFormat.unknown:
          throw StateError('unreachable — filtered out above');
      }
    }

    if (parsed.isEmpty) {
      // Format detection succeeded (it only needs one matching phrase
      // anywhere in the sheet) but the row-by-row parser — which expects
      // a specific table shape below that phrase — found nothing to
      // extract from ANY matched sheet. Different failure mode than
      // "unrecognized file" above, and needs different evidence to
      // diagnose: a full dump of each matched sheet's own rows (not just
      // non-empty cells), since the most likely causes are structural
      // (e.g. a blank spacer row the parser mistakes for "end of sheet",
      // or a header cell that doesn't exactly match what it's looking for).
      final dump = matchedSheets.map(_fullRowDump).join('\n\n---\n\n');
      throw ScheduleImportException(
        'Detected this as a $format file, but found 0 rows to import '
        'from it.\n\n$dump',
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

        // Confirmed real case: a Room Schedule file mixed in Senior High
        // sections ("ABM 12A") alongside college ones — entirely out of
        // scope for this system. Skipped silently (not counted, not an
        // error) rather than let it hit `sections_year_level_check` as a
        // raw PostgrestException that reads as a bug to the Registrar/
        // Scheduling Officer.
        if (isSeniorHighSection(offering.sectionName!)) {
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
          // Checked AFTER room canonicalization, not on the raw room
          // text: confirmed real duplicate where the same meeting was
          // listed with two different room spellings for the same
          // physical room ("ComLab 2" vs "COMPUTER LABORATORY 2") — a
          // pre-canonicalization check would have missed it since the
          // raw text still differs even once room_aliases resolves both
          // to the same canonical name.
          final isDuplicate = resolvedMeetings.any((m) =>
              m.component == meeting.component &&
              m.day == meeting.day &&
              m.startTime == meeting.startTime &&
              m.endTime == meeting.endTime &&
              m.room == room);
          if (isDuplicate) continue;
          resolvedMeetings.add(ScheduleImportRow(
            subjectTitle: meeting.subjectTitle,
            component: meeting.component,
            day: meeting.day,
            startTime: meeting.startTime,
            endTime: meeting.endTime,
            room: room,
            units: meeting.units,
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
      // A placeholder professor's canonical form ("New IT Faculty 1" and
      // plain "IT Faculty 1" both -> "it faculty 1") is used here, not
      // the raw name — confirmed real data spells the same open position
      // both ways across different tabs/files, and without this they'd
      // group into two different offerings, each becoming its own
      // class_sections row for what's really one open teaching slot.
      final professorKey = row.professorName == null
          ? (row.instructorId?.trim() ?? '')
          : (canonicalPlaceholderName(row.professorName!) ??
              row.professorName!.trim().toLowerCase());
      final key = [
        row.subjectTitle.trim().toLowerCase(),
        row.section?.trim().toLowerCase() ?? '',
        professorKey,
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
