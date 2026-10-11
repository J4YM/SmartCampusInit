import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/referral_request_status.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';

/// "Ask for help" form on the Student Dashboard: a referral to Guidance for
/// the student themselves or for a classmate they are worried about.
///
/// Reports `{concern, details, aboutStudentNumber, urgent}`; a null
/// `aboutStudentNumber` means a self-referral. The page closes itself after a
/// valid submit — the caller does the saving and shows the result.
class ReferralRequestPage extends StatefulWidget {
  const ReferralRequestPage({super.key, required this.onSubmit});

  final void Function({
    required ReferralConcern concern,
    required String details,
    String? aboutStudentNumber,
    required bool urgent,
  }) onSubmit;

  @override
  State<ReferralRequestPage> createState() => _ReferralRequestPageState();
}

class _ReferralRequestPageState extends State<ReferralRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _details = TextEditingController();
  final _studentNumber = TextEditingController();

  bool _forSomeoneElse = false;
  ReferralConcern _concern = ReferralConcern.emotional;
  bool _urgent = false;

  @override
  void dispose() {
    _details.dispose();
    _studentNumber.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
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
    final primary = StudentPortalColors.textPrimary(context);
    final secondary = StudentPortalColors.textSecondary(context);

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
        );

    return Scaffold(
      backgroundColor: StudentPortalColors.pageBackground(context),
      appBar: AppBar(
        title: Text(
          'Request Support',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(StudentPortalSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ask the Guidance Office to reach out - for yourself or '
                    'for a classmate you are worried about. Your name is '
                    'never shared with the classmate.',
                    style: GoogleFonts.inter(fontSize: 13, color: secondary),
                  ),
                  const SizedBox(height: StudentPortalSpacing.lg),
                  label('Who is this for?'),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Myself')),
                      ButtonSegment(value: true, label: Text('Someone else')),
                    ],
                    selected: {_forSomeoneElse},
                    onSelectionChanged: (s) =>
                        setState(() => _forSomeoneElse = s.first),
                  ),
                  if (_forSomeoneElse) ...[
                    const SizedBox(height: StudentPortalSpacing.lg),
                    label('Their student number *'),
                    TextFormField(
                      controller: _studentNumber,
                      decoration: const InputDecoration(
                        hintText: 'e.g. 02000123456',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? "Enter your classmate's student number"
                          : null,
                    ),
                  ],
                  const SizedBox(height: StudentPortalSpacing.lg),
                  label('What is it about? *'),
                  DropdownButtonFormField<ReferralConcern>(
                    initialValue: _concern,
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                    items: [
                      for (final c in ReferralConcern.values)
                        DropdownMenuItem(value: c, child: Text(c.label)),
                    ],
                    onChanged: (c) {
                      if (c != null) setState(() => _concern = c);
                    },
                  ),
                  const SizedBox(height: StudentPortalSpacing.lg),
                  label('Tell us what is going on *'),
                  TextFormField(
                    controller: _details,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: 'Share as much as you are comfortable with.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().length < 10)
                        ? 'Please write at least a sentence'
                        : null,
                  ),
                  const SizedBox(height: StudentPortalSpacing.sm),
                  CheckboxListTile(
                    value: _urgent,
                    onChanged: (v) => setState(() => _urgent = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      'This is urgent - someone may be in danger or need '
                      'help right away',
                      style: GoogleFonts.inter(fontSize: 13, color: primary),
                    ),
                  ),
                  const SizedBox(height: StudentPortalSpacing.lg),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Submit referral'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
