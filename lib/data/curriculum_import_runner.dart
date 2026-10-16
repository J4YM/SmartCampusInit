import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'curriculum_import/curriculum_file_parser.dart';
import 'schedule_import/xlsx_reader.dart';

class CurriculumImportException implements Exception {
  CurriculumImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Result of one [CurriculumImportRunner.run].
class CurriculumImportSummary {
  const CurriculumImportSummary({
    required this.subjects,
    required this.placements,
    required this.programs,
    required this.mergedAutoSubjects,
    required this.errors,
  });

  /// Distinct subject codes written to `subjects`.
  final int subjects;

  /// Program/year/term placements written to `curriculum_entries`.
  final int placements;
  final List<String> programs;

  /// Earlier auto-generated `AUTO-…` subjects folded into a real one.
  final int mergedAutoSubjects;

  /// Rows skipped for bad data (see [ParsedCurriculum.errors]).
  final List<String> errors;
}

/// One course in the on-screen curriculum list.
class CurriculumEntryView {
  const CurriculumEntryView({
    this.id,
    this.subjectId,
    required this.program,
    required this.yearLevel,
    required this.term,
    required this.code,
    required this.title,
    required this.units,
    this.prerequisites,
  });

  /// `curriculum_entries.id` / `subjects.id` — what Edit and Delete act on.
  final String? id;
  final String? subjectId;
  final String program;
  final int yearLevel;
  final int term;
  final String code;
  final String title;
  final num units;
  final String? prerequisites;
}

/// Registrar curriculum upload: reads a CSV or .xlsx of every course per
/// program (see [parseCurriculumRows] for the columns), writes them into
/// `subjects` + `curriculum_entries`, so schedule imports find an existing
/// subject instead of auto-creating one.
class CurriculumImportRunner {
  CurriculumImportRunner(this._client);

  final SupabaseClient _client;

  static const _chunk = 100;

  Future<CurriculumImportSummary> run({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final List<List<String?>> rows;
    try {
      rows = fileName.toLowerCase().endsWith('.csv')
          ? parseCsvText(utf8.decode(bytes, allowMalformed: true))
          : readFirstSheetRows(bytes);
    } catch (e) {
      throw CurriculumImportException('Could not read "$fileName": $e');
    }

    final parsed = parseCurriculumRows(rows);
    if (parsed == null || parsed.rows.isEmpty) {
      throw CurriculumImportException(
        'No curriculum rows found — expected a header row with the columns '
        'Program, Year, Term, Code, Title, Units (Prerequisites optional), '
        'followed by one row per course.',
      );
    }

    // "BSIT" -> "BS Information Technology" etc., so uploads spelled either
    // way land under the name sections/imports already use.
    final aliasRows =
        await _client.from('program_aliases').select('alias, canonical_program');
    final aliases = {
      for (final r in aliasRows as List<dynamic>)
        ((r as Map<String, dynamic>)['alias'] as String).trim().toUpperCase():
            r['canonical_program'] as String,
    };
    String canonical(String program) =>
        aliases[program.trim().toUpperCase()] ?? program.trim();

    // One subjects row per code (first spelling wins within the file).
    final byCode = <String, CurriculumRow>{};
    for (final r in parsed.rows) {
      byCode.putIfAbsent(r.code, () => r);
    }
    final codes = byCode.keys.toList();

    for (var i = 0; i < codes.length; i += _chunk) {
      final slice = codes.skip(i).take(_chunk);
      await _client.from('subjects').upsert([
        for (final c in slice)
          {'code': c, 'title': byCode[c]!.title, 'units': byCode[c]!.units},
      ], onConflict: 'code');
    }

    final idByCode = <String, String>{};
    for (var i = 0; i < codes.length; i += _chunk) {
      final slice = codes.skip(i).take(_chunk).toList();
      final found =
          await _client.from('subjects').select('id, code').inFilter('code', slice);
      for (final r in found as List<dynamic>) {
        final m = r as Map<String, dynamic>;
        idByCode[m['code'] as String] = m['id'] as String;
      }
    }

    final placements = <Map<String, dynamic>>[];
    final seen = <String>{};
    final programs = <String>{};
    for (final r in parsed.rows) {
      final id = idByCode[r.code];
      if (id == null) continue;
      final program = canonical(r.program);
      if (!seen.add('$program|$id')) continue; // duplicate within the file
      programs.add(program);
      placements.add({
        'program': program,
        'year_level': r.yearLevel,
        'term': r.term,
        'subject_id': id,
        'prerequisites': r.prerequisites,
      });
    }
    for (var i = 0; i < placements.length; i += _chunk) {
      await _client
          .from('curriculum_entries')
          .upsert(placements.skip(i).take(_chunk).toList(),
              onConflict: 'program,subject_id');
    }

    var merged = 0;
    try {
      final result = await _client.rpc('merge_auto_subjects');
      merged = (result as num?)?.toInt() ?? 0;
    } catch (_) {
      // Best effort — the upload itself already succeeded.
    }

    return CurriculumImportSummary(
      subjects: codes.length,
      placements: placements.length,
      programs: programs.toList()..sort(),
      mergedAutoSubjects: merged,
      errors: parsed.errors,
    );
  }

  /// Adds a course to a program ([entryId] null) or edits an existing one.
  ///
  /// A course is a shared `subjects` row (code, title, units — one per code,
  /// used by every program and by class schedules) plus a per-program
  /// `curriculum_entries` placement (program, year, term, prerequisites).
  /// Editing therefore changes the subject for every program that lists it;
  /// adding a code that already exists reuses that subject and overwrites its
  /// title/units, the same as re-uploading a file does.
  ///
  /// Throws [CurriculumImportException] with a readable message for the two
  /// conflicts a person can cause: a code another subject already uses, and a
  /// program that already lists the course.
  Future<void> saveCourse({
    String? entryId,
    String? subjectId,
    required String program,
    required int yearLevel,
    required int term,
    required String code,
    required String title,
    required num units,
    String? prerequisites,
  }) async {
    final cleanCode = code.toUpperCase().replaceAll(' ', '');
    final cleanProgram = program.trim();
    final prereq = (prerequisites == null || prerequisites.trim().isEmpty)
        ? null
        : prerequisites.trim();
    try {
      if (entryId == null) {
        final subject = await _client
            .from('subjects')
            .upsert({'code': cleanCode, 'title': title.trim(), 'units': units},
                onConflict: 'code')
            .select('id')
            .single();
        final id = subject['id'] as String;
        final existing = await _client
            .from('curriculum_entries')
            .select('id')
            .eq('program', cleanProgram)
            .eq('subject_id', id)
            .maybeSingle();
        if (existing != null) {
          throw CurriculumImportException(
              '$cleanProgram already has $cleanCode in its curriculum.');
        }
        await _client.from('curriculum_entries').insert({
          'program': cleanProgram,
          'year_level': yearLevel,
          'term': term,
          'subject_id': id,
          'prerequisites': prereq,
        });
      } else {
        if (subjectId == null) {
          throw CurriculumImportException('This course cannot be edited.');
        }
        // .select() so a write that row-level security silently turned into
        // "0 rows" is reported rather than looking like success.
        final subjectRows = await _client
            .from('subjects')
            .update({'code': cleanCode, 'title': title.trim(), 'units': units})
            .eq('id', subjectId)
            .select('id');
        final entryRows = await _client
            .from('curriculum_entries')
            .update({
              'program': cleanProgram,
              'year_level': yearLevel,
              'term': term,
              'prerequisites': prereq,
            })
            .eq('id', entryId)
            .select('id');
        if ((subjectRows as List).isEmpty || (entryRows as List).isEmpty) {
          throw CurriculumImportException(
              'Could not save the change — it was not permitted, or the course '
              'was already removed.');
        }
      }
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw CurriculumImportException(entryId == null
            ? '$cleanProgram already has $cleanCode in its curriculum.'
            : 'Another course already uses the code $cleanCode, or '
                '$cleanProgram already lists this course.');
      }
      throw CurriculumImportException(e.message);
    }
  }

