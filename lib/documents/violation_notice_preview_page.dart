// lib/documents/violation_notice_preview_page.dart
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'violation_notice_pdf.dart';

/// Opens the Parent Acknowledgment notice as a preview the officer can print
/// or save as a PDF, then have the parent sign.
Future<void> showViolationNoticePreview(
  BuildContext context,
  ViolationNoticeData data,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => ViolationNoticePreviewPage(data: data)),
  );
}

class ViolationNoticePreviewPage extends StatelessWidget {
  const ViolationNoticePreviewPage({super.key, required this.data});

  final ViolationNoticeData data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parent Acknowledgment Notice')),
      body: PdfPreview(
        build: (format) => buildViolationNoticePdf(data),
        pdfFileName: 'Violation Notice - ${data.studentName}.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}
