import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';

/// One course in a program's curriculum. [yearLevel]/[term] 0 = elective.
class CurriculumEntryModel {
  const CurriculumEntryModel({
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

/// Outcome of one curriculum upload, shown under the Upload button.
class CurriculumUploadResult {
  const CurriculumUploadResult({
    required this.subjects,
    required this.placements,
    required this.programs,
    required this.mergedAutoSubjects,
    required this.errors,
  });

  final int subjects;
  final int placements;
  final List<String> programs;
  final int mergedAutoSubjects;
  final List<String> errors;
}

String _ordinal(int n) => switch (n) {
      1 => '1st',
      2 => '2nd',
      3 => '3rd',
      _ => '${n}th',
    };

String _groupLabel(int year, int term) =>
    year == 0 ? 'Electives' : '${_ordinal(year)} Year · ${_ordinal(term)} Term';

/// The Registrar's Curriculum tab: upload every program's course list once
/// so schedule imports match real subjects instead of auto-generating a
/// course code, and browse what is on file per program / year / term.
class CurriculumView extends StatefulWidget {
  const CurriculumView({
    super.key,
    required this.entries,
    this.onUpload,
  });

  final List<CurriculumEntryModel> entries;

  /// Reads and stores the picked CSV/Excel file; throws on a fatal problem
  /// (unreadable file, missing columns). Null hides the Upload button (demo).
  final Future<CurriculumUploadResult> Function(PlatformFile file)? onUpload;

  @override
  State<CurriculumView> createState() => _CurriculumViewState();
}

class _CurriculumViewState extends State<CurriculumView> {
  bool _uploading = false;
  String? _error;
  CurriculumUploadResult? _result;

  Future<void> _handle(PlatformFile file) async {
    final upload = widget.onUpload;
    if (upload == null || _uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await upload(file);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = RegistrarColors.rowText(context);
    final muted = RegistrarColors.mutedText(context);

    final byProgram = <String, List<CurriculumEntryModel>>{};
    for (final e in widget.entries) {
      (byProgram[e.program] ??= []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: RegistrarColors.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: RegistrarColors.cardBorder(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Curriculum',
                        style: GoogleFonts.poppins(
                            fontSize: 16, fontWeight: FontWeight.w700, color: text)),
                  ),
                  if (widget.onUpload != null)
                    if (_uploading)
                      const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      UploadSpreadsheetButton(
                        label: 'Upload Curriculum',
                        tooltip: 'Upload a curriculum CSV / Excel file',
                        onFileSelected: _handle,
                      ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Upload a CSV or Excel file with the columns Program, Year, '
                'Term, Code, Title, Units and (optional) Prerequisites — one '
                'row per course; use Year 0 / Term 0 (or "Elective") for '
                'electives. Re-uploading updates existing courses. Once a '
                'subject is on file here, schedule imports match it by title '
                'instead of generating a course code.',
                style: GoogleFonts.poppins(fontSize: 12, color: muted),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.red)),
              ],
              if (_result != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Imported ${_result!.subjects} subjects into '
                  '${_result!.placements} placements across '
                  '${_result!.programs.length} program(s)'
                  '${_result!.mergedAutoSubjects > 0 ? ', merged ${_result!.mergedAutoSubjects} auto-generated subject(s) into real ones' : ''}.',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: text),
                ),
                for (final e in _result!.errors.take(10))
                  Text('• $e',
                      style: GoogleFonts.poppins(
                          fontSize: 11.5, color: const Color(0xFFD97706))),
                if (_result!.errors.length > 10)
                  Text('…and ${_result!.errors.length - 10} more skipped rows',
                      style: GoogleFonts.poppins(fontSize: 11.5, color: muted)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (byProgram.isEmpty)
          Text('No curriculum on file yet. Upload one above.',
              style: GoogleFonts.poppins(fontSize: 12.5, color: muted))
        else
          for (final program in byProgram.keys)
            _ProgramTile(program: program, entries: byProgram[program]!),
      ],
    );
  }
}

class _ProgramTile extends StatelessWidget {
  const _ProgramTile({required this.program, required this.entries});

  final String program;
  final List<CurriculumEntryModel> entries;

  @override
  Widget build(BuildContext context) {
    final muted = RegistrarColors.mutedText(context);
    final groups = <String, List<CurriculumEntryModel>>{};
    for (final e in entries) {
      (groups[_groupLabel(e.yearLevel, e.term)] ??= []).add(e);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: RegistrarColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RegistrarColors.cardBorder(context)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(program,
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text('${entries.length} courses',
              style: GoogleFonts.poppins(fontSize: 12, color: muted)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final group in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  '${group.key} · ${group.value.fold<num>(0, (s, e) => s + e.units)} units',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
              for (final e in group.value)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(e.code,
                            style: GoogleFonts.poppins(fontSize: 12, color: muted)),
                      ),
                      Expanded(
                        child: Text(
                          e.prerequisites == null || e.prerequisites!.isEmpty
                              ? e.title
                              : '${e.title}  (prereq: ${e.prerequisites})',
                          style: GoogleFonts.poppins(fontSize: 12.5),
                        ),
                      ),
                      Text('${e.units}',
                          style: GoogleFonts.poppins(fontSize: 12, color: muted)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
