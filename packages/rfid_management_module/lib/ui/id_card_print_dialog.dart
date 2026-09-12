// packages/rfid_management_module/lib/ui/id_card_print_dialog.dart
import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../id_card_template.dart';
import '../rfid_student_row.dart';
import 'it_technician_dashboard_page.dart' show ItTechnicianColors;
import 'signature_capture_dialog.dart';
import 'webcam_capture_dialog.dart';

/// Review-and-print screen for a student ID card — picks a saved
/// template, shows whatever photo is currently on file (if any), lets
/// the IT Technician (re)capture one via the webcam, captures a
/// signature when the chosen template's back layout calls for one, and
/// prints once everything required is in hand. Uploading the
/// photo/signature and actually sending the card to the printer both
/// happen in [onPrint], which the host app supplies (this package has no
/// Supabase/printer access of its own).
class IdCardPrintDialog extends StatefulWidget {
  const IdCardPrintDialog({
    super.key,
    required this.student,
    required this.initialPhotoBytes,
    required this.templates,
    required this.onLoadTemplate,
    required this.onPrint,
  });

  final RfidStudentRow student;

  /// The student's existing photo, downloaded by the host app before
  /// opening this dialog — null when they don't have one on file yet.
  final Uint8List? initialPhotoBytes;

  /// Saved templates, most-recently-updated first (see
  /// IdCardTemplatesRepository.fetchTemplates) — the picker defaults to
  /// the first entry.
  final List<IdCardTemplateSummary> templates;

  /// Fetches a template's full front/back layout when the picker
  /// selection changes — this dialog has no Supabase access of its own.
  final Future<IdCardTemplateDetail> Function(String templateId) onLoadTemplate;

  /// Uploads whatever changed (photo, and signature if captured) and
  /// sends the card to the printer. Rethrows on failure so this dialog
  /// can show the error inline.
  final Future<void> Function({
    required Uint8List photoBytes,
    required Uint8List? signatureBytes,
    required IdCardTemplateDetail template,
  }) onPrint;

  @override
  State<IdCardPrintDialog> createState() => _IdCardPrintDialogState();
}

