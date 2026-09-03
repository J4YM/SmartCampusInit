import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../rfid_student_row.dart';
import 'it_technician_dashboard_page.dart' show ItTechnicianColors;
import 'webcam_capture_dialog.dart';

/// Review-and-print screen for a student ID card — shows whatever photo is
/// currently on file (if any), lets the IT Technician (re)capture one via
/// the webcam, and prints once a photo is in hand. Uploading the photo and
/// actually sending the card to the printer both happen in [onPrint], which
/// the host app supplies (this package has no Supabase/printer access of
/// its own).
class IdCardPrintDialog extends StatefulWidget {
  const IdCardPrintDialog({
    super.key,
    required this.student,
    required this.initialPhotoBytes,
    required this.onPrint,
  });

  final RfidStudentRow student;

  /// The student's existing photo, downloaded by the host app before
  /// opening this dialog — null when they don't have one on file yet.
  final Uint8List? initialPhotoBytes;

  /// Uploads [photoBytes] (if changed) and sends the card to the printer.
  /// Rethrows on failure so this dialog can show the error inline.
  final Future<void> Function(Uint8List photoBytes) onPrint;

  @override
  State<IdCardPrintDialog> createState() => _IdCardPrintDialogState();
}

class _IdCardPrintDialogState extends State<IdCardPrintDialog> {
  late Uint8List? _photoBytes = widget.initialPhotoBytes;
  bool _printing = false;
  String? _error;

  Future<void> _capturePhoto() async {
    final bytes = await showDialog<Uint8List>(
      context: context,
      builder: (_) => const WebcamCaptureDialog(),
    );
    if (bytes != null && mounted) setState(() => _photoBytes = bytes);
  }

  Future<void> _handlePrint() async {
    final photoBytes = _photoBytes;
    if (photoBytes == null) return;
    setState(() {
      _printing = true;
      _error = null;
    });
    try {
      await widget.onPrint(photoBytes);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Print Student ID',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ItTechnicianColors.rowText(context),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 110,
                      height: 110,
                      child: _photoBytes == null
                          ? Container(
                              color: ItTechnicianColors.background(context),
                              child: Icon(
                                Icons.person_outline,
                                size: 48,
                                color: ItTechnicianColors.mutedText(context),
                              ),
                            )
                          : Image.memory(_photoBytes!, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 16),
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
                            fontSize: 12,
                            color: ItTechnicianColors.mutedText(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${student.course} — ${student.section}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: ItTechnicianColors.mutedText(context),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _printing ? null : _capturePhoto,
                          icon: const Icon(Icons.camera_alt_outlined,
                              size: 16),
                          label: Text(
                            _photoBytes == null ? 'Capture Photo' : 'Retake',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: ItTechnicianColors.dangerRed),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _printing ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_photoBytes == null || _printing)
                          ? null
                          : _handlePrint,
                      icon: _printing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Print'),
                      style: FilledButton.styleFrom(
                        backgroundColor: ItTechnicianColors.azureBlue,
                      ),
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
}
