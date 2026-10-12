import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

import '../models/referral_request_status.dart';
import '../theme/student_portal_spacing.dart';

/// Opens the "Request Support" form — a bottom sheet on a phone, a centered
/// dialog on desktop (see [showResponsiveSheet]), built from the shared popup
/// kit like every other form in the system.
///
/// Takes [isDarkMode] explicitly rather than reading it from [context]: the
/// caller is the Student Portal's `State`, whose own `context` sits above the
/// local Theme (see `showDayDetailSheet`).
Future<void> showReferralRequestSheet(
  BuildContext context, {
  required bool isDarkMode,
  required void Function({
    required ReferralConcern concern,
    required String details,
    String? aboutStudentNumber,
    required bool urgent,
  }) onSubmit,
}) {
  final theme = ThemeData(
    useMaterial3: true,
    brightness: isDarkMode ? Brightness.dark : Brightness.light,
  ).withPoppins();
  return showResponsiveSheet<void>(
    context: context,
    backgroundColor: isDarkMode ? const Color(0xFF191A1F) : Colors.white,
    handleColor:
        isDarkMode ? const Color(0xFF22242B) : const Color(0xFFF1F5F9),
    desktopMaxWidth: 520,
    builder: (sheetContext) => Theme(
      data: theme,
      child: ReferralRequestSheet(onSubmit: onSubmit),
    ),
  );
}

/// "Ask for help" form on the Student Dashboard: a referral to Guidance for
/// the student themselves or for a classmate they are worried about.
///
/// Reports `{concern, details, aboutStudentNumber, urgent}`; a null
/// `aboutStudentNumber` means a self-referral. The sheet closes itself after a
/// valid submit — the caller does the saving and shows the result.
class ReferralRequestSheet extends StatefulWidget {
  const ReferralRequestSheet({super.key, required this.onSubmit});

  final void Function({
    required ReferralConcern concern,
    required String details,
    String? aboutStudentNumber,
    required bool urgent,
  }) onSubmit;

  @override
  State<ReferralRequestSheet> createState() => _ReferralRequestSheetState();
}

class _ReferralRequestSheetState extends State<ReferralRequestSheet> {
  final _details = TextEditingController();
  final _studentNumber = TextEditingController();

  bool _forSomeoneElse = false;
  ReferralConcern _concern = ReferralConcern.emotional;
  bool _urgent = false;

  /// Shown under a field after a submit attempt, until it is edited.
  String? _studentNumberError;
  String? _detailsError;

  @override
  void dispose() {
    _details.dispose();
    _studentNumber.dispose();
    super.dispose();
  }

  void _submit() {
    final numberMissing =
        _forSomeoneElse && _studentNumber.text.trim().isEmpty;
    final detailsTooShort = _details.text.trim().length < 10;
    if (numberMissing || detailsTooShort) {
      setState(() {
        _studentNumberError =
            numberMissing ? "Enter your classmate's student number" : null;
        _detailsError =
            detailsTooShort ? 'Please write at least a sentence' : null;
      });
      return;
    }
    widget.onSubmit(
      concern: _concern,
      details: _details.text.trim(),
      aboutStudentNumber: _forSomeoneElse ? _studentNumber.text.trim() : null,
      urgent: _urgent,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        StudentPortalSpacing.xxl,
        StudentPortalSpacing.xl,
        StudentPortalSpacing.xxl,
        MediaQuery.of(context).viewInsets.bottom + StudentPortalSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPopupHeader(
            title: 'Request Support',
            subtitle: 'Ask the Guidance Office to reach out - for yourself or '
                'for a classmate you are worried about. Your name is never '
                'shared with the classmate.',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 20),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppPopupDropdown<bool>(
                    label: 'Who is this for?',
                    value: _forSomeoneElse,
                    items: const [
                      DropdownMenuItem(value: false, child: Text('Myself')),
                      DropdownMenuItem(
                          value: true, child: Text('Someone else')),
                    ],
                    onChanged: (v) => setState(() {
                      _forSomeoneElse = v ?? false;
                      _studentNumberError = null;
                    }),
                  ),
                  if (_forSomeoneElse) ...[
                    kAppPopupFieldGap,
                    AppPopupTextField(
                      label: 'Their student number',
                      controller: _studentNumber,
                      hint: 'e.g. 02000123456',
                      keyboardType: TextInputType.text,
                      errorText: _studentNumberError,
                      onChanged: (_) {
                        if (_studentNumberError != null) {
                          setState(() => _studentNumberError = null);
                        }
                      },
                    ),
                  ],
                  kAppPopupFieldGap,
                  AppPopupDropdown<ReferralConcern>(
                    label: 'What is it about?',
                    value: _concern,
                    items: [
                      for (final c in ReferralConcern.values)
                        DropdownMenuItem(value: c, child: Text(c.label)),
                    ],
                    onChanged: (c) {
                      if (c != null) setState(() => _concern = c);
                    },
                  ),
                  kAppPopupFieldGap,
                  AppPopupTextField(
                    label: 'Tell us what is going on',
                    controller: _details,
                    hint: 'Share as much as you are comfortable with.',
                    minLines: 4,
                    maxLines: 8,
                    errorText: _detailsError,
                    onChanged: (_) {
                      if (_detailsError != null) {
                        setState(() => _detailsError = null);
                      }
                    },
                  ),
                  kAppPopupFieldGap,
                  AppPopupCheckboxTile(
                    title: 'This is urgent',
                    subtitle: 'Someone may be in danger or need help right '
                        'away.',
                    value: _urgent,
                    onChanged: (v) => setState(() => _urgent = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Secondary action left of the primary, right-aligned — the same
          // footer every popup in the system uses.
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              AppPopupSecondaryButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
              ),
              AppPopupPrimaryButton(
                key: const Key('referral-submit'),
                label: 'Submit referral',
                onPressed: _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
