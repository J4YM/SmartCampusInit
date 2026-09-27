import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Compact "Upload" trigger shared by every module that needs a file
/// picker for a spreadsheet import (Registrar's Class Schedule/Grades
/// cards, the Scheduling Officer's CFL/Room Schedule uploads, …) — icon on
/// the left, short label on the right; a hover/long-press tooltip still
/// spells out the full "Upload Spreadsheet" action. Tapping it always opens
/// the OS file explorer via `file_picker`.
///
/// Originally lived in registrar_module, hard-coded to that module's own
/// colors; moved here and parameterized ([accentColor]/[backgroundColor])
/// once the Scheduling Officer dashboard needed the same button with its
/// own palette.
class UploadSpreadsheetButton extends StatelessWidget {
  const UploadSpreadsheetButton({
    super.key,
    this.onFileSelected,
    this.accentColor = const Color(0xFF2563EB),
    this.backgroundColor,
    this.label = 'Upload',
    this.tooltip = 'Upload Spreadsheet',
  });

  /// Called with the file the user picked. Falls back to a confirmation
  /// snackbar when omitted (demo behavior — no import pipeline wired up
  /// yet). Not called at all when the picker is dismissed without a pick.
  final ValueChanged<PlatformFile>? onFileSelected;

  /// Icon/label color — each module passes its own accent (e.g.
  /// `RegistrarColors.azureBlue`). Defaults to a generic blue for callers
  /// that don't need a specific brand color.
  final Color accentColor;

  /// Button fill color. Defaults to transparent (the caller's own
  /// background shows through) when omitted.
  final Color? backgroundColor;

  final String label;
  final String tooltip;

  Future<void> _pickFile(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
      // Desktop file_picker leaves PlatformFile.bytes null unless asked
      // for explicitly, but this repo also builds for web (where there is
      // no filesystem path to read from at all) — withData: true is the
      // one option that returns usable bytes on every platform this app
      // targets, matching id_card_template_editor_page.dart's own
      // _pickAndUploadImage.
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null) return;
    if (onFileSelected != null) {
      onFileSelected!(picked);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected "${picked.name}".')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor ?? Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _pickFile(context),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.upload_rounded, size: 16, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
