import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'guardian_credentials_export.dart';
import 'import_students_dialog.dart' show ImportGuardianCredential;

/// Registrar's "Parent Portal Login" for one student: issues the linked
/// guardian a NEW temporary password (replacing whatever they had) and shows
/// it once with print / PDF / CSV / copy — the recovery path when the
/// credentials from enrollment were not noted down. Passwords are stored as
/// hashes only, so an old one can never be looked up, only replaced.
class ParentLoginDialog extends StatefulWidget {
  const ParentLoginDialog({
    super.key,
    required this.studentName,
    required this.onIssue,
  });

  final String studentName;

  /// Resets and returns the linked guardian logins. Throws with a readable
  /// message when the student has no guardian email on file.
  final Future<List<ImportGuardianCredential>> Function() onIssue;

  @override
  State<ParentLoginDialog> createState() => _ParentLoginDialogState();
}

class _ParentLoginDialogState extends State<ParentLoginDialog> {
  bool _working = false;
  String? _error;
  List<ImportGuardianCredential>? _issued;
  bool _kept = false;

  Future<void> _issue() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final issued = await widget.onIssue();
      if (mounted) setState(() => _issued = issued);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _close() async {
    if (_issued != null && !_kept) {
      if (!await confirmDiscardCredentials(context)) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPopupColors.of(context);
    final issued = _issued;
    return AppPopup(
      title: 'Parent Portal Login',
      closeEnabled: !_working,
      onClose: _close,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (issued == null) ...[
            Text(
              'Issue a new temporary password for ${widget.studentName}\'s '
              'guardian(s). Their current password stops working, and they '
              'will be asked to choose a new one on next sign-in.',
              style: GoogleFonts.poppins(fontSize: 12.5, color: colors.muted),
            ),
          ] else
            GuardianCredentialsPanel(
              credentials: issued,
              fileBaseName: 'Parent_Portal_Login',
              onExported: () => setState(() => _kept = true),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppPopupError(_error!),
          ],
        ],
      ),
      actions: issued == null
          ? [
              AppPopupSecondaryButton(
                label: 'Cancel',
                onPressed: _working ? null : () => Navigator.of(context).pop(),
              ),
              AppPopupPrimaryButton(
                label: 'Issue New Password',
                loading: _working,
                onPressed: _working ? null : _issue,
              ),
            ]
          : [
              AppPopupPrimaryButton(label: 'Done', onPressed: _close),
            ],
    );
  }
}
