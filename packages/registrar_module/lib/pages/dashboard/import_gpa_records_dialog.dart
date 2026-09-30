import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';

/// Result of one GPA batch upload — mirrors GradeImportSummary
/// (lib/data/grade_import_runner.dart) without this presentation-only
/// widget depending on the data layer directly, matching
/// ImportStudentsResult's own convention.
class ImportGpaRecordsResult {
  const ImportGpaRecordsResult({
    required this.schoolYear,
    required this.term,
    required this.imported,
    required this.skipped,
    required this.errors,
  });

  final String schoolYear;
  final String term;
  final int imported;

  /// Rows whose student number has no matching student on file yet — not
  /// errors, see GradeImportRepository.upsertGpaRecord's own doc comment.
  final int skipped;
  final List<String> errors;
}

/// Shows the result of a GPA-records upload picked via the Grades tab's
/// own upload button (see GradesView) — that button already handles file
/// selection through [UploadSpreadsheetButton], so this dialog only ever
/// shows the in-progress/result state, not a separate file-picking step.
/// [onImport] runs automatically once, as soon as the dialog opens.
class ImportGpaRecordsResultDialog extends StatefulWidget {
  const ImportGpaRecordsResultDialog({super.key, required this.onImport});

  final Future<ImportGpaRecordsResult> Function() onImport;

  @override
  State<ImportGpaRecordsResultDialog> createState() =>
      _ImportGpaRecordsResultDialogState();
}

class _ImportGpaRecordsResultDialogState
    extends State<ImportGpaRecordsResultDialog> {
  bool _importing = true;
  String? _error;
  ImportGpaRecordsResult? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      final result = await widget.onImport();
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: 460,
        child: BentoCard(
          backgroundColor: RegistrarColors.card(context),
          borderColor: RegistrarColors.cardBorder(context),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Upload GPA Records',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: RegistrarColors.rowText(context),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(child: _buildBody(context)),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _DialogPillButton(
                    label: 'Done',
                    background: RegistrarColors.azureBlue,
                    foreground: Colors.white,
                    onTap: _importing
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_importing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Uploading GPA records...',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: RegistrarColors.rowText(context),
              ),
            ),
          ],
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Text(error, style: const TextStyle(color: RegistrarColors.dangerRed));
    }

    final result = _result;
    if (result == null) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${result.schoolYear} / ${result.term}',
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: RegistrarColors.mutedText(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${result.imported} GPA record(s) saved'
          '${result.skipped == 0 ? '.' : ', ${result.skipped} skipped:'}',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: RegistrarColors.rowText(context),
          ),
        ),
        if (result.skipped > 0) ...[
          const SizedBox(height: 6),
          Text(
            'These students aren\'t on file yet (their batch enrollment may '
            'not be uploaded) — nothing was overwritten for them.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: RegistrarColors.mutedText(context),
            ),
          ),
        ],
        if (result.errors.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '${result.errors.length} row(s) failed:',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: RegistrarColors.rowText(context),
            ),
          ),
          const SizedBox(height: 6),
          for (final error in result.errors)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                error,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: RegistrarColors.mutedText(context),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _DialogPillButton extends StatelessWidget {
  const _DialogPillButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: disabled ? background.withOpacity(0.5) : background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: disabled ? foreground.withOpacity(0.6) : foreground,
            ),
          ),
        ),
      ),
    );
  }
}
