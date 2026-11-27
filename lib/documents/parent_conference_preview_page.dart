// lib/documents/parent_conference_preview_page.dart
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'parent_conference_report_pdf.dart';

/// Opens the Parent Conference Report as a preview the staff member can print
/// or save as a PDF.
Future<void> showParentConferencePreview(
  BuildContext context,
  ParentConferenceData data,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => ParentConferencePreviewPage(data: data)),
  );
}

class ParentConferencePreviewPage extends StatelessWidget {
  const ParentConferencePreviewPage({super.key, required this.data});

  final ParentConferenceData data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parent Conference Report')),
      body: PdfPreview(
        build: (format) => buildParentConferenceReportPdf(data),
        pdfFileName: 'Parent Conference - ${data.studentName}.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}
