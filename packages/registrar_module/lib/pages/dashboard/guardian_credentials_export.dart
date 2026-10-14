import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'import_students_dialog.dart' show ImportGuardianCredential;

String _csvEscape(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// One row per guardian: what the registrar hands over. The temporary
/// password is the only secret in it — and only valid until the guardian's
/// first sign-in, when they must replace it.
String buildGuardianCredentialsCsv(List<ImportGuardianCredential> credentials) {
  final buffer = StringBuffer()
    ..writeln(
      ['Guardian', 'Email (username)', 'Temporary password', 'Children']
          .map(_csvEscape)
          .join(','),
    );
  for (final c in credentials) {
    buffer.writeln(
      [
        c.guardianName ?? '',
        c.email,
        c.temporaryPassword,
        c.students.join('; '),
      ].map(_csvEscape).join(','),
    );
  }
  return buffer.toString();
}

/// Printable hand-out sheet: one bordered slip per guardian (cut along the
/// borders), so each guardian only ever receives their own login.
Future<Uint8List> buildGuardianCredentialsPdf(
  List<ImportGuardianCredential> credentials,
) async {
  final doc = pw.Document();
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11);
  const body = pw.TextStyle(fontSize: 10);
  const small = pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700);

  pw.Widget slip(ImportGuardianCredential c) => pw.Container(
        width: 250,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.8, color: PdfColors.grey600),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('STI College Baliuag', style: small),
            pw.Text('Parent Portal Login', style: bold),
            pw.SizedBox(height: 8),
            pw.Text(c.guardianName ?? 'Guardian', style: body),
            pw.SizedBox(height: 6),
            pw.Text('Username (email)', style: small),
            pw.Text(c.email, style: bold),
            pw.SizedBox(height: 6),
            pw.Text('Temporary password', style: small),
            pw.Text(
              c.temporaryPassword,
              style: pw.TextStyle(
                font: pw.Font.courierBold(),
                fontSize: 14,
              ),
            ),
            if (c.students.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text('Children', style: small),
              for (final s in c.students) pw.Text(s, style: body),
            ],
            pw.SizedBox(height: 8),
            pw.Text(
              'You will be asked to choose your own password the first '
              'time you sign in. Keep this slip private.',
              style: small,
            ),
          ],
        ),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Text(
          'Parent Portal Logins — ${credentials.length} guardian(s)',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
        ),
      ),
      build: (_) => [
        pw.Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [for (final c in credentials) slip(c)],
        ),
      ],
    ),
  );
  return doc.save();
}

/// Lists freshly issued parent logins with every way to keep them: copy,
/// CSV, print and PDF. [onExported] fires when any of them succeeds, so a
/// host dialog can stop warning that the passwords are about to be lost.
class GuardianCredentialsPanel extends StatelessWidget {
  const GuardianCredentialsPanel({
    super.key,
    required this.credentials,
    this.onExported,
    this.fileBaseName = 'Parent_Portal_Logins',
  });

  final List<ImportGuardianCredential> credentials;
  final VoidCallback? onExported;
  final String fileBaseName;

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _plainText() {
    final lines = <String>['Parent portal logins (temporary passwords)'];
    for (final c in credentials) {
      lines
        ..add('')
        ..add('${c.guardianName ?? 'Guardian'} — ${c.email}')
        ..add('  Temporary password: ${c.temporaryPassword}');
      if (c.students.isNotEmpty) {
        lines.add('  Children: ${c.students.join('; ')}');
      }
    }
    return lines.join('\n');
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _plainText()));
    onExported?.call();
    if (context.mounted) _toast(context, 'Parent logins copied.');
  }

  Future<void> _saveCsv(BuildContext context) async {
    try {
      final saved = await FilePicker.saveFile(
        fileName: '$fileBaseName.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: Uint8List.fromList(
          utf8.encode(buildGuardianCredentialsCsv(credentials)),
        ),
      );
      if (saved == null) return; // cancelled
      onExported?.call();
      if (context.mounted) _toast(context, 'CSV saved.');
    } catch (e) {
      if (context.mounted) _toast(context, 'Could not save the CSV: $e');
    }
  }

  Future<void> _savePdf(BuildContext context) async {
    try {
      final bytes = await buildGuardianCredentialsPdf(credentials);
      final saved = await FilePicker.saveFile(
        fileName: '$fileBaseName.pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
      if (saved == null) return;
      onExported?.call();
      if (context.mounted) _toast(context, 'PDF saved.');
    } catch (e) {
      if (context.mounted) _toast(context, 'Could not save the PDF: $e');
    }
  }

  Future<void> _print(BuildContext context) async {
    try {
      final printed = await Printing.layoutPdf(
        name: fileBaseName,
        onLayout: (_) => buildGuardianCredentialsPdf(credentials),
      );
      if (printed) onExported?.call();
    } catch (e) {
      if (context.mounted) _toast(context, 'Could not print: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPopupColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.muted.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${credentials.length} parent login(s)',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sign-in is the guardian\'s email plus the temporary password '
            'below; they choose a new password on first sign-in. Only a '
            'hash is stored, so these cannot be shown again — print or '
            'save them now. (A lost one can be reissued from the student\'s '
            'profile.)',
            style: GoogleFonts.poppins(fontSize: 11.5, color: colors.muted),
          ),
          const SizedBox(height: 8),
          for (final c in credentials)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SelectableText.rich(
                TextSpan(
                  style: GoogleFonts.poppins(fontSize: 12, color: colors.text),
                  children: [
                    TextSpan(
                      text: '${c.guardianName ?? 'Guardian'} · ${c.email}\n',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const TextSpan(text: 'Temporary password: '),
                    TextSpan(
                      text: c.temporaryPassword,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (c.students.isNotEmpty)
                      TextSpan(
                        text: '\nChildren: ${c.students.join('; ')}',
                        style: TextStyle(color: colors.muted),
                      ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                key: const Key('credentials-print'),
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('Print'),
                onPressed: () => _print(context),
              ),
              TextButton.icon(
                key: const Key('credentials-pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text('Save PDF'),
                onPressed: () => _savePdf(context),
              ),
              TextButton.icon(
                key: const Key('credentials-csv'),
                icon: const Icon(Icons.table_chart_outlined, size: 16),
                label: const Text('Download CSV'),
                onPressed: () => _saveCsv(context),
              ),
              TextButton.icon(
                key: const Key('credentials-copy'),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
                onPressed: () => _copy(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Blocks a host dialog's close until the registrar confirms they've kept the
/// logins (or knowingly discards them). Returns true to go ahead and close.
Future<bool> confirmDiscardCredentials(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Close without saving the logins?'),
      content: const Text(
        'The temporary passwords are only shown now and cannot be displayed '
        'again. You have not printed, saved or copied them. A lost one can '
        'still be reissued from the student\'s profile, which replaces the '
        'old password.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Go back'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Close anyway'),
        ),
      ],
    ),
  );
  return ok == true;
}
