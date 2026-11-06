// lib/documents/referral_form_preview_page.dart
import 'package:dashboard_layout/dashboard_layout.dart' show ReferralFormDocument;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'referral_form_pdf.dart';

/// Opens the External Referral Form of a self referral as a preview the
/// viewer can print or save as a PDF. Used by the student (after sending a
/// referral, and from their referral list) and by the Guidance Associate.
Future<void> showReferralFormPreview(
  BuildContext context,
  ReferralFormDocument document,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => ReferralFormPreviewPage(document: document)),
  );
}

class ReferralFormPreviewPage extends StatelessWidget {
  const ReferralFormPreviewPage({super.key, required this.document});

  final ReferralFormDocument document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('External Referral Form')),
      body: PdfPreview(
        build: (format) => buildReferralFormPdf(document),
        pdfFileName: 'External Referral Form.pdf',
        // The form is laid out for A4; another page size would only distort it.
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}
