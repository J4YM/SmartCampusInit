import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

/// An administrator lifts a "Not for readmission" / "Dismissed" restriction
/// after an appeal or a mistaken sanction. A written reason is required; it is
/// recorded in the audit log. Pops with the reason.
class LiftRestrictionDialog extends StatefulWidget {
  const LiftRestrictionDialog({super.key, required this.studentName});

  final String studentName;

  @override
  State<LiftRestrictionDialog> createState() => _LiftRestrictionDialogState();
}

class _LiftRestrictionDialogState extends State<LiftRestrictionDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: 'Lift Restriction',
      subtitle: '${widget.studentName} will be able to be enrolled again.',
      width: 480,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('lift-confirm'),
          label: 'Lift restriction',
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_reason.text.trim()),
        ),
      ],
      body: AppPopupTextField(
        label: 'Reason (recorded in the audit log)',
        fieldKey: const Key('lift-reason'),
        controller: _reason,
        minLines: 3,
        maxLines: 5,
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}
