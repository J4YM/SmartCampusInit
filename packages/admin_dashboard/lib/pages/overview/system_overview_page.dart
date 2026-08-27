import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Data models — swap the default datasets below with Supabase/API streams later.
// ---------------------------------------------------------------------------

class OverviewStatsModel {
  const OverviewStatsModel({
    required this.activeScans,
    required this.activeScansTrend,
    required this.pendingAlerts,
    required this.newAlerts,
    required this.inReviewAlerts,
    required this.resolvedAlerts,
    required this.highRiskCount,
    this.activeScansTrendPoints = _flatSparklinePlaceholder,
    this.alertsTrendPoints = _flatSparklinePlaceholder,
    this.highRiskTrendPoints = _flatSparklinePlaceholder,
    this.weeklyAlerts = const [],
  });

  final int activeScans;
  final String activeScansTrend;
  final int pendingAlerts;
  final int newAlerts;
  final int inReviewAlerts;
  final int resolvedAlerts;
  final int highRiskCount;

  /// Last 7 days, oldest first, each normalized to 0–1 against that week's
  /// peak — feeds the small corner sparkline on each stat card.
  final List<double> activeScansTrendPoints;
  final List<double> alertsTrendPoints;
  final List<double> highRiskTrendPoints;

  /// Last 7 days of new discipline alerts, oldest first — feeds the larger
  /// labeled trend chart below the stat-card row.
  final List<DailyCountModel> weeklyAlerts;
}

/// One day's bar in [_WeeklyAlertsTrendCard] — e.g. label "Mon", count 3.
class DailyCountModel {
  const DailyCountModel({
    required this.label,
    required this.count,
    required this.isToday,
  });

  final String label;
  final int count;
  final bool isToday;
}

class ViolationHotzoneModel {
  const ViolationHotzoneModel({
    required this.categoryName,
    required this.percentageValue,
    required this.barColor,
  });

  final String categoryName;
  final double percentageValue;
  final Color barColor;
}

enum RfidScanType {
  inScan,
  outScan;

  String get label => this == RfidScanType.inScan ? 'IN' : 'OUT';
}

class RfidLogModel {
  const RfidLogModel({
    required this.id,
    required this.avatarInitials,
    required this.studentName,
    required this.studentId,
    required this.scanType,
    required this.location,
    required this.timestamp,
    required this.avatarColor,
  });

  final String id;
  final String avatarInitials;
  final String studentName;
  final String studentId;
  final RfidScanType scanType;
  final String location;
  final DateTime timestamp;
  final Color avatarColor;
}

class AtRiskStudentModel {
  const AtRiskStudentModel({
    required this.avatarInitials,
    required this.name,
    required this.courseYear,
    required this.riskPercentage,
    required this.riskColor,
    required this.riskTags,
    required this.lastSeen,
    required this.assignedCounselor,
    required this.avatarColor,
  });

  final String avatarInitials;
  final String name;
  final String courseYear;
  final int riskPercentage;
  final Color riskColor;
  final List<String> riskTags;
  final String lastSeen;
  final String assignedCounselor;
  final Color avatarColor;
}

// ---------------------------------------------------------------------------
// Default (zero/empty) datasets — swap with Supabase/API-backed data when
// the backend is wired up. Category labels are preserved so the hotzone
// card keeps its structure while every value starts at zero.
// ---------------------------------------------------------------------------

const defaultOverviewStats = OverviewStatsModel(
  activeScans: 0,
  activeScansTrend: '0%',
  pendingAlerts: 0,
  newAlerts: 0,
  inReviewAlerts: 0,
  resolvedAlerts: 0,
  highRiskCount: 0,
);

const defaultViolationHotzones = <ViolationHotzoneModel>[
  ViolationHotzoneModel(
    categoryName: 'Tardiness',
    percentageValue: 0.0,
    barColor: Color(0xFF8B5CF6),
  ),
  ViolationHotzoneModel(
    categoryName: 'Absences',
    percentageValue: 0.0,
    barColor: Color(0xFF3B82F6),
  ),
  ViolationHotzoneModel(
    categoryName: 'Dress Code',
    percentageValue: 0.0,
    barColor: Color(0xFF60A5FA),
  ),
  ViolationHotzoneModel(
    categoryName: 'Phone use',
    percentageValue: 0.0,
    barColor: Color(0xFF06B6D4),
  ),
];

const defaultRfidLogs = <RfidLogModel>[];

const defaultAtRiskStudents = <AtRiskStudentModel>[];

const _flatSparklinePlaceholder = [0.5, 0.5];

