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

  String? get _selectedName {
    for (final s in widget.sectionOptions) {
      if (s.id == _sectionId) return s.name;
    }
    return null;
  }

  /// Program comes from the section's own column, else from its name
  /// ("BSIT-3B"); year from `yearLevel`, else from the name.
  late final List<PickerEntry> _entries = [
    for (final s in widget.sectionOptions) _entryFor(s),
  ];

  PickerEntry _entryFor(SectionOption s) {
    final isCurrent = s.name.trim().toLowerCase() ==
        widget.currentSectionName.trim().toLowerCase();
    return PickerEntry.section(
      id: s.id,
      name: s.name,
      program: s.program,
      yearLevel: s.yearLevel,
      badge: isCurrent ? 'Current' : null,
      enabled: !isCurrent,
    );
  }

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
    return AppPopup(
      title: 'Change Section',
      subtitle: '${widget.studentName} — currently ${widget.currentSectionName}',
      width: 520,
      closeEnabled: !_saving,
      // The picker scrolls its own list, so it gets a bounded height instead
      // of a scroll view around it.
      scrollBody: false,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SearchablePickerList(
              searchHint: 'Search sections',
              palette: RegistrarColors.picker(context),
              groupByProgram: true,
              emptyMessage: 'No sections available.',
              entries: _entries,
              selectedId: _sectionId,
              onSelected: (id) {
                if (!_saving) setState(() => _sectionId = id);
              },
            ),
          ),
          if (_selectedName != null) ...[
            const SizedBox(height: 12),
            Text(
              'Move to $_selectedName',
              key: const Key('change-section-target'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppPopupColors.accent,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppPopupError(_error!),
          ],
        ],
      ),
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('change-section-save'),
          label: 'Save',
          loading: _saving,
          onPressed: _canSave ? _handleSave : null,
        ),
      ],
    );
  }
}
