import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: 420,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x0D000000)),
            // Same soft-shadow recipe every dashboard's BentoCard surfaces
            // use — this package stays dependency-free of dashboard_layout
            // (it's also built standalone for the kiosk app), so the recipe
            // is replicated by hand instead of imported.
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Confirm Violations',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Is the following information correct?',
                style: GoogleFonts.inter(fontSize: 13),
              ),
              const SizedBox(height: 12),
              for (final label in widget.violationLabels)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('•  $label', style: GoogleFonts.inter(fontSize: 13)),
                ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Could not submit: ${_errorMessage!}',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.red),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Material(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: _submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: const Color(0xFF345892),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: _submitting ? null : _handleConfirm,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                'Confirm',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
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
