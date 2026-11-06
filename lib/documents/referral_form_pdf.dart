// lib/documents/referral_form_pdf.dart
import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _kLogoAsset = 'packages/dashboard_layout/assets/images/STI_Baliuag_Logo.png';
const _kInk = PdfColors.black;
const _kText = 8.5;

/// Builds STI's External Referral Form (FT-SDW-164-00) for a self referral:
/// what the student picked and wrote filled into the Guidance and Counseling
/// Office's paper layout, ready to view and print.
///
/// "Reasons for Referral" is always the student's own request, "Interventions
/// Done" is left for the Guidance Associate to write by hand, and "Referred
/// by" names the student.
Future<Uint8List> buildReferralFormPdf(ReferralFormDocument doc) async {
  pw.MemoryImage? logo;
  try {
    final bytes = await rootBundle.load(_kLogoAsset);
    logo = pw.MemoryImage(bytes.buffer.asUint8List());
  } catch (_) {
    // No logo: the title block still identifies the form.
  }

  final f = doc.form;
  final date = _formatDate(doc.referredOn);
  final other = f.referralToOther.trim();

  final pdf = pw.Document(title: 'External Referral Form');
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 32, 40, 32),
      footer: (_) => _footer(),
      build: (context) => [
        _header(logo),
        pw.SizedBox(height: 10),
        _box(pw.Column(children: [
          pw.Row(children: [
            _cell('STI School', doc.school, flex: 3),
            _cell('Date of Referral', date, flex: 2),
          ]),
          pw.Row(children: [
            _cell('School Year', doc.schoolYear, flex: 2),
            _cell('Tertiary (Semester)', '', flex: 2, boxes: const [
              '1st',
              '2nd',
              'Summer',
            ]),
            _cell('Senior High (Quarter)', '', flex: 3, boxes: const [
              '1st',
              '2nd',
              '3rd',
              '4th',
              'Summer',
            ]),
          ]),
        ])),
        pw.SizedBox(height: 6),
        _box(pw.Column(children: [
          pw.Row(children: [
            _cell('Name', _orBlank(f.studentName), flex: 4),
            _cell('Birthdate', _orBlank(f.birthdate), flex: 2),
            _cell('Contact Number', _orBlank(f.contactNumber), flex: 2),
          ]),
          pw.Row(children: [
            _cell('Address', _orBlank(f.address), flex: 4),
            _cell('Grade/Year Level & Section', _orBlank(f.section), flex: 2),
            _cell('Program', _orBlank(f.program), flex: 2),
          ]),
        ])),
        pw.SizedBox(height: 12),
        _referralTo(f, other),
        pw.SizedBox(height: 10),
        _reasons(doc),
        pw.SizedBox(height: 12),
        _specificConcern(f),
        pw.SizedBox(height: 12),
        _label('Significant History'),
        pw.SizedBox(height: 4),
        ..._history(doc.details),
        pw.SizedBox(height: 12),
        _label('Intervention/s Done'),
        pw.SizedBox(height: 4),
        pw.Wrap(spacing: 14, runSpacing: 4, children: [
          for (final i in const [
            'Cognitive Processing',
            'Behavioral Processing',
            'Counseling',
            'Consultation with Teacher/s',
            'Consultation with Parents/Guardian',
          ])
            _check(i, false),
          _check('Others:', false, trailing: _line(150)),
        ]),
        pw.SizedBox(height: 14),
        _label('Referred by'),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(_orBlank(f.studentName), style: _style(bold: true)),
                  pw.Container(
                      height: 0.6, color: _kInk, margin: const pw.EdgeInsets.only(top: 2)),
                  pw.SizedBox(height: 2),
                  pw.Text('Name and Signature of Student (self referral)',
                      style: _style()),
                ],
              ),
            ),
            pw.SizedBox(width: 30),
            pw.Expanded(
              flex: 1,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(date, style: _style(bold: true)),
                  pw.Container(
                      height: 0.6, color: _kInk, margin: const pw.EdgeInsets.only(top: 2)),
                  pw.SizedBox(height: 2),
                  pw.Text('Date', style: _style()),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text('*This form is not valid for medico-legal purposes.',
            style: _style(italic: true)),
      ],
    ),
  );
  return pdf.save();
}

String _orBlank(String v) => v.trim().isEmpty ? '' : v.trim();

pw.TextStyle _style({bool bold = false, bool italic = false, double size = _kText}) =>
    pw.TextStyle(
      fontSize: size,
      color: _kInk,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
    );

pw.Widget _header(pw.MemoryImage? logo) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null) pw.Image(logo, height: 44) else pw.Text('STI', style: _style(bold: true, size: 26)),
        pw.Spacer(),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('STI Guidance and Counseling Office',
                style: _style(bold: true, size: 13)),
            pw.Text('External Referral Form', style: _style(size: 15)),
          ],
        ),
      ],
    );

pw.Widget _box(pw.Widget child) => pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _kInk, width: 0.7)),
      child: child,
    );

