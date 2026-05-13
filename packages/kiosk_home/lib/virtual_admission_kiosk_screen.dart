import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'kiosk_student_payload.dart';

/// Brand and layout colors matching the Virtual Admission Kiosk design.
class _KioskColors {
  static const Color headerBlue = Color(0xFF001A99);
  static const Color pageBackground = Color(0xFFE1F5FE);
  static const Color heading = Color(0xFF1F2937);
  static const Color body = Color(0xFF6B7280);
}

/// Full-screen kiosk: RFID keyboard wedge + tap-to-focus, validates UID via [identifyStudent].
class VirtualAdmissionKioskScreen extends StatefulWidget {
  const VirtualAdmissionKioskScreen({
    super.key,
    required this.identifyStudent,
    required this.onStudentIdentified,
    this.invalidRfidMessage = 'Invalid RFID',
  });

  final IdentifyStudentFromRfid identifyStudent;
  final OnStudentIdentifiedFromKiosk onStudentIdentified;
  final String invalidRfidMessage;

  @override
  State<VirtualAdmissionKioskScreen> createState() =>
      _VirtualAdmissionKioskScreenState();
}

class _VirtualAdmissionKioskScreenState extends State<VirtualAdmissionKioskScreen> {
  final FocusNode _scanFocus = FocusNode();
  final TextEditingController _scanController = TextEditingController();

  String? _errorText;
  bool _busy = false;

  static const String _scannerAsset = 'assets/images/scanner_logo.png';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _scanFocus.dispose();
    _scanController.dispose();
    super.dispose();
  }

  Future<void> _handleScannedUid(String raw) async {
    final uid = raw.trim();
    if (uid.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      final student = await widget.identifyStudent(uid);
      if (!mounted) return;
      if (student != null) {
        setState(() => _busy = false);
        widget.onStudentIdentified(context, student);
        _scanController.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scanFocus.requestFocus();
        });
        return;
      }
      setState(() {
        _busy = false;
        _errorText = widget.invalidRfidMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = 'Could not verify RFID. Check network and Supabase.';
      });
    }

    _scanController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanFocus.requestFocus();
    });
  }

  void _refocusScanner() {
    _scanFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = GoogleFonts.poppins(
      color: Colors.white,
      fontSize: 35,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    final subtitleStyle = GoogleFonts.poppins(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.w400,
      height: 1.3,
    );

    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _refocusScanner,
        child: Scaffold(
          backgroundColor: _KioskColors.pageBackground,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                color: _KioskColors.headerBlue,
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('STI College Baliuag', style: titleStyle),
                    const SizedBox(height: 6),
                    Text('Virtual Admission Kiosk', style: subtitleStyle),
                  ],
                ),
              ),
              if (_errorText != null)
                Material(
                  color: const Color(0xFFFEE2E2),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorText!,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFB91C1C),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: 500,
                          height: 620,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(50, 90, 50, 36),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Scan your RFID',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w700,
                                    color: _KioskColors.heading,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Place your student ID on the reader, or tap anywhere '
                                  'and use the hardware RFID keyboard input.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w400,
                                    color: _KioskColors.body,
                                    height: 1.45,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      const Spacer(),
                                      if (_busy)
                                        const Padding(
                                          padding: EdgeInsets.only(bottom: 24),
                                          child: CircularProgressIndicator(),
                                        )
                                      else
                                        SizedBox(
                                          width: 170,
                                          height: 170,
                                          child: Image.asset(
                                            _scannerAsset,
                                            package: 'kiosk',
                                            fit: BoxFit.contain,
                                            filterQuality: FilterQuality.high,
                                            semanticLabel: 'RFID scanner symbol',
                                          ),
                                        ),
                                      const Spacer(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 8,
                      height: 1,
                      child: Opacity(
                        opacity: 0.02,
                        child: TextField(
                          controller: _scanController,
                          focusNode: _scanFocus,
                          autofocus: true,
                          keyboardType: TextInputType.visiblePassword,
                          enableSuggestions: false,
                          autocorrect: false,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(border: InputBorder.none),
                          onSubmitted: (value) {
                            if (!_busy) {
                              _handleScannedUid(value);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }
}
