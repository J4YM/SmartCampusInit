import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/student_portal_colors.dart';

/// "Request a Document" form — document type, purpose, optional remarks.
/// Returns the entered values via [onSubmit], or null if the sheet was
/// dismissed without submitting (caller decides what "submit" means —
/// this widget has no Supabase knowledge of its own).
class RequestDocumentDialog extends StatefulWidget {
  const RequestDocumentDialog({super.key, required this.onSubmit});

  final void Function({
    required String documentType,
    required String purpose,
    String? remarks,
  }) onSubmit;

  @override
  State<RequestDocumentDialog> createState() => _RequestDocumentDialogState();
}

class _RequestDocumentDialogState extends State<RequestDocumentDialog> {
  final _documentTypeController =
      TextEditingController(text: 'Good Moral Certificate');
  final _purposeController = TextEditingController();
  final _remarksController = TextEditingController();

  @override
  void dispose() {
    _documentTypeController.dispose();
    _purposeController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_purposeController.text.trim().isEmpty) return;
    widget.onSubmit(
      documentType: _documentTypeController.text.trim(),
      purpose: _purposeController.text.trim(),
      remarks: _remarksController.text.trim().isEmpty
          ? null
          : _remarksController.text.trim(),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Request a Document',
        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _documentTypeController,
            decoration: const InputDecoration(labelText: 'Document Type'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _purposeController,
            decoration: const InputDecoration(labelText: 'Purpose'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remarksController,
            decoration:
                const InputDecoration(labelText: 'Remarks (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: StudentPortalColors.accent(context),
          ),
          child: const Text('Submit Request'),
        ),
      ],
    );
  }
}