/// A labelled cell of the details boxes; [boxes] adds tick boxes after the
/// label (the term / quarter rows, left unticked for the office to fill).
pw.Widget _cell(String label, String value,
    {int flex = 1, List<String> boxes = const []}) {
  return pw.Expanded(
    flex: flex,
    child: pw.Container(
      constraints: const pw.BoxConstraints(minHeight: 30),
      padding: const pw.EdgeInsets.fromLTRB(5, 3, 5, 4),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _kInk, width: 0.4)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$label:', style: _style(size: 7.5)),
          if (value.isNotEmpty) pw.Text(value, style: _style(bold: true, size: 9.5)),
          if (boxes.isNotEmpty)
            pw.Wrap(spacing: 8, children: [for (final b in boxes) _check(b, false)]),
        ],
      ),
    ),
  );
}

pw.Widget _label(String text) => pw.Text(text, style: _style(bold: true, size: 10));

pw.Widget _line(double width) => pw.Container(
    width: width,
    height: 0.6,
    color: _kInk,
    margin: const pw.EdgeInsets.only(top: 9, left: 2));

pw.Widget _tickBox(bool checked) => pw.Container(
      width: 8.5,
      height: 8.5,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _kInk, width: 0.7)),
      child: checked ? pw.Text('X', style: _style(bold: true, size: 7)) : null,
    );

pw.Widget _check(String label, bool checked, {pw.Widget? trailing}) => pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        _tickBox(checked),
        pw.SizedBox(width: 3),
        pw.Text(label, style: _style()),
        if (trailing != null) trailing,
      ],
    );

pw.Widget _referralTo(ReferralFormData f, String other) => pw.Wrap(
      spacing: 16,
      runSpacing: 4,
      crossAxisAlignment: pw.WrapCrossAlignment.center,
      children: [
        pw.Text('Referral to:', style: _style(bold: true)),
        for (final r in ReferralFormOptions.referralTo)
          _check(r, f.referralTo.contains(r)),
        _check(
          'Others:',
          other.isNotEmpty,
          trailing: other.isEmpty
              ? _line(110)
              : pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 3),
                  child: pw.Text(other, style: _style(bold: true)),
                ),
        ),
      ],
    );

/// A self referral is always the student's own request.
pw.Widget _reasons(ReferralFormDocument doc) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _label('Reason/s for Referral:'),
        pw.SizedBox(height: 3),
        _check('Severe Level of Depression, Anxiety, Stress based on MindCheck Assessment', false),
        pw.SizedBox(height: 2),
        _check('High to Very High Need in Social, Personal, Academic, Career and/or Emotional Needs based on Student Needs Assessment Results', false),
        pw.SizedBox(height: 2),
        _check('Observations of Teachers, Guidance Personnel, Students and/or Parents', false),
        pw.SizedBox(height: 2),
        _check(
          'Others:',
          true,
          trailing: pw.Padding(
            padding: const pw.EdgeInsets.only(left: 3),
            child: pw.Text(
              'Self referral by the student - ${doc.concernLabel}'
              '${doc.urgent ? ' (marked urgent)' : ''}',
              style: _style(bold: true),
            ),
          ),
        ),
      ],
    );

pw.Widget _group(String title, List<String> options, List<String> picked,
    String other) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(title, style: _style(bold: true, italic: true, size: 9.5)),
      pw.SizedBox(height: 3),
      for (final o in options)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: _check(o, picked.contains(o)),
        ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: _check(
          'Others:',
          other.isNotEmpty,
          trailing: pw.Padding(
            padding: const pw.EdgeInsets.only(left: 3),
            child: other.isEmpty
                ? _line(90)
                : pw.Text(other, style: _style(bold: true)),
          ),
        ),
      ),
    ],
  );
}

pw.Widget _specificConcern(ReferralFormData f) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _label('Specific Concern'),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _group('Academic', ReferralFormOptions.academic, f.academic,
                      f.otherAcademic),
                  pw.SizedBox(height: 8),
                  _group('Career', ReferralFormOptions.career, f.career,
                      f.otherCareer),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Expanded(
              child: _group('Personal/Social/Emotional',
                  ReferralFormOptions.personal, f.personal, f.otherPersonal),
            ),
          ],
        ),
      ],
    );

/// The student's own words, under the "Significant History" heading. A
/// Paragraph so that a long history flows onto the next page, with a rule
/// beneath it like the paper form's lines.
List<pw.Widget> _history(String details) {
  final text = details.trim();
  return [
    if (text.isNotEmpty) pw.Paragraph(text: text, style: _style(size: 9), margin: pw.EdgeInsets.zero),
    pw.Container(
      width: double.infinity,
      height: text.isEmpty ? 40 : 6,
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _kInk, width: 0.6)),
      ),
    ),
  ];
}

pw.Widget _footer() => pw.Column(
      children: [
        pw.Text(
          'STRICTLY CONFIDENTIAL. Should only be accessed by the Guidance '
          'Counselor/Associate.',
          style: _style(bold: true, size: 7),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2),
        pw.Text('FT-SDW-164-00 | EXTERNAL REFERRAL FORM',
            style: _style(bold: true, size: 7)),
      ],
    );

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];

String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
