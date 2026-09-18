import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';

enum _SchoolStatus { enrolled, transferred, shsGraduate, collegeGraduate }

enum _RequestReason {
  scholarship,
  employment,
  transferringSchool,
  shsGraduate,
  collegeGraduate,
  other,
}

extension on _SchoolStatus {
  String get label => switch (this) {
        _SchoolStatus.enrolled => 'enrolled',
        _SchoolStatus.transferred => 'transferred',
        _SchoolStatus.shsGraduate => 'SHS graduate',
        _SchoolStatus.collegeGraduate => 'College graduate',
      };

  /// Distinct capitalized form for the submitted `remarks` text — the
  /// on-page checkbox label stays lowercase to match the slip exactly.
  String get remarksLabel => switch (this) {
        _SchoolStatus.enrolled => 'Enrolled',
        _SchoolStatus.transferred => 'Transferred',
        _SchoolStatus.shsGraduate => 'SHS Graduate',
        _SchoolStatus.collegeGraduate => 'College Graduate',
      };
}

extension on _RequestReason {
  String get label => switch (this) {
        _RequestReason.scholarship => 'Scholarship',
        _RequestReason.employment => 'Employment',
        _RequestReason.transferringSchool => 'transferring to other School',
        _RequestReason.shsGraduate => 'SHS Graduate',
        _RequestReason.collegeGraduate => 'College Graduate',
        _RequestReason.other => 'other',
      };
}

/// Full-page "Request for Certificate of Good Moral" form — reached from the
/// header's document-request icon in place of the old compact
/// `RequestDocumentDialog`. Deliberately reproduces STI College Baliuag's
/// actual paper CGM request slip as closely as a digital form can — plain
/// labeled blanks and checkbox rows on a single bordered "sheet" rather than
/// this module's usual Bento UI (rounded multi-card layout, colored pill
/// buttons, `SectionHeader`) — only the sheet's own corner radius is kept
/// from that convention, per an explicit design call to make this one page
/// read as a document, not an app card.
///
/// Submits through the same `{documentType, purpose, remarks}` shape the
/// backend (`good_moral_requests` table, via
/// `StudentPortalRepository.submitGoodMoralRequest`) already accepts, so no
/// schema change is needed: `documentType` is fixed to 'Certificate of Good
/// Moral' (this form doesn't ask — that's the one document the whole slip is
/// for), `purpose` carries the selected reason, and every other slip field
/// (name, address, student number, section, contact, AY/term, school status)
/// is packed into a labeled `remarks` block so nothing typed here is lost.
class GoodMoralRequestPage extends StatefulWidget {
  const GoodMoralRequestPage({super.key, required this.onSubmit});

  final void Function({
    required String documentType,
    required String purpose,
    String? remarks,
  }) onSubmit;

  @override
  State<GoodMoralRequestPage> createState() => _GoodMoralRequestPageState();
}

class _GoodMoralRequestPageState extends State<GoodMoralRequestPage> {
  final _formKey = GlobalKey<FormState>();

  final _lastName = TextEditingController();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _address = TextEditingController();
  final _studentNumber = TextEditingController();
  final _section = TextEditingController();
  final _contactNumber = TextEditingController();
  final _ayStarted = TextEditingController();
  final _ayLastAttended = TextEditingController();
  final _otherReason = TextEditingController();

  _SchoolStatus? _schoolStatus;
  _RequestReason? _reason;
  bool _certified = false;

  /// Only after a first submit attempt do unfilled fields/groups show their
  /// errors — matches the rest of the app's forms (e.g. `AddStudentDialog`)
  /// rather than greeting the student with a wall of red on page load.
  bool _submitted = false;

