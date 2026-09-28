import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';

/// Result of one [ImportStudentsDialog] upload — mirrors
/// EnrollmentImportSummary (lib/data/enrollment_import_runner.dart)
/// without this presentation-only widget depending on the data layer
/// directly, matching SectionSchedulePdfRow's own convention.
class ImportStudentsResult {
  const ImportStudentsResult({
    required this.created,
    required this.updated,
    required this.errors,
    required this.capWarnings,
  });

  final int created;
  final int updated;
  final List<String> errors;
  final List<String> capWarnings;
}

/// Registrar's "Import Students" dialog — upload the school's own
/// "Student Information" export and each student is enrolled
/// automatically into a section matching their own row's Program/Level,
/// spread across whichever of that program/level's sections currently has
/// the fewest students. See EnrollmentImportRunner's own doc comment for
/// the full placement rule — there is deliberately no section picker
/// here; the file's own data drives placement, not a single upfront
/// choice.
class ImportStudentsDialog extends StatefulWidget {
  const ImportStudentsDialog({super.key, required this.onImport});

  final Future<ImportStudentsResult> Function({required PlatformFile file})
      onImport;

  @override
  State<ImportStudentsDialog> createState() => _ImportStudentsDialogState();
}

class _ImportStudentsDialogState extends State<ImportStudentsDialog> {
  PlatformFile? _file;
  bool _importing = false;
  String? _error;
  ImportStudentsResult? _result;

  bool get _canImport => _file != null && !_importing;

  Future<void> _handleImport() async {
    final file = _file;
    if (file == null) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final result = await widget.onImport(file: file);
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Import Students',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: RegistrarColors.rowText(context),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Close',
                    child: InkWell(
                      onTap: _importing ? null : () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 22,
                          color: RegistrarColors.rowText(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: _result != null
                      ? _buildResult(context, _result!)
                      : _buildForm(context),
                ),
              ),
              const SizedBox(height: 20),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Each student is enrolled automatically based on their own '
          'Program/Level columns — spread across that program/level\'s '
          'existing sections, least-full first.',
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            color: RegistrarColors.mutedText(context),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                _file?.name ?? 'No file selected',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: _file == null
                      ? RegistrarColors.mutedText(context)
                      : RegistrarColors.rowText(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            UploadSpreadsheetButton(
              accentColor: RegistrarColors.azureBlue,
              label: 'Choose File',
              onFileSelected: _importing
                  ? null
                  : (file) => setState(() => _file = file),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: RegistrarColors.dangerRed)),
        ],
      ],
    );
  }

  Widget _buildResult(BuildContext context, ImportStudentsResult result) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${result.created} student(s) created, ${result.updated} updated'
          '${result.errors.isEmpty ? '.' : ', ${result.errors.length} skipped:'}',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: RegistrarColors.rowText(context),
          ),
        ),
        if (result.errors.isNotEmpty) ...[
          const SizedBox(height: 10),
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
        if (result.capWarnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '${result.capWarnings.length} enrolled past the target section size:',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: RegistrarColors.rowText(context),
            ),
          ),
          const SizedBox(height: 6),
          for (final warning in result.capWarnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                warning,
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

  Widget _buildActions(BuildContext context) {
    if (_result != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _DialogPillButton(
            label: 'Done',
            background: RegistrarColors.azureBlue,
            foreground: Colors.white,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _DialogPillButton(
          label: 'Cancel',
          background: RegistrarColors.background(context),
          foreground: RegistrarColors.rowText(context),
          onTap: _importing ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 10),
        _DialogPillButton(
          label: 'Import',
          background: RegistrarColors.azureBlue,
          foreground: Colors.white,
          onTap: _canImport ? _handleImport : null,
          loading: _importing,
        ),
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
    this.loading = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: disabled && !loading ? background.withOpacity(0.5) : background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                )
              : Text(
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