class _IdCardPrintDialogState extends State<IdCardPrintDialog> {
  late Uint8List? _photoBytes = widget.initialPhotoBytes;
  Uint8List? _signatureBytes;
  IdCardTemplateDetail? _selectedTemplate;
  String? _selectedTemplateId;
  bool _loadingTemplate = false;
  bool _printing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.templates.isNotEmpty) {
      _selectedTemplateId = widget.templates.first.id;
      _loadTemplate(widget.templates.first.id);
    }
  }

  Future<void> _loadTemplate(String id) async {
    setState(() => _loadingTemplate = true);
    try {
      final detail = await widget.onLoadTemplate(id);
      if (mounted) {
        setState(() {
          _selectedTemplate = detail;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedTemplate = null;
          _error = 'Could not load template: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _loadingTemplate = false);
    }
  }

  bool get _needsSignature {
    final template = _selectedTemplate;
    if (template == null) return false;
    return [...template.frontLayout, ...template.backLayout]
        .any((e) => e.type == IdCardElementType.signature);
  }

  Future<void> _capturePhoto() async {
    final bytes = await showDialog<Uint8List>(
      context: context,
      builder: (_) => const WebcamCaptureDialog(),
    );
    if (bytes != null && mounted) setState(() => _photoBytes = bytes);
  }

  Future<void> _captureSignature() async {
    final bytes = await showDialog<Uint8List>(
      context: context,
      builder: (_) => const SignatureCaptureDialog(),
    );
    if (bytes != null && mounted) setState(() => _signatureBytes = bytes);
  }

  Future<void> _handlePrint() async {
    final photoBytes = _photoBytes;
    final template = _selectedTemplate;
    if (photoBytes == null || template == null) return;
    if (_needsSignature && _signatureBytes == null) {
      setState(() => _error = 'Capture a signature before printing.');
      return;
    }
    setState(() {
      _printing = true;
      _error = null;
    });
    try {
      await widget.onPrint(
        photoBytes: photoBytes,
        signatureBytes: _signatureBytes,
        template: template,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  bool get _canPrint =>
      !_printing &&
      !_loadingTemplate &&
      _photoBytes != null &&
      _selectedTemplate != null &&
      (!_needsSignature || _signatureBytes != null);

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Print Student ID',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: ItTechnicianColors.rowText(context),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.templates.isEmpty)
                Text(
                  'No templates available — create one in the ID Templates tab first.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: ItTechnicianColors.dangerRed,
                  ),
                )
              else
                DropdownButton<String>(
                  value: _selectedTemplateId,
                  isExpanded: true,
                  items: [
                    for (final t in widget.templates)
                      DropdownMenuItem(value: t.id, child: Text(t.name)),
                  ],
                  onChanged: (id) {
                    if (id == null) return;
                    setState(() {
                      _selectedTemplateId = id;
                      _signatureBytes = null;
                    });
                    _loadTemplate(id);
                  },
                ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: _photoBytes == null
                          ? Container(
                              color: ItTechnicianColors.background(context),
                              child: Icon(
                                Icons.person_outline,
                                size: 42,
                                color: ItTechnicianColors.mutedText(context),
                              ),
                            )
                          : Image.memory(_photoBytes!, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.fullName,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: ItTechnicianColors.rowText(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          student.studentNumber,
                          style: GoogleFonts.poppins(
                            fontSize: context.isMobileWidth ? 10 : 12,
                            color: ItTechnicianColors.mutedText(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _printing ? null : _capturePhoto,
                          icon: const Icon(Icons.camera_alt_outlined, size: 16),
                          label: Text(_photoBytes == null ? 'Capture Photo' : 'Retake'),
                        ),
                        if (_needsSignature) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _printing ? null : _captureSignature,
                            icon: const Icon(Icons.draw_outlined, size: 16),
                            label: Text(_signatureBytes == null
                                ? 'Capture Signature'
                                : 'Retake Signature'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (_selectedTemplate != null && _photoBytes != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: PdfPreview(
                    key: ValueKey(
                      '${_selectedTemplateId}_${_photoBytes.hashCode}_${_signatureBytes.hashCode}',
                    ),
                    build: (format) => _buildPreviewBytes(),
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    allowPrinting: false,
                    allowSharing: false,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: ItTechnicianColors.dangerRed)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _printing ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _canPrint ? _handlePrint : null,
                      icon: _printing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Print'),
                      style: FilledButton.styleFrom(backgroundColor: ItTechnicianColors.azureBlue),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _buildPreviewBytes() async {
    final template = _selectedTemplate;
    final photoBytes = _photoBytes;
    if (template == null || photoBytes == null) {
      throw StateError('Preview requested before a template/photo were ready.');
    }
    return _buildPreviewPdf(
      frontLayout: template.frontLayout,
      backLayout: template.backLayout,
      photoBytes: photoBytes,
      signatureBytes: _signatureBytes,
      student: widget.student,
    );
  }
}

String _previewValueFor(IdDataFieldKey key, RfidStudentRow student) {
  switch (key) {
    case IdDataFieldKey.firstName:
      return student.firstName;
    case IdDataFieldKey.middleInitial:
      return student.middleInitial;
    case IdDataFieldKey.lastName:
      return student.lastName;
    case IdDataFieldKey.studentNumber:
      return student.studentNumber;
    case IdDataFieldKey.course:
      return student.course;
    case IdDataFieldKey.section:
      return student.section;
    case IdDataFieldKey.yearLevel:
      return student.yearLevel;
    case IdDataFieldKey.guardianName:
      return student.guardianName;
    case IdDataFieldKey.guardianContactNo:
      return student.guardianContactNo;
  }
}

/// Treats a zero-alpha color the same as null — "no fill/stroke" — since
/// the pdf package's BoxDecoration/PdfGraphics never consult alpha
/// themselves; any non-null PdfColor paints fully opaque regardless of
/// its alpha byte.
PdfColor? _pdfColorOrNull(int? value) {
  if (value == null || (value >> 24) & 0xFF == 0) return null;
  return PdfColor.fromInt(value);
}

pw.TextAlign _pdfTextAlign(String? value) {
  switch (value) {
    case 'center':
      return pw.TextAlign.center;
    case 'right':
      return pw.TextAlign.right;
    default:
      return pw.TextAlign.left;
  }
}

pw.Widget _renderPreviewElement(
  IdCardTemplateElement element,
  RfidStudentRow student,
  Uint8List photoBytes,
  Uint8List? signatureBytes,
) {
  switch (element.type) {
    case IdCardElementType.staticText:
      return pw.Text(
        element.textContent ?? '',
        textAlign: _pdfTextAlign(element.textAlign),
        style: pw.TextStyle(
          fontSize: element.fontSize ?? 10,
          color: _pdfColorOrNull(element.color),
        ),
      );
    case IdCardElementType.idData:
      final key = element.fieldKey;
      return pw.Text(
        key == null ? '' : _previewValueFor(key, student),
        textAlign: _pdfTextAlign(element.textAlign),
        style: pw.TextStyle(
          fontSize: element.fontSize ?? 10,
          color: _pdfColorOrNull(element.color),
        ),
      );
    case IdCardElementType.image:
      // Static template images aren't fetched for this in-dialog preview
      // (it has no Supabase access) — the real printed card, built by
      // lib/documents's buildIdCardPdf, does render them.
      return pw.SizedBox();
    case IdCardElementType.idPicture:
      return pw.Image(pw.MemoryImage(photoBytes), fit: pw.BoxFit.cover);
    case IdCardElementType.signature:
      if (signatureBytes == null) return pw.SizedBox();
      return pw.Image(pw.MemoryImage(signatureBytes), fit: pw.BoxFit.contain);
    case IdCardElementType.rectangle:
    case IdCardElementType.roundedRect:
      final strokeColor = _pdfColorOrNull(element.strokeColor);
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: _pdfColorOrNull(element.fillColor),
          border: strokeColor == null
              ? null
              : pw.Border.all(
                  color: strokeColor,
                  width: element.strokeWidth ?? 1,
                ),
          borderRadius: element.type == IdCardElementType.roundedRect
              ? pw.BorderRadius.circular(element.cornerRadius ?? 0)
              : null,
        ),
      );
    case IdCardElementType.ellipse:
      final strokeColor = _pdfColorOrNull(element.strokeColor);
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: _pdfColorOrNull(element.fillColor),
          border: strokeColor == null
              ? null
              : pw.Border.all(
                  color: strokeColor,
                  width: element.strokeWidth ?? 1,
                ),
          shape: pw.BoxShape.circle,
        ),
      );
    case IdCardElementType.line:
      return pw.Container(
        color: _pdfColorOrNull(element.strokeColor),
      );
  }
}

pw.Widget _buildPreviewSide(
  List<IdCardTemplateElement> elements,
  RfidStudentRow student,
  Uint8List photoBytes,
  Uint8List? signatureBytes,
) {
  return pw.Stack(
    children: [
      for (final element in elements)
        pw.Positioned(
          left: element.x,
          top: element.y,
          child: pw.SizedBox(
            width: element.width,
            height: element.height,
            child: _renderPreviewElement(
                element, student, photoBytes, signatureBytes),
          ),
        ),
    ],
  );
}

Future<Uint8List> _buildPreviewPdf({
  required List<IdCardTemplateElement> frontLayout,
  required List<IdCardTemplateElement> backLayout,
  required Uint8List photoBytes,
  required Uint8List? signatureBytes,
  required RfidStudentRow student,
}) async {
  final format = PdfPageFormat(idCardWidthPt, idCardHeightPt, marginAll: 0);
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: format,
      build: (context) =>
          _buildPreviewSide(frontLayout, student, photoBytes, signatureBytes),
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: format,
      build: (context) =>
          _buildPreviewSide(backLayout, student, photoBytes, signatureBytes),
    ),
  );
  return doc.save();
}
