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

/// Opens [ReportTechnicalIssueDialog] as a Material dialog. The shared entry
/// point Teacher's and Admin's dashboards both call, so the reporting form
/// is pixel-identical wherever it's opened from.
Future<void> showReportTechnicalIssueDialog(
  BuildContext context, {
  required Future<void> Function({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  }) onSubmit,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ReportTechnicalIssueDialog(onSubmit: onSubmit),
  );
}

/// Reports a technical issue (offline device/reader, offline kiosk,
/// classroom PC problem, or other) to IT Technician. Submitted via
/// [onSubmit] — the host app wires this to
/// `TechnicalIssuesRepository.report`.
class ReportTechnicalIssueDialog extends StatefulWidget {
  const ReportTechnicalIssueDialog({super.key, required this.onSubmit});

  final Future<void> Function({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  }) onSubmit;

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
    return AlertDialog(
      title: Text(
        'Report a Technical Issue',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<ReportTechnicalIssueCategory>(
              value: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: ReportTechnicalIssueCategory.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                hintText: 'e.g. Room 301, Floor 2 hallway',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Describe the problem',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}