// ---------------------------------------------------------------------------
// Theme tokens for the overview light panel.
// ---------------------------------------------------------------------------

abstract final class _OverviewColors {
  static const background = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const cardBorder = Color(0xFFE2E8F0);
  static const liveGreen = Color(0xFF22C55E);
  static const liveGreenBg = Color(0xFFDCFCE7);
  static const inBadgeBg = Color(0xFFDCFCE7);
  static const inBadgeText = Color(0xFF15803D);
  static const outBadgeBg = Color(0xFFFEE2E2);
  static const outBadgeText = Color(0xFFDC2626);
  static const pendingBadgeBg = Color(0xFFFFEDD5);
  static const pendingBadgeText = Color(0xFFEA580C);
  static const flaggedBadgeBg = Color(0xFFFEE2E2);
  static const flaggedBadgeText = Color(0xFFDC2626);
  static const sparklinePlaceholder = Color(0xFFCBD5E1);
  static const emptyStateIcon = Color(0xFFCBD5E1);
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class SystemOverviewPage extends StatelessWidget {
  const SystemOverviewPage({
    super.key,
    required this.stats,
    required this.hotzones,
    required this.rfidLogs,
    required this.atRiskStudents,
  });

  factory SystemOverviewPage.empty({Key? key}) {
    return SystemOverviewPage(
      key: key,
      stats: defaultOverviewStats,
      hotzones: defaultViolationHotzones,
      rfidLogs: defaultRfidLogs,
      atRiskStudents: defaultAtRiskStudents,
    );
  }

  final OverviewStatsModel stats;
  final List<ViolationHotzoneModel> hotzones;
  final List<RfidLogModel> rfidLogs;
  final List<AtRiskStudentModel> atRiskStudents;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _OverviewColors.background,
      child: SafeArea(
        // The scroll view spans the full content pane (no width cap out
        // here) so its scrollbar sits at the pane's true edge; only the
        // inner content is capped at 1440px and centered.
        child: SingleChildScrollView(
          child: DashboardPageWrapper(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'System Overview',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _OverviewColors.primaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Real-time campus monitoring and discipline insights',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: _OverviewColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final useTwoByTwo = constraints.maxWidth < 1100;
                    if (useTwoByTwo) {
                      return Column(
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _ActiveScansCard(stats: stats),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _DisciplineAlertsCard(stats: stats),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _HighRiskCard(stats: stats),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child:
                                      _ViolationHotzoneCard(hotzones: hotzones),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _ActiveScansCard(stats: stats)),
                          const SizedBox(width: 16),
                          Expanded(child: _DisciplineAlertsCard(stats: stats)),
                          const SizedBox(width: 16),
                          Expanded(child: _HighRiskCard(stats: stats)),
                          const SizedBox(width: 16),
                          Expanded(
                              child: _ViolationHotzoneCard(hotzones: hotzones)),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _WeeklyAlertsTrendCard(days: stats.weeklyAlerts),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stackColumns = constraints.maxWidth < 960;
                    if (stackColumns) {
                      return Column(
                        children: [
                          _RfidActivityFeed(logs: rfidLogs),
                          const SizedBox(height: 16),
                          _EarlyWarningPanel(students: atRiskStudents),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: _RfidActivityFeed(logs: rfidLogs),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 4,
                          child: _EarlyWarningPanel(students: atRiskStudents),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat cards
// ---------------------------------------------------------------------------

class _OverviewCardShell extends StatelessWidget {
  const _OverviewCardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _OverviewColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _OverviewColors.cardBorder),
      ),
      child: child,
    );
  }
}

class _StatCardHeader extends StatelessWidget {
  const _StatCardHeader({
    required this.title,
    required this.icon,
    required this.iconBg,
  });

  final String title;
  final IconData icon;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: _OverviewColors.secondaryText,
            ),
          ),
        ),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconBg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: _OverviewColors.primaryText),
        ),
      ],
    );
  }
}

class _ActiveScansCard extends StatelessWidget {
  const _ActiveScansCard({required this.stats});

  final OverviewStatsModel stats;

  @override
  Widget build(BuildContext context) {
    return _OverviewCardShell(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _StatCardHeader(
                title: "TODAY'S ACTIVE SCANS",
                icon: Icons.bolt_rounded,
                iconBg: Color(0xFFDBEAFE),
              ),
              const SizedBox(height: 12),
              Text(
                '${stats.activeScans}',
                style: GoogleFonts.poppins(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: _OverviewColors.primaryText,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                stats.activeScansTrend,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _OverviewColors.secondaryText,
                ),
              ),
            ],
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: _MiniSparkline(
              points: stats.activeScansTrendPoints,
              color: _OverviewColors.sparklinePlaceholder,
            ),
          ),
        ],
      ),
    );
  }
}

