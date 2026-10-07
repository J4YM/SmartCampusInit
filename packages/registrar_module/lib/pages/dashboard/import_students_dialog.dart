import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';


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
    final done = _result != null;
    return AppPopup(
      title: 'Import Students',
      closeEnabled: !_importing,
      body: done ? _buildResult(context, _result!) : _buildForm(context),
      actions: done
          ? [
              AppPopupPrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]
          : [
              AppPopupSecondaryButton(
                label: 'Cancel',
                onPressed: _importing ? null : () => Navigator.of(context).pop(),
              ),
              AppPopupPrimaryButton(
                label: 'Import',
                loading: _importing,
                onPressed: _canImport ? _handleImport : null,
              ),
            ],
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
            color: AppPopupColors.of(context).muted,
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
                      ? AppPopupColors.of(context).muted
                      : AppPopupColors.of(context).text,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            UploadSpreadsheetButton(
              accentColor: AppPopupColors.accent,
              label: 'Choose File',
              onFileSelected: _importing
                  ? null
                  : (file) => setState(() => _file = file),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          AppPopupError(_error!),
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
            color: AppPopupColors.of(context).text,
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
                  color: AppPopupColors.of(context).muted,
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
              color: AppPopupColors.of(context).text,
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
                  color: AppPopupColors.of(context).muted,
                ),
              ),
            ),
        ],
      ],
    );
  }
}
