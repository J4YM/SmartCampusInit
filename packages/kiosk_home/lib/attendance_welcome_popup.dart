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
const Duration _autoDismiss = Duration(seconds: 5);

/// Shows the "Welcome, STIer!" popup for a successful attendance RFID scan.
/// Dismisses itself after [_autoDismiss], or on tap.
Future<void> showAttendanceWelcomePopup(
  BuildContext context,
  KioskStudentPayload student, {
  String direction = 'in',
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _AttendanceWelcomeDialog(student: student, direction: direction),
  );
}

class _AttendanceWelcomeDialog extends StatefulWidget {
  const _AttendanceWelcomeDialog({required this.student, required this.direction});

  final KioskStudentPayload student;
  final String direction;

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
          title: attendanceGreetingFor(widget.direction),
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
              // Success check: pops in on the avatar's lower-right edge shortly
              // after the photo appears.
              const Positioned(
                left: 458,
                top: 358,
                width: 74,
                height: 74,
                child: _SuccessCheck(),
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

/// Header text for a tap: "Welcome, STIer!" when tapping in,
/// "See you later, STIer!" when tapping out.
String attendanceGreetingFor(String direction) =>
    direction == 'out' ? 'See you later, STIer!' : 'Welcome, STIer!';

const Color _successGreen = Color(0xFF22C55E);

/// Green badge that scales in, then draws its check mark — plays once, a
/// beat after the profile photo is already on screen, to signal the tap was
/// read successfully.
class _SuccessCheck extends StatefulWidget {
  const _SuccessCheck();

  @override
  State<_SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<_SuccessCheck>
    with SingleTickerProviderStateMixin {
  static const Duration _delay = Duration(milliseconds: 400);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _delayTimer = Timer(_delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // First 45%: badge scales in with a slight overshoot; rest: the
        // check stroke draws.
        final pop = Curves.easeOutBack.transform((t / 0.45).clamp(0.0, 1.0));
        final draw = Curves.easeOut.transform(((t - 0.4) / 0.6).clamp(0.0, 1.0));
        return Transform.scale(
          scale: pop,
          child: CustomPaint(painter: _CheckPainter(draw)),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    canvas.drawCircle(center, radius - 5, Paint()..color = _successGreen);

    // Check mark path in a 0..1 box, drawn progressively.
    final p1 = Offset(size.width * 0.28, size.height * 0.52);
    final p2 = Offset(size.width * 0.44, size.height * 0.67);
    final p3 = Offset(size.width * 0.72, size.height * 0.36);
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}
