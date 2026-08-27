import 'package:flutter/material.dart';

/// Shown before an admission slip is written to the database — lists the
/// violations the reporter selected and asks them to confirm the
/// information is correct. [onConfirm] is only called once, on a
/// successful tap of "Confirm", and performs the actual database write;
/// this dialog pops `true` once it resolves. A throwing [onConfirm] keeps
/// the dialog open with an inline error so the reporter can retry or
/// cancel; "Cancel"/dismissing pops without ever having called [onConfirm].
class AdmissionSlipConfirmDialog extends StatefulWidget {
  const AdmissionSlipConfirmDialog({
    super.key,
    required this.violationLabels,
    required this.onConfirm,
  });

  final List<String> violationLabels;
  final Future<void> Function() onConfirm;

  @override
  State<AdmissionSlipConfirmDialog> createState() =>
      _AdmissionSlipConfirmDialogState();
}

class _AdmissionSlipConfirmDialogState
    extends State<AdmissionSlipConfirmDialog> {
  bool _submitting = false;
  String? _errorMessage;

  Future<void> _handleConfirm() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await widget.onConfirm();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Violations'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Is the following information correct?'),
          const SizedBox(height: 12),
          for (final label in widget.violationLabels)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('•  $label'),
            ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              'Could not submit: ${_errorMessage!}',
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _handleConfirm,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm'),
        ),
      ],
    );
  }
}
