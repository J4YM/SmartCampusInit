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
    required this.program,
    required this.yearLevel,
    required this.term,
    required this.code,
    required this.title,
    required this.units,
    this.prerequisites,
  });

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

  /// Every stored curriculum placement, ordered program / year / term / code.
  Future<List<CurriculumEntryView>> fetchCurriculum() async {
    final rows = await _client
        .from('curriculum_entries')
        .select('program, year_level, term, prerequisites, subjects ( code, title, units )')
        .order('program')
        .order('year_level')
        .order('term');
    final list = (rows as List<dynamic>).map((raw) {
      final r = raw as Map<String, dynamic>;
      final s = r['subjects'] as Map<String, dynamic>?;
      return CurriculumEntryView(
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