class _DisciplineAlertsCard extends StatelessWidget {
  const _DisciplineAlertsCard({required this.stats});

  final OverviewStatsModel stats;

  @override
  Widget build(BuildContext context) {
    return _OverviewCardShell(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _StatCardHeader(
                title: 'DISCIPLINE ALERTS',
                icon: Icons.warning_amber_rounded,
                iconBg: Color(0xFFFEE2E2),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${stats.pendingAlerts}',
                    style: GoogleFonts.poppins(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: _OverviewColors.primaryText,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _OverviewColors.pendingBadgeBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Pending Review',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _OverviewColors.pendingBadgeText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _StatusDot(
                    color: const Color(0xFFEF4444),
                    label: '${stats.newAlerts} New',
                  ),
                  _StatusDot(
                    color: const Color(0xFF64748B),
                    label: '${stats.inReviewAlerts} In Review',
                  ),
                  _StatusDot(
                    color: const Color(0xFF22C55E),
                    label: '${stats.resolvedAlerts} Resolved',
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 0,
            top: 0,
            child: _MiniSparkline(
              points: stats.alertsTrendPoints,
              color: _OverviewColors.sparklinePlaceholder,
            ),
          ),
        ],
      ),
    );
  }
}

class _HighRiskCard extends StatelessWidget {
  const _HighRiskCard({required this.stats});

  final OverviewStatsModel stats;

  @override
  Widget build(BuildContext context) {
    return _OverviewCardShell(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _StatCardHeader(
                title: 'HIGH-RISK STUDENTS',
                icon: Icons.psychology_outlined,
                iconBg: Color(0xFFFEE2E2),
              ),
              const SizedBox(height: 12),
              Text(
                '${stats.highRiskCount}',
                style: GoogleFonts.poppins(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: _OverviewColors.primaryText,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'ML early warning flags',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _OverviewColors.secondaryText,
                ),
              ),
            ],
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: _MiniSparkline(
              points: stats.highRiskTrendPoints,
              color: _OverviewColors.sparklinePlaceholder,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViolationHotzoneCard extends StatelessWidget {
  const _ViolationHotzoneCard({required this.hotzones});

  final List<ViolationHotzoneModel> hotzones;

  @override
  Widget build(BuildContext context) {
    return _OverviewCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StatCardHeader(
            title: 'VIOLATION HOTZONE',
            icon: Icons.error_outline_rounded,
            iconBg: Color(0xFFFEE2E2),
          ),
          const SizedBox(height: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final hotzone in hotzones) ...[
                _HotzoneBar(item: hotzone),
                if (hotzone != hotzones.last) const SizedBox(height: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HotzoneBar extends StatelessWidget {
  const _HotzoneBar({required this.item});

  final ViolationHotzoneModel item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            item.categoryName,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _OverviewColors.secondaryText,
              height: 1.2,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: item.percentageValue,
              minHeight: 8,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: AlwaysStoppedAnimation<Color>(item.barColor),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-width labeled bar chart of new discipline alerts over the last 7
/// calendar days — the "past monitoring, not just today's counter" view the
/// stat cards' tiny corner sparklines can't show on their own.
class _WeeklyAlertsTrendCard extends StatelessWidget {
  const _WeeklyAlertsTrendCard({required this.days});

  final List<DailyCountModel> days;

  @override
  Widget build(BuildContext context) {
    final maxCount = days.isEmpty
        ? 1
        : days
            .map((d) => d.count)
            .reduce((a, b) => a > b ? a : b)
            .clamp(1, 1 << 30);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _OverviewColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _OverviewColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DISCIPLINE ALERTS — LAST 7 DAYS',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: _OverviewColors.secondaryText,
            ),
          ),
          const SizedBox(height: 16),
          if (days.isEmpty)
            const _PanelEmptyState(
              icon: Icons.show_chart,
              message: 'No alerts recorded this week',
            )
          else
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${day.count}',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _OverviewColors.primaryText,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: SizedBox(
                                height: 64 * (day.count / maxCount),
                                child: ColoredBox(
                                  color: day.isToday
                                      ? const Color(0xFF8B5CF6)
                                      : const Color(0xFFC4B5FD),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              day.label,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: day.isToday
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: day.isToday
                                    ? _OverviewColors.primaryText
                                    : _OverviewColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
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

class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: _OverviewColors.secondaryText,
          ),
        ),
      ],
    );
  }
}

class _MiniSparkline extends StatelessWidget {
  const _MiniSparkline({
    required this.points,
    required this.color,
  });

  final List<double> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 36,
      child: CustomPaint(
        painter: _SparklinePainter(points: points, color: color),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.points,
    required this.color,
  });

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * size.width;
      final y = size.height - (points[i] * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}

// ---------------------------------------------------------------------------
// Main split panels
// ---------------------------------------------------------------------------

class _RfidActivityFeed extends StatelessWidget {
  const _RfidActivityFeed({required this.logs});

  final List<RfidLogModel> logs;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'Recent Attendance Activity',
      subtitle: 'Latest attendance check-ins recorded',
      badge: const _LiveBadge(label: '● LIVE'),
      child: logs.isEmpty
          ? const _PanelEmptyState(
              icon: Icons.history,
              message: 'No attendance recorded yet today',
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: logs.length,
              separatorBuilder: (context, index) => const Divider(
                height: 1,
                color: _OverviewColors.cardBorder,
              ),
              itemBuilder: (context, index) => _RfidLogTile(log: logs[index]),
            ),
    );
  }
}

class _EarlyWarningPanel extends StatelessWidget {
  const _EarlyWarningPanel({required this.students});

