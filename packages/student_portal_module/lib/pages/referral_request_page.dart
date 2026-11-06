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
///
/// [initialForm] carries what the account already knows (name, number,
/// section, contact, program) so the External Referral Form is filled in.
Future<void> showReferralRequestSheet(
  BuildContext context, {
  required bool isDarkMode,
  ReferralFormData initialForm = const ReferralFormData(),
  required void Function({
    required ReferralConcern concern,
    required String details,
    required bool urgent,
    required ReferralFormData form,
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
    desktopMaxWidth: 600,
    builder: (sheetContext) => Theme(
      data: theme,
      child: ReferralRequestSheet(initialForm: initialForm, onSubmit: onSubmit),
    ),
  );
}

/// "Ask for help" form on the Student Dashboard: a self referral to Guidance
/// for mental health concerns or other troubles.
///
/// Below the original questions it carries the fields of STI's External
/// Referral Form (who to refer to, the specific concerns, the student's
/// address / birthdate / program) so the form can be shown and printed once
/// the referral is sent.
///
/// Reports `{concern, details, urgent, form}`. The sheet closes itself after a
/// valid submit — the caller does the saving and shows the result.
class ReferralRequestSheet extends StatefulWidget {
  const ReferralRequestSheet({
    super.key,
    required this.onSubmit,
    this.initialForm = const ReferralFormData(),
  });

  /// The student's name, number, section and contact already known from the
  /// account; address, birthdate and program can be filled in here.
  final ReferralFormData initialForm;

  final void Function({
    required ReferralConcern concern,
    required String details,
    required bool urgent,
    required ReferralFormData form,
  }) onSubmit;

  @override
  State<ReferralRequestSheet> createState() => _ReferralRequestSheetState();
}

class _ReferralRequestSheetState extends State<ReferralRequestSheet> {
  final _details = TextEditingController();
  late final _address = TextEditingController(text: widget.initialForm.address);
  late final _birthdate =
      TextEditingController(text: widget.initialForm.birthdate);
  late final _program = TextEditingController(text: widget.initialForm.program);
  final _referralToOther = TextEditingController();
  final _otherAcademic = TextEditingController();
  final _otherPersonal = TextEditingController();
  final _otherCareer = TextEditingController();

  final Set<String> _referralTo = {'Guidance Counselor'};
  final Set<String> _academic = {};
  final Set<String> _personal = {};
  final Set<String> _career = {};

  ReferralConcern _concern = ReferralConcern.emotional;
  bool _urgent = false;

  /// Shown under a field after a submit attempt, until it is edited.
  String? _detailsError;

  @override
  void dispose() {
    for (final c in [
      _details,
      _address,
      _birthdate,
      _program,
      _referralToOther,
      _otherAcademic,
      _otherPersonal,
      _otherCareer,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_details.text.trim().length < 10) {
      setState(() => _detailsError = 'Please write at least a sentence');
      return;
    }
    // Keep the form's own order, not the order the pills were tapped in.
    List<String> picked(List<String> options, Set<String> chosen) =>
        [for (final o in options) if (chosen.contains(o)) o];
    widget.onSubmit(
      concern: _concern,
      details: _details.text.trim(),
      urgent: _urgent,
      form: widget.initialForm.copyWith(
        address: _address.text.trim(),
        birthdate: _birthdate.text.trim(),
        program: _program.text.trim(),
        referralTo: picked(ReferralFormOptions.referralTo, _referralTo),
        referralToOther: _referralToOther.text.trim(),
        academic: picked(ReferralFormOptions.academic, _academic),
        personal: picked(ReferralFormOptions.personal, _personal),
        career: picked(ReferralFormOptions.career, _career),
        otherAcademic: _otherAcademic.text.trim(),
        otherPersonal: _otherPersonal.text.trim(),
        otherCareer: _otherCareer.text.trim(),
      ),
    );
    Navigator.of(context).pop();
  }

  /// A group of tick-able pills, one per option of the paper form.
  Widget _pills(
    String keyPrefix,
    List<String> options,
    Set<String> chosen,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          AppPopupChoicePill(
            key: Key('$keyPrefix-$option'),
            label: option,
            selected: chosen.contains(option),
            onTap: () => setState(() {
              if (!chosen.remove(option)) chosen.add(option);
            }),
          ),
      ],
    );
  }

  /// What the account already tells the form, read-only.
  Widget _identity(BuildContext context) {
    final f = widget.initialForm;
    final muted = AppPopupColors.of(context).muted;
    final text = AppPopupColors.of(context).text;
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$label  ', style: TextStyle(color: muted)),
              TextSpan(text: value.isEmpty ? '-' : value),
            ]),
            style: TextStyle(fontSize: 12.5, color: text),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line('Name', f.studentName),
        line('Student number', f.studentNumber),
        line('Year level & section', f.section),
        line('Contact number', f.contactNumber),
      ],
    );
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
            subtitle: 'Ask the Guidance Office to reach out about your '
                'well-being or anything troubling you. Only Guidance sees '
                'this.',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 20),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppPopupDropdown<ReferralConcern>(
                    label: 'What is it about?',
                    value: _concern,
                    items: [
                      for (final c in ReferralConcern.selfReferralChoices)
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
                    subtitle: 'You need help right '
                        'away.',
                    value: _urgent,
                    onChanged: (v) => setState(() => _urgent = v),
                  ),
                  const SizedBox(height: 10),
                  const AppPopupSection('Referral Form',
                      icon: Icons.description_outlined),
                  Text(
                    'These fill in the STI Guidance and Counseling Office '
                    'External Referral Form, which you can view and print '
                    'once you send this.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppPopupColors.of(context).muted,
                    ),
                  ),
                  kAppPopupFieldGap,
                  _identity(context),
                  kAppPopupFieldGap,
                  AppPopupTextField(
                    label: 'Address',
                    fieldKey: const Key('referral-address'),
                    controller: _address,
                  ),
                  kAppPopupFieldGap,
                  AppPopupTextField(
                    label: 'Birthdate',
                    fieldKey: const Key('referral-birthdate'),
                    controller: _birthdate,
                    hint: 'MM/DD/YYYY',
                    keyboardType: TextInputType.datetime,
                  ),
                  kAppPopupFieldGap,
                  AppPopupTextField(
                    label: 'Program',
                    fieldKey: const Key('referral-program'),
                    controller: _program,
                  ),
                  kAppPopupFieldGap,
                  const AppPopupFieldLabel('Refer me to'),
                  _pills('referral-to', ReferralFormOptions.referralTo,
                      _referralTo),
                  const SizedBox(height: 10),
                  AppPopupTextField(
                    label: 'Someone else (optional)',
                    fieldKey: const Key('referral-to-other'),
                    controller: _referralToOther,
                  ),
                  const SizedBox(height: 10),
                  const AppPopupSection('Specific Concerns',
                      icon: Icons.checklist_rounded),
                  const AppPopupFieldLabel('Academic'),
                  _pills('concern-academic', ReferralFormOptions.academic,
                      _academic),
                  const SizedBox(height: 10),
                  AppPopupTextField(
                    label: 'Other academic concern (optional)',
                    fieldKey: const Key('referral-other-academic'),
                    controller: _otherAcademic,
                  ),
                  kAppPopupFieldGap,
                  const AppPopupFieldLabel('Personal / Social / Emotional'),
                  _pills('concern-personal', ReferralFormOptions.personal,
                      _personal),
                  const SizedBox(height: 10),
                  AppPopupTextField(
                    label: 'Other personal concern (optional)',
                    fieldKey: const Key('referral-other-personal'),
                    controller: _otherPersonal,
                  ),
                  kAppPopupFieldGap,
                  const AppPopupFieldLabel('Career'),
                  _pills('concern-career', ReferralFormOptions.career,
                      _career),
                  const SizedBox(height: 10),
                  AppPopupTextField(
                    label: 'Other career concern (optional)',
                    fieldKey: const Key('referral-other-career'),
                    controller: _otherCareer,
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
