import 'package:flutter/material.dart';

import 'app_popup.dart';

/// Package-local, presentation-only category list — mirrors the four
/// `technical_issue_category` Postgres enum values (see
/// supabase/add_it_technician_schema.sql) without this package depending on
/// Supabase, same reasoning as `rfid_management_module`'s
/// `RfidReaderRowModel`. Host apps map this to their own db-backed enum.
enum ReportTechnicalIssueCategory {
  offlineDevice,
  offlineKiosk,
  classroomPc,
  other
}

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
  return showAppPopup<void>(
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

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    final c = AppPopupColors(isDarkMode);

    return AppPopup(
      title: 'Report a Technical Issue',
      subtitle: 'Sent straight to IT Technician for follow-up.',
      isDarkMode: isDarkMode,
      closeEnabled: !_submitting,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            AppPopupError(_error!),
            const SizedBox(height: 12),
          ],
          AppPopupFieldLabel('Category', isDarkMode: isDarkMode),
          DropdownButtonFormField<ReportTechnicalIssueCategory>(
            value: _category,
            isExpanded: true,
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                size: 20, color: c.muted),
            style: appPopupFieldStyle(context, isDarkMode: isDarkMode),
            dropdownColor: c.card,
            decoration:
                appPopupInputDecoration(context, isDarkMode: isDarkMode),
            items: ReportTechnicalIssueCategory.values
                .map((cat) => DropdownMenuItem(
                    value: cat, child: Text(cat.label)))
                .toList(),
            onChanged: _submitting
                ? null
                : (value) {
                    if (value != null) setState(() => _category = value);
                  },
          ),
          kAppPopupFieldGap,
          AppPopupTextField(
            label: 'Location (optional)',
            controller: _locationController,
            enabled: !_submitting,
            hint: 'e.g. Room 301, Floor 2 hallway',
            isDarkMode: isDarkMode,
          ),
          kAppPopupFieldGap,
          AppPopupTextField(
            label: 'Describe the problem',
            controller: _descriptionController,
            enabled: !_submitting,
            maxLines: 4,
            isDarkMode: isDarkMode,
          ),
        ],
      ),
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          isDarkMode: isDarkMode,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          label: 'Submit',
          loading: _submitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}