  final List<AtRiskStudentModel> students;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'Early Warning Triggers',
      subtitle: 'ML-flagged high-risk students',
      badge: _FlaggedBadge(count: students.length),
      child: students.isEmpty
          ? const _PanelEmptyState(
              icon: Icons.inbox_outlined,
              message: 'No flagged students',
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: students.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _AtRiskStudentCard(student: students[index]),
            ),
    );
  }
}

class _PanelEmptyState extends StatelessWidget {
  const _PanelEmptyState({
    required this.icon,
    required this.message,
  });

  static const double height = 220;

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: _OverviewColors.emptyStateIcon),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _OverviewColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget badge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _OverviewColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _OverviewColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _OverviewColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: _OverviewColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              badge,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _OverviewColors.liveGreenBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _OverviewColors.liveGreen,
        ),
      ),
    );
  }
}

class _FlaggedBadge extends StatelessWidget {
  const _FlaggedBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _OverviewColors.flaggedBadgeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count Flagged',
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _OverviewColors.flaggedBadgeText,
        ),
      ),
    );
  }
}

class _RfidLogTile extends StatelessWidget {
  const _RfidLogTile({required this.log});

  final RfidLogModel log;

  @override
  Widget build(BuildContext context) {
    final isIn = log.scanType == RfidScanType.inScan;
    final timeLabel =
        '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InitialAvatar(
            initials: log.avatarInitials,
            color: log.avatarColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        log.studentName,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _OverviewColors.primaryText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ScanTypeBadge(isIn: isIn, label: log.scanType.label),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${log.studentId} · ${log.location}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: _OverviewColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.access_time_rounded,
                size: 14,
                color: _OverviewColors.secondaryText,
              ),
              const SizedBox(width: 4),
              Text(
                timeLabel,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _OverviewColors.secondaryText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AtRiskStudentCard extends StatelessWidget {
  const _AtRiskStudentCard({required this.student});

  final AtRiskStudentModel student;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _OverviewColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InitialAvatar(
                initials: student.avatarInitials,
                color: student.avatarColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.name,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _OverviewColors.primaryText,
                      ),
                    ),
                    Text(
                      student.courseYear,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: _OverviewColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _OverviewColors.flaggedBadgeBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${student.riskPercentage}% risk',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: student.riskColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: student.riskPercentage / 100,
              minHeight: 6,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(student.riskColor),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: student.riskTags
                .map(
                  (tag) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _OverviewColors.secondaryText,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Last seen: ${student.lastSeen}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: _OverviewColors.secondaryText,
                  ),
                ),
              ),
              Text(
                'Counselor: ${student.assignedCounselor}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: _OverviewColors.secondaryText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({
    required this.initials,
    required this.color,
  });

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ScanTypeBadge extends StatelessWidget {
  const _ScanTypeBadge({
    required this.isIn,
    required this.label,
  });

  final bool isIn;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isIn ? _OverviewColors.inBadgeBg : _OverviewColors.outBadgeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color:
              isIn ? _OverviewColors.inBadgeText : _OverviewColors.outBadgeText,
        ),
      ),
    );
  }
}