  @override
  void dispose() {
    for (final c in [
      _lastName,
      _firstName,
      _middleName,
      _address,
      _studentNumber,
      _section,
      _contactNumber,
      _ayStarted,
      _ayLastAttended,
      _otherReason,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Required' : null;

  void _submit() {
    setState(() => _submitted = true);
    final fieldsOk = _formKey.currentState?.validate() ?? false;
    final schoolStatusOk = _schoolStatus != null;
    final reasonOk = _reason != null &&
        (_reason != _RequestReason.other ||
            _otherReason.text.trim().isNotEmpty);
    if (!fieldsOk || !schoolStatusOk || !reasonOk || !_certified) return;

    final middle = _middleName.text.trim();
    final fullName = '${_lastName.text.trim()}, ${_firstName.text.trim()}'
        '${middle.isEmpty ? '' : ' $middle'}';
    final purpose = _reason == _RequestReason.other
        ? _otherReason.text.trim()
        : _reason!.label;
    final remarks = [
      'Name: $fullName',
      'Address: ${_address.text.trim()}',
      'Student Number: ${_studentNumber.text.trim()}',
      'Strand/Course/Section: ${_section.text.trim()}',
      'Contact Number: ${_contactNumber.text.trim()}',
      'A.Y./TERM started in STI: ${_ayStarted.text.trim()}',
      'A.Y./TERM last attended in STI: ${_ayLastAttended.text.trim()}',
      'School Status: ${_schoolStatus!.remarksLabel}',
    ].join('\n');

    widget.onSubmit(
      documentType: 'Certificate of Good Moral',
      purpose: purpose,
      remarks: remarks,
    );
    Navigator.of(context).pop();
  }

  /// Underline-only "fill in the blank" field — no fill color, no floating
  /// label inside the box, since the label is its own line above (see
  /// [_field]), matching the slip's own "Label: / blank line" pairing
  /// instead of this module's usual pale-filled rounded field.
  InputDecoration _blankDecoration(BuildContext context) {
    final line = StudentPortalColors.borderStrong(context);
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      errorStyle:
          GoogleFonts.inter(fontSize: 11, color: const Color(0xFFDC2626)),
      border: UnderlineInputBorder(borderSide: BorderSide(color: line)),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: line)),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: StudentPortalColors.accent(context)),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFDC2626)),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFDC2626)),
      ),
    );
  }

  Widget _label(BuildContext context, String text, {bool required = true}) {
    return Text(
      required ? '$text *' : text,
      style: GoogleFonts.poppins(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: StudentPortalColors.textPrimary(context),
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    bool required = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, label, required: required),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: StudentPortalColors.textPrimary(context),
          ),
          decoration: _blankDecoration(context),
          validator: required ? _required : null,
        ),
      ],
    );
  }

  /// Lays [fields] out side-by-side on wide viewports, stacked on mobile —
  /// same breakpoint every other portal layout uses.
  Widget _responsiveRow(BuildContext context, List<Widget> fields) {
    if (context.isMobileWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            fields[i],
            if (i != fields.length - 1)
              const SizedBox(height: StudentPortalSpacing.lg),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          Expanded(child: fields[i]),
          if (i != fields.length - 1)
            const SizedBox(width: StudentPortalSpacing.lg),
        ],
      ],
    );
  }

  Widget _errorText(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        message,
        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFDC2626)),
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: StudentPortalColors.textPrimary(context),
              )),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: StudentPortalColors.textPrimary(context),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String get _todayFormatted {
    final now = DateTime.now();
    return '${_months[now.month - 1]} ${now.day}, ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final today = _todayFormatted;

    return Scaffold(
      backgroundColor: StudentPortalColors.pageBackground(context),
      appBar: AppBar(
        backgroundColor: StudentPortalColors.surface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: StudentPortalColors.textPrimary(context),
        title: Text(
          'Good Moral Certificate Request',
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: DashboardPageWrapper(
          maxWidth: 900,
          padding: EdgeInsets.symmetric(
            horizontal: StudentPortalSpacing.pageHorizontal(context),
            vertical: StudentPortalSpacing.lg,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              autovalidateMode: _submitted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              // The one "sheet" this whole slip lives on — a single bordered,
              // rounded-corner container standing in for the paper form,
              // instead of this module's usual scattered Bento cards.
              child: Container(
                decoration: BoxDecoration(
                  color: StudentPortalColors.surface(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: StudentPortalColors.borderStrong(context)),
                ),
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- Letterhead ------------------------------------
                    Text(
                      'STI COLLEGE BALIUAG',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: StudentPortalColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'REQUEST FOR',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: StudentPortalColors.textSecondary(context),
                      ),
                    ),
                    Text(
                      'CERTIFICATE OF GOOD MORAL',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: StudentPortalColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 2,
                      color: StudentPortalColors.textPrimary(context),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: StudentPortalColors.borderStrong(context)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Filing Number:',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: StudentPortalColors.textSecondary(
                                      context),
                                )),
                            Text('CGM-',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: StudentPortalColors.textMuted(context),
                                )),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: StudentPortalSpacing.xl),

                    // --- Personal information --------------------------
                    Text(
                      'Please complete the following:',
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: StudentPortalColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: StudentPortalSpacing.lg),
                    _responsiveRow(context, [
                      _field(context,
                          controller: _lastName, label: 'Last Name'),
                      _field(context,
                          controller: _firstName, label: 'First Name'),
                      _field(context,
                          controller: _middleName,
                          label: 'Middle Name',
                          required: false),
                    ]),
                    const SizedBox(height: StudentPortalSpacing.lg),
                    _field(context, controller: _address, label: 'Address'),
                    const SizedBox(height: StudentPortalSpacing.lg),
                    _responsiveRow(context, [
                      _field(context,
                          controller: _studentNumber, label: 'Student Number'),
                      _field(context,
                          controller: _section, label: 'Strand/Course/Section'),
                      _field(context,
                          controller: _contactNumber, label: 'Contact Number'),
                    ]),
                    const SizedBox(height: StudentPortalSpacing.lg),
                    _responsiveRow(context, [
                      _field(context,
                          controller: _ayStarted,
                          label: 'A.Y./TERM started in STI'),
                      _field(context,
                          controller: _ayLastAttended,
                          label: 'A.Y./TERM last attended in STI'),
                    ]),
                    const SizedBox(height: StudentPortalSpacing.lg),
                    Text(
                      'School Status',
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: StudentPortalColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // A `Wrap` rather than a fixed 2-column grid — reflows
                    // to a single column on narrow phones instead of
                    // overflowing when "College graduate" doesn't fit a
                    // half-width column.
                    Wrap(
                      spacing: StudentPortalSpacing.xl,
                      runSpacing: 2,
                      children: [
                        for (final status in _SchoolStatus.values)
                          _CheckOption(
                            label: status.label,
                            selected: _schoolStatus == status,
                            onTap: () => setState(() => _schoolStatus = status),
                          ),
                      ],
                    ),
                    if (_submitted && _schoolStatus == null)
                      _errorText(context, 'Please select your school status.'),

                    const SizedBox(height: StudentPortalSpacing.xl),
                    Container(
                      height: 1,
                      color: StudentPortalColors.cardBorder(context),
                    ),
                    const SizedBox(height: StudentPortalSpacing.xl),

                    // --- Reason -----------------------------------------
                    Text(
                      'Reason for requesting Certificate of Good Moral',
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: StudentPortalColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: StudentPortalSpacing.sm),
                    Wrap(
                      spacing: StudentPortalSpacing.lg,
                      runSpacing: StudentPortalSpacing.sm,
                      children: [
                        for (final reason in _RequestReason.values)
                          if (reason != _RequestReason.other)
                            _CheckOption(
                              label: reason.label,
                              selected: _reason == reason,
                              onTap: () => setState(() => _reason = reason),
                            ),
                      ],
                    ),
                    const SizedBox(height: StudentPortalSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _CheckOption(
                          label: 'other',
                          selected: _reason == _RequestReason.other,
                          onTap: () =>
                              setState(() => _reason = _RequestReason.other),
                        ),
                        const SizedBox(width: StudentPortalSpacing.sm),
                        Expanded(
                          child: TextFormField(
                            controller: _otherReason,
                            enabled: _reason == _RequestReason.other,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: StudentPortalColors.textPrimary(context),
                            ),
                            decoration: _blankDecoration(context),
                            validator: (v) => _reason == _RequestReason.other
                                ? _required(v)
                                : null,
                          ),
                        ),
                      ],
                    ),
                    if (_submitted && _reason == null)
                      _errorText(context, 'Please select a reason.'),

                    const SizedBox(height: StudentPortalSpacing.xl),
                    _bullet(context, 'Submit a photocopy of clearance.'),
                    _bullet(
                        context, 'Pay the corresponding fee to the Cashier.'),

                    const SizedBox(height: StudentPortalSpacing.xl),
                    Container(
                      height: 1,
                      color: StudentPortalColors.cardBorder(context),
                    ),
                    const SizedBox(height: StudentPortalSpacing.xl),

                    // --- Certification ------------------------------------
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _certified,
                          onChanged: (v) =>
                              setState(() => _certified = v ?? false),
                          activeColor: StudentPortalColors.textPrimary(context),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'I hereby certify that the above information given '
                              'are true and correct to the best of my knowledge.',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: StudentPortalColors.textPrimary(context),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_submitted && !_certified)
                      _errorText(context,
                          'Please certify the information before submitting.'),
                    const SizedBox(height: StudentPortalSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Invisible placeholder matching the date
                              // column's text above its own rule — without
                              // it this column's rule sits higher than the
                              // date column's (which has that text pushing
                              // its rule down), so the two rules/captions
                              // land at different heights instead of lining
                              // up across the row.
                              Opacity(
                                opacity: 0,
                                child: Text(today,
                                    style: GoogleFonts.inter(fontSize: 13)),
                              ),
                              Container(
                                  height: 1,
                                  color: StudentPortalColors.borderStrong(
                                      context)),
                              const SizedBox(height: 4),
                              Text('Signature of Student',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color:
                                        StudentPortalColors.textMuted(context),
                                  )),
                            ],
                          ),
                        ),
                        const SizedBox(width: StudentPortalSpacing.xxl),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(today,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: StudentPortalColors.textPrimary(
                                        context),
                                  )),
                              Container(
                                  height: 1,
                                  color: StudentPortalColors.borderStrong(
                                      context)),
                              const SizedBox(height: 4),
                              Text('Date of Request',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color:
                                        StudentPortalColors.textMuted(context),
                                  )),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: StudentPortalSpacing.xxl),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(
                                  color: StudentPortalColors.borderStrong(
                                      context)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: StudentPortalColors.textPrimary(context),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: StudentPortalSpacing.md),
                        Expanded(
                          child: FilledButton(
                            onPressed: _submit,
                            style: FilledButton.styleFrom(
                              // App-wide primary CTA blue (same as every
                              // other dashboard's "Save"/"Confirm"/"Submit"
                              // button) instead of the theme-adaptive
                              // ink/paper black this page otherwise uses.
                              backgroundColor: const Color(0xFF345892),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Submit Request',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
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
          ),
        ),
      ),
    );
  }
}

/// Square checkbox + label — the slip's own "☐ enrolled" style option,
/// standing in for this module's usual colored pill `_ChoiceChip`. Behaves
/// as single-select within whichever group it's used in (the caller
/// toggles the shared state field), matching the slip's own checkbox
/// groups even though only one option logically applies at a time.
class _CheckOption extends StatelessWidget {
  const _CheckOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: selected
                      ? StudentPortalColors.textPrimary(context)
                      : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? StudentPortalColors.textPrimary(context)
                        : StudentPortalColors.borderStrong(context),
                    width: 1.4,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: selected
                    ? Icon(Icons.check,
                        size: 12, color: StudentPortalColors.surface(context))
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            // `Flexible` (not a plain `Text`) so a long label like
            // "transferring to other School" wraps onto a second line
            // instead of overflowing when this option sits inside a `Wrap`
            // that's narrower than the label's natural width (e.g. a 320px
            // phone).
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: StudentPortalColors.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
