import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'kiosk_staff_payload.dart';
import 'kiosk_student_payload.dart';

/// Brand and layout colors matching the Virtual Admission Kiosk design
/// (Figma node 617:1445) — the same navy/yellow tokens as the login
/// screen's campus-photo treatment, kept local to this package rather than
/// depending on `login_module` for them.
class _KioskColors {
  static const Color overlayNavy = Color(0xFF15253F);
  static const Color brandYellow = Color(0xFFFACC15);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color heading = Color(0xFF1F2937);
  static const Color body = Color(0xFF6B7280);
  static const Color errorBg = Color(0xFFFEE2E2);
  static const Color errorText = Color(0xFFB91C1C);
}

/// Fixed width/height of the RFID card and the gap reserved between it and
/// the branding text in the side-by-side layout.
const double _cardWidth = 500;
const double _cardHeight = 650;
const double _brandingCardGap = 120;

/// Minimum width the branding text needs so "STI COLLEGE" wraps to at most
/// two lines at its 96px font size — squeezed narrower than this, it wraps
/// enough to overflow the card's height instead. Below
/// [_wideLayoutBreakpoint], the branding text and card stack instead of
/// sitting side by side, which has no such width limit (it scrolls).
const double _minBrandingWidth = 640;
const double _wideLayoutBreakpoint =
    _cardWidth + _brandingCardGap + _minBrandingWidth;

/// Full-screen kiosk: RFID keyboard wedge + tap-to-focus, validates UID via [identifyStudent].
class VirtualAdmissionKioskScreen extends StatefulWidget {
  const VirtualAdmissionKioskScreen({
    super.key,
    required this.identifyStudent,
    required this.onStudentIdentified,
    this.identifyStaff,
    this.onStaffIdentified,
    this.invalidRfidMessage = 'Invalid RFID',
  });

  final IdentifyStudentFromRfid identifyStudent;
  final OnStudentIdentifiedFromKiosk onStudentIdentified;

  /// Consulted only when [identifyStudent] returns null for a tap — lets the
  /// same reader recognize a staff/security card and branch into a
  /// different flow instead of showing "Invalid RFID". Omit to keep this
  /// screen student-only (its original behavior).
  final IdentifyStaffFromRfid? identifyStaff;
  final OnStaffIdentifiedFromKiosk? onStaffIdentified;
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

  static const String _scannerAsset = 'assets/images/rfid.png';
  static const String _backgroundAsset = 'assets/images/campus_background.png';

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

      final identifyStaff = widget.identifyStaff;
      if (identifyStaff != null) {
        final staff = await identifyStaff(uid);
        if (!mounted) return;
        if (staff != null) {
          setState(() => _busy = false);
          widget.onStaffIdentified?.call(context, staff);
          _scanController.clear();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scanFocus.requestFocus();
          });
          return;
        }
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _refocusScanner,
      child: Scaffold(
        backgroundColor: _KioskColors.overlayNavy,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              _backgroundAsset,
              package: 'kiosk',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const ColoredBox(color: _KioskColors.overlayNavy);
              },
            ),
            // Darkens the campus photo for text legibility — same treatment
            // as the login screen's full-screen background.
            ColoredBox(color: _KioskColors.overlayNavy.withOpacity(0.55)),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorText != null) _ErrorBanner(text: _errorText!),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow =
                            constraints.maxWidth < _wideLayoutBreakpoint;

                        final branding = _BrandingBlock(centered: isNarrow);
                        final card = _RfidCard(
                          busy: _busy,
                          scannerAsset: _scannerAsset,
                        );

                        if (isNarrow) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 32,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight - 64,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  branding,
                                  const SizedBox(height: 32),
                                  card,
                                ],
                              ),
                            ),
                          );
                        }

                        // Clusters the branding text and the card together
                        // near the screen's horizontal (and vertical)
                        // center, with a fixed inner gap between them,
                        // instead of pinning each to an opposite edge.
                        return Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: branding),
                              const SizedBox(width: _brandingCardGap),
                              card,
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Near-invisible field that captures the RFID reader's keyboard
            // wedge input; kept off-screen visually but focused/tappable.
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
    );
  }
}

/// "STI COLLEGE" / "Baliuag" split-color branding text over the campus photo.
class _BrandingBlock extends StatelessWidget {
  const _BrandingBlock({required this.centered});

  final bool centered;

  @override
  Widget build(BuildContext context) {
    final crossAxisAlignment =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text.rich(
          textAlign: textAlign,
          TextSpan(
            style: GoogleFonts.poppins(
              fontSize: 96,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
            children: const [
              TextSpan(
                text: 'STI ',
                style: TextStyle(color: _KioskColors.brandYellow),
              ),
              TextSpan(
                text: 'COLLEGE',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Baliuag',
          textAlign: textAlign,
          style: GoogleFonts.poppins(
            fontSize: 48,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// White rounded "Scan your RFID" card floated over the campus photo.
class _RfidCard extends StatelessWidget {
  const _RfidCard({required this.busy, required this.scannerAsset});

  final bool busy;
  final String scannerAsset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _cardWidth,
      height: _cardHeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 56),
        decoration: BoxDecoration(
          color: _KioskColors.cardWhite,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Scan your RFID',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: _KioskColors.heading,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Place your student ID on the reader',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w400,
                color: _KioskColors.body,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 48),
            if (busy)
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              SizedBox(
                width: 160,
                height: 160,
                child: Image.asset(
                  scannerAsset,
                  package: 'kiosk',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  semanticLabel: 'Tap your ID card against the RFID reader',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Floating error pill shown over the campus photo when a scan is rejected.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _KioskColors.errorBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: _KioskColors.errorText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _KioskColors.errorText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
