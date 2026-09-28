import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'class_schedule_view.dart' show SectionOption;

/// Registrar's section-override dialog — moves one already-enrolled
/// student to a different section. Exists specifically for a batch
/// enrollment upload that auto-placed a student somewhere that needs
/// correcting (see EnrollmentImportRunner); deliberately does not touch
/// name/RFID/guardian fields, unlike the full Edit Student flow on IT
/// Technician's own Student Records tab.
class ChangeSectionDialog extends StatefulWidget {
  const ChangeSectionDialog({
    super.key,
    required this.studentName,
    required this.currentSectionName,
    required this.sectionOptions,
    required this.onSave,
  });

  final String studentName;
  final String currentSectionName;
  final List<SectionOption> sectionOptions;

  final Future<void> Function(SectionOption section) onSave;

  @override
  State<ChangeSectionDialog> createState() => _ChangeSectionDialogState();
}

class _ChangeSectionDialogState extends State<ChangeSectionDialog> {
  String? _sectionId;
  bool _saving = false;
  String? _error;

  bool get _canSave => _sectionId != null && !_saving;

  Future<void> _handleSave() async {
    final sectionId = _sectionId;
    if (sectionId == null) return;
    final section = widget.sectionOptions.firstWhere((s) => s.id == sectionId);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(section);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: 420,
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
                      'Change Section',
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
                      onTap: _saving ? null : () => Navigator.of(context).pop(),
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
              Text(
                '${widget.studentName} — currently ${widget.currentSectionName}',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: RegistrarColors.mutedText(context),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _sectionId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'New Section',
                  labelStyle: GoogleFonts.poppins(
                    fontSize: 13,
                    color: RegistrarColors.mutedText(context),
                  ),
                  filled: true,
                  fillColor: RegistrarColors.background(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: [
                  for (final section in widget.sectionOptions)
                    DropdownMenuItem(value: section.id, child: Text(section.name)),
                ],
                onChanged:
                    _saving ? null : (value) => setState(() => _sectionId = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: RegistrarColors.dangerRed)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _DialogPillButton(
                    label: 'Cancel',
                    background: RegistrarColors.background(context),
                    foreground: RegistrarColors.rowText(context),
                    onTap: _saving ? null : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  _DialogPillButton(
                    label: 'Save',
                    background: RegistrarColors.azureBlue,
                    foreground: Colors.white,
                    onTap: _canSave ? _handleSave : null,
                    loading: _saving,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
