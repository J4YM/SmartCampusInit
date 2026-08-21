import 'package:docx_creator/docx_creator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// Shared "preview & export" screen for every generated document (Good
/// Moral Certificate, Reports & Exports, ...). [document] is built once
/// (via docx_creator's fluent builder, see [addLetterhead]) and exported to
/// both formats from that single source so the PDF and DOCX never drift
/// apart: PDF for [PdfPreview] — which supplies the in-app preview plus
/// Print and Share/Save-PDF actions for free — and DOCX for the extra
/// "Download DOCX" action added alongside them. Putting both choices on one
/// screen (rather than a blind upfront "pick a format" dialog) lets the
/// admin see the document before deciding how to export it.
class DocumentPreviewPage extends StatelessWidget {
  const DocumentPreviewPage({
    super.key,
    required this.title,
    required this.document,
    required this.fileBaseName,
  });

  /// Shown in the app bar.
  final String title;

  /// The document to render.
  final DocxBuiltDocument document;

  /// Used for both the PDF and DOCX file names (without extension).
  final String fileBaseName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: (format) => PdfExporter().exportToBytes(document),
        pdfFileName: '$fileBaseName.pdf',
        // The document is already built at a fixed size; letting the admin
        // pick a different page format wouldn't reflow docx_creator's
        // pre-laid-out content, only distort it.
        canChangePageFormat: false,
        actions: [
          PdfPreviewAction(
            icon: const Tooltip(
              message: 'Download PDF',
              child: Icon(Icons.picture_as_pdf_outlined),
            ),
            onPressed: (actionContext, build, format) =>
                _downloadPdf(actionContext, build, format),
          ),
          PdfPreviewAction(
            icon: const Tooltip(
              message: 'Download as Word (.docx)',
              child: Icon(Icons.article_outlined),
            ),
            onPressed: (actionContext, _, __) => _downloadDocx(actionContext),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadPdf(
    BuildContext context,
    LayoutCallback build,
    PdfPageFormat format,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await build(format);
      final savedPath = await FilePicker.saveFile(
        fileName: '$fileBaseName.pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
      if (savedPath == null) return; // User cancelled the save dialog.
      messenger.showSnackBar(
        const SnackBar(content: Text('PDF downloaded.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not generate PDF: $e')),
      );
    }
  }

  Future<void> _downloadDocx(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await DocxExporter().exportToBytes(document);
      final savedPath = await FilePicker.saveFile(
        fileName: '$fileBaseName.docx',
        type: FileType.custom,
        allowedExtensions: const ['docx'],
        bytes: bytes,
      );
      if (savedPath == null) return; // User cancelled the save dialog.
      messenger.showSnackBar(
        const SnackBar(content: Text('DOCX downloaded.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not generate DOCX: $e')),
      );
    }
  }
}
