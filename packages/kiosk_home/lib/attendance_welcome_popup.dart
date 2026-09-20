import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'kiosk_student_payload.dart';

/// Fixed size of the Attendance popup (Figma node 659:1532).
const double _popupWidth = 820;
const double _popupHeight = 620;

const Color _darkBlue = Color(0xFF27426D);
const Color _mutedBorder = Color(0xFF8F8F8F);
const Color _nameBlue = Color(0xFF345892);
const Color _avatarRing = Color(0xFFD9D9D9);

const AssetImage _placeholderPhoto = AssetImage(
  'assets/images/attendance_profile_placeholder.png',
  package: 'kiosk',
);

/// How long the popup stays up after a scan before dismissing itself.
const Duration _autoDismiss = Duration(seconds: 4);

/// Shows the "Welcome, STIer!" popup for a successful attendance RFID scan.
/// Dismisses itself after [_autoDismiss], or on tap.
Future<void> showAttendanceWelcomePopup(
  BuildContext context,
  KioskStudentPayload student,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _AttendanceWelcomeDialog(student: student),
  );
}

class _AttendanceWelcomeDialog extends StatefulWidget {
  const _AttendanceWelcomeDialog({required this.student});

  final KioskStudentPayload student;

  @override
  State<_AttendanceWelcomeDialog> createState() =>
      _AttendanceWelcomeDialogState();
}

class _AttendanceWelcomeDialogState extends State<_AttendanceWelcomeDialog> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_autoDismiss, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _courseSection {
    final course = widget.student.course?.trim() ?? '';
    final section = widget.student.gradeSection?.trim() ?? '';
    if (course.isNotEmpty && section.isNotEmpty) return '$course- $section';
    return course.isNotEmpty ? course : section;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: AttendanceWelcomeCard(
          name: widget.student.displayName,
          courseSection: _courseSection,
        ),
      ),
    );
  }
}

/// The 820x620 "Welcome, STIer!" card (Figma node 659:1532) on its own, so a
/// host that isn't showing it in a dialog (e.g. the standalone attendance
/// display) can place it directly. Scales down on screens smaller than
/// 820x620 instead of overflowing.
class AttendanceWelcomeCard extends StatelessWidget {
  const AttendanceWelcomeCard({
    super.key,
    required this.name,
    required this.courseSection,
    this.title = 'Welcome, STIer!',
    this.photo,
  });

  final String name;
  final String courseSection;
  final String title;

  /// Replaces the placeholder silhouette (e.g. a signed photo URL).
  final ImageProvider? photo;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: _popupWidth,
        height: _popupHeight,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _mutedBorder),
          ),
          child: Stack(
            children: [
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 107,
                child: ColoredBox(color: _darkBlue),
              ),
              Positioned(
                left: 50,
                top: 0,
                height: 107,
                child: Center(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 40,
                      fontWeight: FontWeight.w600,
                      height: 30 / 40,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              // Profile: 240px ring behind a 230px photo, centered.
              Positioned(
                left: (_popupWidth - 240) / 2,
                top: 190,
                width: 240,
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 240,
                      height: 240,
                      decoration: const BoxDecoration(
                        color: _avatarRing,
                        shape: BoxShape.circle,
                      ),
                    ),
                    ClipOval(
                      child: Image(
                        image: photo ?? _placeholderPhoto,
                        width: 230,
                        height: 230,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Image(
                          image: _placeholderPhoto,
                          width: 230,
                          height: 230,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 465,
                height: 30,
                child: Center(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.italic,
                      height: 30 / 32,
                      letterSpacing: 0.5,
                      color: _nameBlue,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 503,
                height: 30,
                child: Center(
                  child: Text(
                    courseSection,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.italic,
                      height: 30 / 20,
                      letterSpacing: 0.5,
                      color: _nameBlue,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
