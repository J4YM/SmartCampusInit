import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

import '../models/concern_report_status.dart';
import '../theme/student_portal_spacing.dart';

/// Opens the "Report a Concern" form — a bottom sheet on a phone, a centered
/// dialog on desktop (see [showResponsiveSheet]), built from the shared popup
/// kit like every other form in the system.
///
/// Takes [isDarkMode] explicitly rather than reading it from [context]: the
/// caller is the Student Portal's `State`, whose own `context` sits above the
/// local Theme (see `showDayDetailSheet`).
Future<void> showConcernReportSheet(
  BuildContext context, {
  required bool isDarkMode,
  required void Function({
    required ConcernType concern,
    required String details,
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
      child: ConcernReportSheet(onSubmit: onSubmit),
    ),
  );
}

/// "Report a Concern" form on the Student Dashboard: a concern report to
/// Student Affairs (attendance, behavior, bullying, safety and the like).
///
/// Reports `{concern, details, urgent}`. The sheet closes itself after a
/// valid submit — the caller does the saving and shows the result.
class ConcernReportSheet extends StatefulWidget {
  const ConcernReportSheet({super.key, required this.onSubmit});

  final void Function({
    required ConcernType concern,
    required String details,
    required bool urgent,
  }) onSubmit;

  @override
  State<ConcernReportSheet> createState() => _ConcernReportSheetState();
}

class _ConcernReportSheetState extends State<ConcernReportSheet> {
  final _details = TextEditingController();

  ConcernType _concern = ConcernType.attendance;
  bool _urgent = false;

  /// Shown under a field after a submit attempt, until it is edited.
  String? _detailsError;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  void _submit() {
    if (_details.text.trim().length < 10) {
      setState(() => _detailsError = 'Please write at least a sentence');
      return;
    }
    widget.onSubmit(
      concern: _concern,
      details: _details.text.trim(),
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
            title: 'Report a Concern',
            subtitle: 'Tell Student Affairs about something that needs '
                'attention at school, such as bullying, safety or '
                'attendance problems.',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 20),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppPopupDropdown<ConcernType>(
                    label: 'What is it about?',
                    value: _concern,
                    items: [
                      for (final c in ConcernType.values)
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
                    subtitle: 'Someone may be in danger or it needs '
                        'action right away.',
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
                key: const Key('concern-submit'),
                label: 'Submit concern',
                onPressed: _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
