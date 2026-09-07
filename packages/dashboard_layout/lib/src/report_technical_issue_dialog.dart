import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Package-local, presentation-only category list — mirrors the four
/// `technical_issue_category` Postgres enum values (see
/// supabase/add_it_technician_schema.sql) without this package depending on
/// Supabase, same reasoning as `rfid_management_module`'s
/// `RfidReaderRowModel`. Host apps map this to their own db-backed enum.
enum ReportTechnicalIssueCategory { offlineDevice, offlineKiosk, classroomPc, other }

extension ReportTechnicalIssueCategoryLabel on ReportTechnicalIssueCategory {
  String get label {
    switch (this) {
      case ReportTechnicalIssueCategory.offlineDevice:
        return 'Offline device/reader';
      case ReportTechnicalIssueCategory.offlineKiosk:
        return 'Offline kiosk';
      case ReportTechnicalIssueCategory.classroomPc:
        return 'Classroom PC problem';
      case ReportTechnicalIssueCategory.other:
        return 'Other';
    }
  }
}

/// Shared surface palette for [ReportTechnicalIssueDialog] — same tokens
/// (card/border/text/pale-field-fill/brand-accent) every other custom dialog
/// and popover in this app already uses.
// Dark-mode values below use the app-wide neutral near-black palette
// (0E0E0E background, 191A1F cards, 22242B/2E313A borders, F5F5F5/
// A1A1AA/71717A text) — light mode is untouched.
abstract final class _ReportDialogColors {
  static Color card(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF191A1F) : Colors.white;
  static Color border(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF22242B) : const Color(0x0DE2E8F0);
  static Color primaryText(bool isDarkMode) =>
      isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color secondaryText(bool isDarkMode) =>
      isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
  static Color fieldFill(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);
  static const primaryButton = Color(0xFF345892);
  static const errorText = Color(0xFFDC2626);
}

/// Opens [ReportTechnicalIssueDialog] as a Material dialog. The shared entry
/// point every dashboard calls, so the reporting form is pixel-identical
/// wherever it's opened from.
Future<void> showReportTechnicalIssueDialog(
  BuildContext context, {
  required Future<void> Function({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  }) onSubmit,
  bool isDarkMode = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        ReportTechnicalIssueDialog(onSubmit: onSubmit, isDarkMode: isDarkMode),
  );
}

/// Reports a technical issue (offline device/reader, offline kiosk,
/// classroom PC problem, or other) to IT Technician. Submitted via
/// [onSubmit] — the host app wires this to
/// `TechnicalIssuesRepository.report`. Styled as the same rounded-16 card
/// shell (Poppins title + close-X header, pale borderless rounded-10
/// fields, solid/muted pill actions) used by every other dashboard's own
/// form dialogs (e.g. Admin's Edit Student dialog).
class ReportTechnicalIssueDialog extends StatefulWidget {
  const ReportTechnicalIssueDialog({
    super.key,
    required this.onSubmit,
    this.isDarkMode = false,
  });

  final Future<void> Function({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  }) onSubmit;

  /// Rendered through `showDialog`'s own root-navigator Overlay, which sits
  /// outside the dashboard page's local per-page Theme — so
  /// `context.isDarkMode` here would read the app's ambient theme, not the
  /// page's toggle. Threaded in explicitly instead (same pattern as
  /// `LogoutConfirmationDialog`).
  final bool isDarkMode;

  @override
  State<ReportTechnicalIssueDialog> createState() =>
      _ReportTechnicalIssueDialogState();
}

class _ReportTechnicalIssueDialogState
    extends State<ReportTechnicalIssueDialog> {
  ReportTechnicalIssueCategory _category =
      ReportTechnicalIssueCategory.offlineDevice;
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      setState(() => _error = 'Describe the problem before submitting.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        category: _category,
        description: description,
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // Preserves the entered description/location so nothing typed is
        // lost — the dialog stays open on failure.
        _error = 'Could not submit: $e';
      });
    }
  }

  InputDecoration _fieldDecoration({String? hintText}) {
    final isDarkMode = widget.isDarkMode;
    final borderless = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.poppins(
        fontSize: 13,
        color: _ReportDialogColors.secondaryText(isDarkMode),
      ),
      isDense: true,
      filled: true,
      fillColor: _ReportDialogColors.fieldFill(isDarkMode),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: borderless,
      enabledBorder: borderless,
      disabledBorder: borderless,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
            color: _ReportDialogColors.primaryButton, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    final fieldTextStyle = GoogleFonts.poppins(
      fontSize: 13,
      color: _ReportDialogColors.primaryText(isDarkMode),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 440,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: _ReportDialogColors.card(isDarkMode),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _ReportDialogColors.border(isDarkMode)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Report a Technical Issue',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _ReportDialogColors.primaryText(isDarkMode),
                    ),
                  ),
                ),
                InkWell(
                  onTap: _submitting ? null : () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: _ReportDialogColors.primaryText(isDarkMode),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Sent straight to IT Technician for follow-up.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: _ReportDialogColors.secondaryText(isDarkMode),
              ),
            ),
            const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _ReportDialogColors.errorText,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _ReportFieldLabel(label: 'Category', isDarkMode: isDarkMode),
                    DropdownButtonFormField<ReportTechnicalIssueCategory>(
                      value: _category,
                      isExpanded: true,
                      icon: Icon(Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: _ReportDialogColors.secondaryText(isDarkMode)),
                      style: fieldTextStyle,
                      dropdownColor: _ReportDialogColors.card(isDarkMode),
                      decoration: _fieldDecoration(),
                      items: ReportTechnicalIssueCategory.values
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c.label)))
                          .toList(),
                      onChanged: _submitting
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _category = value);
                              }
                            },
                    ),
                    const SizedBox(height: 14),
                    _ReportFieldLabel(
                        label: 'Location (optional)', isDarkMode: isDarkMode),
                    TextField(
                      controller: _locationController,
                      enabled: !_submitting,
                      style: fieldTextStyle,
                      decoration: _fieldDecoration(
                          hintText: 'e.g. Room 301, Floor 2 hallway'),
                    ),
                    const SizedBox(height: 14),
                    _ReportFieldLabel(
                        label: 'Describe the problem', isDarkMode: isDarkMode),
                    TextField(
                      controller: _descriptionController,
                      enabled: !_submitting,
                      maxLines: 4,
                      style: fieldTextStyle,
                      decoration: _fieldDecoration(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ReportDialogPillButton(
                  label: 'Cancel',
                  background: _ReportDialogColors.fieldFill(isDarkMode),
                  foreground: _ReportDialogColors.primaryText(isDarkMode),
                  onTap: _submitting ? null : () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                _ReportDialogPillButton(
                  label: 'Submit',
                  background: _ReportDialogColors.primaryButton,
                  foreground: Colors.white,
                  onTap: _submitting ? null : _submit,
                  loading: _submitting,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportFieldLabel extends StatelessWidget {
  const _ReportFieldLabel({required this.label, required this.isDarkMode});

  final String label;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _ReportDialogColors.primaryText(isDarkMode),
        ),
      ),
    );
  }
}

/// Solid/pale pill button matching the shared design language's dialog
/// actions used across every dashboard.
class _ReportDialogPillButton extends StatelessWidget {
  const _ReportDialogPillButton({
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