  /// Removes a course from one program's curriculum. The `subjects` row stays:
  /// class schedules and other programs may still use it.
  Future<void> deleteEntry(String entryId) async {
    try {
      final removed = await _client
          .from('curriculum_entries')
          .delete()
          .eq('id', entryId)
          .select('id');
      if ((removed as List).isEmpty) {
        throw CurriculumImportException(
            'Could not remove the course — it was not permitted, or it was '
            'already removed.');
      }
    } on PostgrestException catch (e) {
      throw CurriculumImportException(e.message);
    }
  }

  /// Every stored curriculum placement, ordered program / year / term / code.
  Future<List<CurriculumEntryView>> fetchCurriculum() async {
    final rows = await _client
        .from('curriculum_entries')
        .select('id, subject_id, program, year_level, term, prerequisites, subjects ( code, title, units )')
        .order('program')
        .order('year_level')
        .order('term');
    final list = (rows as List<dynamic>).map((raw) {
      final r = raw as Map<String, dynamic>;
      final s = r['subjects'] as Map<String, dynamic>?;
      return CurriculumEntryView(
        id: r['id'] as String?,
        subjectId: r['subject_id'] as String?,
        program: r['program'] as String,
        yearLevel: (r['year_level'] as num).toInt(),
        term: (r['term'] as num).toInt(),
        code: s?['code'] as String? ?? '',
        title: s?['title'] as String? ?? '',
        units: (s?['units'] as num?) ?? 0,
        prerequisites: r['prerequisites'] as String?,
      );
    }).toList()
      ..sort((a, b) {
        final byProgram = a.program.compareTo(b.program);
        if (byProgram != 0) return byProgram;
        final byYear = a.yearLevel.compareTo(b.yearLevel);
        if (byYear != 0) return byYear;
        final byTerm = a.term.compareTo(b.term);
        return byTerm != 0 ? byTerm : a.code.compareTo(b.code);
      });
    return list;
  }
}
