import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'admission_slip_data.dart';

/// Tailwind-aligned palette (Flutter has no Tailwind runtime; these mirror common tokens).
abstract final class _Tw {
  static const Color pageBg = Color(0xFFF0F4FF); // mint page (screenshot)
  static const Color white = Color(0xFFFFFFFF);
  static const Color gray200 = Color(0xFFE5E7EB);
  static const Color gray500 = Color(0xFF6B7280);
  static const Color gray900 = Color(0xFF111827);
  static const Color red50 = Color(0xFFFEF2F2);
  static const Color rose600 = Color(0xFFE11D48);
  static const Color blue600 = Color(0xFF2563EB);
  static const Color blue900 = Color(0xFF1E3A8A);
  static const Color yellow50 = Color(0xFFFFFBEB);
  static const Color yellow200 = Color(0xFFFDE68A);
  static const Color amber800 = Color(0xFF92400E);
  static const Color amber900 = Color(0xFF78350F);
}

/// Full-screen layout matching the admission slip screenshot (Poppins + placeholder-driven content).
class AdmissionSlipGeneratedView extends StatelessWidget {
  const AdmissionSlipGeneratedView({
    super.key,
    this.data = const AdmissionSlipData(),
  });

  final AdmissionSlipData data;

  TextStyle _poppins({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = _Tw.gray900,
    double? height,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.poppins(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Tw.pageBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 100, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Admission Slip Generated',
                textAlign: TextAlign.center,
                style: _poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _Tw.gray900,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: 18,
                    color: _Tw.gray500,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Take a photo of this slip for your records',
                      textAlign: TextAlign.center,
                      style: _poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: _Tw.gray500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = min(580.0, constraints.maxWidth);
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: cardWidth,
                        height: constraints.maxHeight,
                        child: _SlipCard(data: data, poppins: _poppins),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final actionWidth = min(580.0, constraints.maxWidth);
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: actionWidth,
                      child: FilledButton(
                        onPressed: () => Navigator.maybePop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: _Tw.blue900,
                          foregroundColor: _Tw.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Done',
                          style: _poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: _Tw.white,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlipCard extends StatelessWidget {
  const _SlipCard({
    required this.data,
    required this.poppins,
  });

  final AdmissionSlipData data;
  final TextStyle Function({
    double fontSize,
    FontWeight fontWeight,
    Color color,
    double? height,
    double letterSpacing,
  }) poppins;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _Tw.white,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'VIRTUAL ADMISSION SLIP',
                    textAlign: TextAlign.center,
                    style: poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _Tw.gray900,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Disciplinary Office',
                    textAlign: TextAlign.center,
                    style: poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _Tw.gray500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, thickness: 1, color: _Tw.gray200),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _FieldColumn(
                          entries: [
                            _Field('Student Name', data.studentName),
                            const SizedBox(height: 14),
                            _Field('Grade & Section', data.gradeSection),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _FieldColumn(
                          entries: [
                            _Field('Student Number', data.studentNumber),
                            const SizedBox(height: 14),
                            _Field('Slip ID', data.slipId),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Acknowledged Violations:',
                    style: poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _Tw.gray500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: _Tw.red50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _Tw.rose600,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            data.violationCode,
                            style: poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            data.violationDescription,
                            style: poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _Tw.gray900,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1, thickness: 1, color: _Tw.gray200),
                  const SizedBox(height: 18),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Field('Issue Date & Time', data.issueDateTime),
                      const SizedBox(height: 14),
                      _Field('Valid Until', data.validUntil),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.schedule,
                              size: 18,
                              color: _Tw.blue600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Time Remaining: ${data.timeRemaining}',
                              style: poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _Tw.blue600,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
            child: _ImportantNotice(poppins: poppins),
          ),
        ],
      ),
    );
  }
}

class _ImportantNotice extends StatelessWidget {
  const _ImportantNotice({required this.poppins});

  final TextStyle Function({
    double fontSize,
    FontWeight fontWeight,
    Color color,
    double? height,
    double letterSpacing,
  }) poppins;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _Tw.yellow50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Tw.yellow200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.amber.shade600,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Important Notice',
                  style: poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _Tw.amber900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This admission slip is valid for 72 hours only. Present this to your teacher '
                  'before entering class. Any attempt to duplicate or forge this slip will result '
                  'in additional disciplinary action.',
                  style: poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _Tw.amber800,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldColumn extends StatelessWidget {
  const _FieldColumn({
    required this.entries,
  });

  final List<Widget> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final base = GoogleFonts.poppins();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: base.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _Tw.gray500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: base.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _Tw.gray900,
                height: 1.25,
              ),
            ),
          ],
        );
      },
    );
  }
}
