import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/attendance_models.dart';
import '../models/good_moral_request_status.dart';
import '../models/intervention_models.dart';
import '../models/schedule_models.dart';
import '../models/violation_models.dart';
import '../pages/interventions_page.dart' show InterventionFilter;
import '../pages/violations_page.dart' show ViolationFilter;
import '../theme/parent_portal_colors.dart';
import '../theme/parent_portal_spacing.dart';
import '../util/date_format.dart';
import 'portal_surface_card.dart';
import 'section_header.dart';
import 'status_badge.dart';
import 'violation_row.dart';

// ---------------------------------------------------------------------------
// The Parent Portal's own building blocks. A parent checks in on their child
// rather than managing their own day, so these answer, in plain language:
// is my child at school today, does anything need my attention, how is
// attendance trending, how is their conduct, and where are they supposed to
// be. Compare the Student Portal's self-focused ring + month calendar.
// ---------------------------------------------------------------------------

/// One status per school day — a day with any absence counts as absent,
/// then late, then excused (see [aggregateStatus]).
Map<DateTime, AttendanceStatus> dailyStatuses(List<AttendanceEntry> entries) {
  final byDay = <DateTime, List<AttendanceEntry>>{};
  for (final e in entries) {
    (byDay[dateOnly(e.date)] ??= []).add(e);
  }
  return {
    for (final entry in byDay.entries) entry.key: aggregateStatus(entry.value)!,
  };
}

/// Weekday numbers (1 = Monday) a schedule entry meets on. Accepts the
/// class-schedule codes ('M', 'T', 'W', 'TH', 'F', 'S') as well as short
/// and full day names.
Set<int> scheduleWeekdays(StudentScheduleEntryModel entry) {
  int? parse(String raw) {
    final v = raw.trim().toUpperCase();
    if (v.startsWith('TH')) return DateTime.thursday;
    if (v.startsWith('TU') || v == 'T') return DateTime.tuesday;
    if (v.startsWith('M')) return DateTime.monday;
    if (v.startsWith('W')) return DateTime.wednesday;
    if (v.startsWith('F')) return DateTime.friday;
    if (v.startsWith('SU')) return DateTime.sunday;
    if (v.startsWith('S')) return DateTime.saturday;
    return null;
  }

  return {for (final d in entry.days) parse(d)}.whereType<int>().toSet();
}

/// "07:30" / "07:30:00" -> "7:30 AM".
String formatClockTime(String raw) => formatClock12h(raw);

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

Widget _cardTitle(BuildContext context, String title, {String? subtitle}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: ParentPortalSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: ParentPortalColors.textPrimary(context),
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: ParentPortalColors.textSecondary(context),
            ),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Child banner
// ---------------------------------------------------------------------------

/// Greets the parent, then introduces the child this portal is about.
class ChildProfileBanner extends StatelessWidget {
  const ChildProfileBanner({
    super.key,
    required this.parentName,
    required this.childName,
    required this.programLine,
    this.studentNumber,
  });

  final String parentName;
  final String childName;
  final String programLine;
  final String? studentNumber;

  @override
  Widget build(BuildContext context) {
    final firstName = parentName.trim().split(RegExp(r'\s+')).first;
    final accent = subNavActiveColor(context, const Color(0xFF345892));

    final child = Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: accent.withOpacity(context.isDarkMode ? 0.22 : 0.12),
          child: Text(
            _initials(childName),
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: ParentPortalSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR CHILD',
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: ParentPortalColors.textMuted(context),
                ),
              ),
              Text(
                childName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ParentPortalColors.textPrimary(context),
                ),
              ),
              Text(
                [
                  if (programLine.isNotEmpty) programLine,
                  if (studentNumber != null && studentNumber!.isNotEmpty)
                    'Student No. $studentNumber',
                ].join('  ·  '),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: ParentPortalColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final greeting = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatFullWeekdayDate(DateTime.now()),
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: accent,
          ),
        ),
        Text(
          '${greetingForHour(DateTime.now().hour)}, $firstName',
          style: GoogleFonts.poppins(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: ParentPortalColors.textPrimary(context),
          ),
        ),
      ],
    );

    return PortalSurfaceCard(
      child: context.isMobileWidth
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                greeting,
                const SizedBox(height: ParentPortalSpacing.lg),
                Divider(
                    height: 1, color: ParentPortalColors.cardBorder(context)),
                const SizedBox(height: ParentPortalSpacing.lg),
                child,
              ],
            )
          : Row(
              children: [
                Expanded(child: greeting),
                Container(
                  width: 1,
                  height: 64,
                  margin: const EdgeInsets.symmetric(
                      horizontal: ParentPortalSpacing.xl),
                  color: ParentPortalColors.cardBorder(context),
                ),
                Expanded(child: child),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today
// ---------------------------------------------------------------------------

/// The first thing a parent wants to know: is my child at school today,
/// and what classes do they have.
class TodayStatusCard extends StatelessWidget {
  const TodayStatusCard({
    super.key,
    required this.childFirstName,
    required this.todayStatus,
    required this.todaysClasses,
    this.onViewAll,
  });

  /// Opens the child's complete weekly schedule; hides the button if null.
  final VoidCallback? onViewAll;

  final String childFirstName;

  /// Null when nothing has been recorded for today (yet).
  final AttendanceStatus? todayStatus;
  final List<StudentScheduleEntryModel> todaysClasses;

  @override
  Widget build(BuildContext context) {
    final weekday = DateTime.now().weekday;
    final noClassDay = weekday == DateTime.sunday ||
        (todaysClasses.isEmpty && todayStatus == null);

    final (IconData icon, Color fg, Color bg, String headline, String detail) =
        switch (todayStatus) {
      AttendanceStatus.present => (
          Icons.check_circle_rounded,
          ParentPortalColors.presentFg(context),
          ParentPortalColors.presentBg(context),
          '$childFirstName is in school today',
          'Marked present.',
        ),
      AttendanceStatus.late => (
          Icons.watch_later_rounded,
          ParentPortalColors.lateFg(context),
          ParentPortalColors.lateBg(context),
          '$childFirstName arrived late today',
          'Marked late — in school, but after the start of class.',
        ),
      AttendanceStatus.absent => (
          Icons.cancel_rounded,
          ParentPortalColors.absentFg(context),
          ParentPortalColors.absentBg(context),
          '$childFirstName is marked absent today',
          'If this is unexpected, please contact the school.',
        ),
      AttendanceStatus.excused => (
          Icons.info_rounded,
          ParentPortalColors.excusedFg(context),
          ParentPortalColors.excusedBg(context),
          "$childFirstName's absence today is excused",
          'Marked excused.',
        ),
      null => noClassDay
          ? (
              Icons.weekend_rounded,
              ParentPortalColors.textSecondary(context),
              ParentPortalColors.surfaceMuted(context),
              'No classes today',
              'Nothing is scheduled for $childFirstName today.',
            )
          : (
              Icons.schedule_rounded,
              ParentPortalColors.textSecondary(context),
              ParentPortalColors.surfaceMuted(context),
              'No attendance recorded yet today',
              'It will appear here once $childFirstName is checked in.',
            ),
    };

    final sorted = [...todaysClasses]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: ParentPortalSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Today',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ParentPortalColors.textPrimary(context),
                    ),
                  ),
                ),
                if (onViewAll != null)
                  TextButton(
                    onPressed: onViewAll,
                    style: TextButton.styleFrom(
                      foregroundColor: subNavActiveColor(
                          context, ParentPortalColors.brandPrimary),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'View all',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(ParentPortalSpacing.md),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(icon, size: 34, color: fg),
                const SizedBox(width: ParentPortalSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ParentPortalColors.textPrimary(context),
                        ),
                      ),
                      Text(
                        detail,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: ParentPortalColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ParentPortalSpacing.md),
          Text(
            sorted.isEmpty
                ? 'No classes scheduled today.'
                : "Today's classes (${sorted.length})",
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ParentPortalColors.textSecondary(context),
            ),
          ),
          for (final c in sorted)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(
                      formatClockTime(c.startTime),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ParentPortalColors.textPrimary(context),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      c.room.isEmpty
                          ? c.subjectTitle
                          : '${c.subjectTitle}  ·  ${c.room}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: ParentPortalColors.textSecondary(context),
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

// ---------------------------------------------------------------------------
// This month at a glance
// ---------------------------------------------------------------------------

/// This month's attendance in whole school days, with a plain-language
/// verdict instead of a bare percentage ring.
class AttendanceSummaryCard extends StatelessWidget {
  const AttendanceSummaryCard({
    super.key,
    required this.statusByDay,
    this.tilesPerRow,
  });

  final Map<DateTime, AttendanceStatus> statusByDay;

  /// Fixes how many count tiles sit in a row (1–4). The page passes this when
  /// the card must share a row with a same-height neighbour: an
  /// [IntrinsicHeight] can't measure the [LayoutBuilder] this card otherwise
  /// uses to pick the count itself, which is what null falls back to.
  final int? tilesPerRow;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = statusByDay.entries
        .where((e) => e.key.year == now.year && e.key.month == now.month)
        .map((e) => e.value)
        .toList();
    int count(AttendanceStatus s) => month.where((m) => m == s).length;
    final present = count(AttendanceStatus.present);
    final late = count(AttendanceStatus.late);
    final absent = count(AttendanceStatus.absent);
    final excused = count(AttendanceStatus.excused);
    // Late still means "at school".
    final attended = present + late;
    final rate = month.isEmpty ? null : attended / month.length;

    final (String verdict, Color verdictFg) = switch (rate) {
      null => (
          'No school days recorded yet this month',
          ParentPortalColors.textSecondary(context)
        ),
      >= 0.9 => ('Good attendance', ParentPortalColors.presentFg(context)),
      >= 0.8 => (
          'Fair — worth keeping an eye on',
          ParentPortalColors.pendingFg(context)
        ),
      _ => ('Needs improvement', ParentPortalColors.absentFg(context)),
    };

    Widget tile(String label, int value, Color fg, Color bg) => Container(
          padding: const EdgeInsets.symmetric(
              horizontal: ParentPortalSpacing.md, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              Text(
                '$label ${value == 1 ? 'day' : 'days'}',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: ParentPortalColors.textSecondary(context),
                ),
              ),
            ],
          ),
        );

    final tiles = [
      tile('Present', present, ParentPortalColors.presentFg(context),
          ParentPortalColors.presentBg(context)),
      tile('Late', late, ParentPortalColors.lateFg(context),
          ParentPortalColors.lateBg(context)),
      tile('Absent', absent, ParentPortalColors.absentFg(context),
          ParentPortalColors.absentBg(context)),
      tile('Excused', excused, ParentPortalColors.excusedFg(context),
          ParentPortalColors.excusedBg(context)),
    ];

    return PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(context, 'This month at a glance',
              subtitle: formatMonthYear(now)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rate == null ? '—' : '${(rate * 100).round()}%',
                style: GoogleFonts.poppins(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: ParentPortalColors.textPrimary(context),
                ),
              ),
              const SizedBox(width: ParentPortalSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    rate == null ? verdict : 'attended  ·  $verdict',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: verdictFg,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (rate != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 8,
                backgroundColor: ParentPortalColors.surfaceMuted(context),
                valueColor: AlwaysStoppedAnimation(verdictFg),
              ),
            ),
          ],
          const SizedBox(height: ParentPortalSpacing.md),
          if (tilesPerRow case final perRow?)
            Column(
              children: [
                for (var i = 0; i < tiles.length; i += perRow) ...[
                  if (i > 0) const SizedBox(height: ParentPortalSpacing.sm),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = 0; j < perRow; j++) ...[
                          if (j > 0)
                            const SizedBox(width: ParentPortalSpacing.sm),
                          Expanded(
                            child: i + j < tiles.length
                                ? tiles[i + j]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final perRow = c.maxWidth < 360 ? 2 : 4;
                const gap = ParentPortalSpacing.sm;
                final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final t in tiles) SizedBox(width: w, child: t),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Discipline
// ---------------------------------------------------------------------------

/// The tinted one-line status strip at the top of the Conduct and
/// Interventions cards. With an [onTap] it is a button (chevron shown) that
/// opens the full list on the relevant tab.
class _StandingBanner extends StatelessWidget {
  const _StandingBanner({
    required this.icon,
    required this.foreground,
    required this.background,
    required this.text,
    this.onTap,
  });

  final IconData icon;
  final Color foreground;
  final Color background;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Material(
      color: background,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: ParentPortalSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: ParentPortalColors.textPrimary(context),
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: ParentPortalSpacing.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: foreground,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Conduct record with a one-line standing summary, then the latest cases.
class DisciplineSummaryCard extends StatelessWidget {
  const DisciplineSummaryCard({
    super.key,
    required this.violations,
    required this.onSeeAll,
    required this.onOpenFiltered,
    required this.onOpenViolation,
  });

  final List<StudentViolationModel> violations;
  final VoidCallback onSeeAll;

  /// Opens the full Violations page on the given tab (the banner tap).
  final ValueChanged<ViolationFilter> onOpenFiltered;
  final ValueChanged<StudentViolationModel> onOpenViolation;

  @override
  Widget build(BuildContext context) {
    final pending =
        violations.where((v) => v.status == ViolationStatus.pending).length;
    final major =
        violations.where((v) => v.category == ViolationCategory.major).length;
    final sorted = [...violations]
      ..sort((a, b) => b.dateFiled.compareTo(a.dateFiled));

    final (IconData icon, Color fg, Color bg, String standing) =
        violations.isEmpty
            ? (
                Icons.verified_rounded,
                ParentPortalColors.presentFg(context),
                ParentPortalColors.presentBg(context),
                'Good standing — no offenses on record.',
              )
            : pending > 0
                ? (
                    Icons.hourglass_top_rounded,
                    ParentPortalColors.pendingFg(context),
                    ParentPortalColors.pendingBg(context),
                    '$pending case${pending == 1 ? '' : 's'} still under review.',
                  )
                : (
                    Icons.task_alt_rounded,
                    ParentPortalColors.recordedFg(context),
                    ParentPortalColors.recordedBg(context),
                    'All cases resolved and recorded.',
                  );

    return PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Conduct & discipline',
            onSeeAll: violations.isEmpty ? null : onSeeAll,
          ),
          _StandingBanner(
            icon: icon,
            foreground: fg,
            background: bg,
            text: standing,
            // Opens the full list on the tab the banner is talking about.
            onTap: violations.isEmpty
                ? null
                : () => onOpenFiltered(
                      pending > 0
                          ? ViolationFilter.pending
                          : ViolationFilter.recorded,
                    ),
          ),
          if (violations.isNotEmpty) ...[
            const SizedBox(height: ParentPortalSpacing.sm),
            Text(
              '${violations.length} on record  ·  $major major  ·  '
              '${violations.length - major} minor',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: ParentPortalColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: ParentPortalSpacing.sm),
            for (final v in sorted.take(3))
              ViolationRow(violation: v, onTap: () => onOpenViolation(v)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weekly class schedule
// ---------------------------------------------------------------------------

/// The child's classes grouped by school day, today's highlighted — so a
/// parent can see where their child should be at any time.
class WeeklyScheduleCard extends StatelessWidget {
  const WeeklyScheduleCard({
    super.key,
    required this.entries,
    this.embedded = false,
  });

  final List<StudentScheduleEntryModel> entries;

  /// Content only — no card chrome or title — for use inside a sheet that
  /// already has its own heading.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final todayWeekday = DateTime.now().weekday;
    final accent = subNavActiveColor(context, const Color(0xFF345892));
    final byDay = <int, List<StudentScheduleEntryModel>>{};
    for (final e in entries) {
      for (final d in scheduleWeekdays(e)) {
        (byDay[d] ??= []).add(e);
      }
    }
    for (final list in byDay.values) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
    final days = byDay.keys.toList()..sort();

    final card = PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!embedded)
            _cardTitle(context, 'Class schedule',
                subtitle: entries.isEmpty
                    ? null
                    : '${entries.length} subject${entries.length == 1 ? '' : 's'} this term'),
          if (entries.isEmpty)
            Text(
              'No classes enrolled yet.',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: ParentPortalColors.textSecondary(context),
              ),
            )
          else
            for (final day in days) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Row(
                  children: [
                    Text(
                      _weekdayNameFull(day),
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: day == todayWeekday
                            ? accent
                            : ParentPortalColors.textPrimary(context),
                      ),
                    ),
                    if (day == todayWeekday) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(
                          color: accent
                              .withOpacity(context.isDarkMode ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'Today',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              for (final e in byDay[day]!)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: day == todayWeekday
                        ? accent.withOpacity(context.isDarkMode ? 0.12 : 0.06)
                        : ParentPortalColors.surfaceMuted(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // Phones stack the time above the subject so long subject
                  // names aren't cut off; wider screens keep them side by side.
                  child: Flex(
                    direction:
                        context.isMobileWidth ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: context.isMobileWidth ? null : 138,
                        child: Text(
                          '${formatClockTime(e.startTime)} – '
                          '${formatClockTime(e.endTime)}',
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: ParentPortalColors.textPrimary(context),
                          ),
                        ),
                      ),
                      _expandedInRow(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.subjectTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: ParentPortalColors.textPrimary(context),
                              ),
                            ),
                            Text(
                              [
                                if (e.room.isNotEmpty) 'Room ${e.room}',
                                if (e.professorName.isNotEmpty) e.professorName,
                              ].join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color:
                                    ParentPortalColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
        ],
      ),
    );
    return embedded ? card.child : card;
  }
}

/// [child] as-is in the stacked phone layout, [Expanded] in the side-by-side
/// one (a vertical Flex inside a scroll view has unbounded height).
Widget _expandedInRow(BuildContext context, Widget child) =>
    context.isMobileWidth ? child : Expanded(child: child);

String _weekdayNameFull(int weekday) => const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][weekday - 1];

// ---------------------------------------------------------------------------
// Document requests
// ---------------------------------------------------------------------------

/// The child's Good Moral certificate requests, with a clear status and a
/// "Request Good Moral" button in the card header.
class DocumentRequestsCard extends StatelessWidget {
  const DocumentRequestsCard({
    super.key,
    required this.requests,
    required this.onRequest,
  });

  final List<GoodMoralRequestStatus> requests;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title and button share a row when the card is wide enough; in a
          // narrow card the button drops below the title.
          LayoutBuilder(
            builder: (context, c) {
              final title = Text(
                'Student\'s Document',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ParentPortalColors.textPrimary(context),
                ),
              );
              final button = SecondaryPillButton(
                label: 'Request Good Moral',
                icon: Icons.add_rounded,
                onTap: onRequest,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: ParentPortalSpacing.md),
                child: c.maxWidth < 380
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          const SizedBox(height: ParentPortalSpacing.sm),
                          button,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: title),
                          const SizedBox(width: ParentPortalSpacing.sm),
                          button,
                        ],
                      ),
              );
            },
          ),
          if (requests.isEmpty)
            Text(
              "You haven't requested any documents yet.",
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: ParentPortalColors.textSecondary(context),
              ),
            )
          else
            for (final r in requests)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      r.isFulfilled
                          ? Icons.check_circle_rounded
                          : Icons.hourglass_top_rounded,
                      size: 18,
                      color: r.isFulfilled
                          ? ParentPortalColors.presentFg(context)
                          : ParentPortalColors.pendingFg(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.documentType,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: ParentPortalColors.textPrimary(context),
                            ),
                          ),
                          Text(
                            r.isFulfilled
                                ? 'Ready — ${r.purpose}'
                                : 'Being processed — ${r.purpose}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              color: ParentPortalColors.textSecondary(context),
                            ),
                          ),
                        ],
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

// ---------------------------------------------------------------------------
// Interventions
// ---------------------------------------------------------------------------

/// Messages from the school about interventions for the child (a counselor
/// asking for a conference, a conduct follow-up, …), laid out like the
/// Conduct & discipline card: header with "View all", a one-line standing, a
/// count line, then the latest few compact rows. Tapping a row opens that
/// message's detail popup; "View all" opens the full list page.
class InterventionsCard extends StatelessWidget {
  const InterventionsCard({
    super.key,
    required this.messages,
    required this.onSeeAll,
    required this.onOpenFiltered,
    required this.onOpenMessage,
  });

  final List<InterventionMessageModel> messages;
  final VoidCallback onSeeAll;

  /// Opens the full Interventions page on the given tab (the banner tap).
  final ValueChanged<InterventionFilter> onOpenFiltered;
  final ValueChanged<InterventionMessageModel> onOpenMessage;

  @override
  Widget build(BuildContext context) {
    final sorted = [...messages]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final unread = messages.where((m) => !m.isRead).length;
    final actionNeeded = messages.where((m) => m.actionRequired).length;

    final (IconData icon, Color fg, Color bg, String standing) =
        messages.isEmpty
            ? (
                Icons.mark_email_read_outlined,
                ParentPortalColors.presentFg(context),
                ParentPortalColors.presentBg(context),
                'No messages from the school right now.',
              )
            : unread > 0
                ? (
                    Icons.mark_email_unread_outlined,
                    ParentPortalColors.pendingFg(context),
                    ParentPortalColors.pendingBg(context),
                    '$unread unread message${unread == 1 ? '' : 's'} from '
                        'the school.',
                  )
                : (
                    Icons.task_alt_rounded,
                    ParentPortalColors.recordedFg(context),
                    ParentPortalColors.recordedBg(context),
                    "You're all caught up.",
                  );

    return PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Interventions',
            onSeeAll: messages.isEmpty ? null : onSeeAll,
          ),
          _StandingBanner(
            icon: icon,
            foreground: fg,
            background: bg,
            text: standing,
            // Opens the full list on the tab the banner is talking about.
            onTap: messages.isEmpty
                ? null
                : () => onOpenFiltered(
                      unread > 0
                          ? InterventionFilter.unread
                          : InterventionFilter.all,
                    ),
          ),
          if (messages.isNotEmpty) ...[
            const SizedBox(height: ParentPortalSpacing.sm),
            Text(
              '${messages.length} on record  ·  $actionNeeded need action  ·  '
              '${messages.length - unread} read',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: ParentPortalColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: ParentPortalSpacing.sm),
            for (final m in sorted.take(3))
              InterventionTile(message: m, onTap: () => onOpenMessage(m)),
          ],
        ],
      ),
    );
  }
}

/// One compact intervention row, in the same shape as a conduct case row:
/// topic badge, title, date and a chevron (two lines when narrow). Unread
/// messages get a red dot; ones needing action are tinted amber. The full
/// text is only in the detail popup.
class InterventionTile extends StatelessWidget {
  const InterventionTile({
    super.key,
    required this.message,
    required this.onTap,
  });

  final InterventionMessageModel message;
  final VoidCallback onTap;

  static const _twoLineBelow = 460.0;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final urgent = m.actionRequired;
    final stripe = urgent
        ? ParentPortalColors.pendingFg(context)
        : ParentPortalColors.excusedFg(context);

    final badges = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusBadge(
          label: m.kind.label,
          foreground: ParentPortalColors.excusedFg(context),
          background: ParentPortalColors.excusedBg(context),
          icon: m.kind.icon,
          dense: true,
        ),
        if (urgent) ...[
          const SizedBox(width: ParentPortalSpacing.xs),
          StatusBadge(
            label: 'Action needed',
            foreground: ParentPortalColors.pendingFg(context),
            background: ParentPortalColors.pendingBg(context),
            dense: true,
          ),
        ],
      ],
    );

    final wrappedBadges = Wrap(
      spacing: ParentPortalSpacing.xs,
      runSpacing: ParentPortalSpacing.xs,
      children: [
        StatusBadge(
          label: m.kind.label,
          foreground: ParentPortalColors.excusedFg(context),
          background: ParentPortalColors.excusedBg(context),
          icon: m.kind.icon,
          dense: true,
        ),
        if (urgent)
          StatusBadge(
            label: 'Action needed',
            foreground: ParentPortalColors.pendingFg(context),
            background: ParentPortalColors.pendingBg(context),
            dense: true,
          ),
      ],
    );

    Widget title(int lines) => Row(
          children: [
            if (!m.isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: ParentPortalColors.absentFg(context),
                  shape: BoxShape.circle,
                ),
              ),
            Expanded(
              child: Text(
                m.title,
                maxLines: lines,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: m.isRead ? FontWeight.w500 : FontWeight.w700,
                  color: ParentPortalColors.textPrimary(context),
                ),
              ),
            ),
          ],
        );

    final date = Text(
      formatMonthDayYear(m.createdAt),
      style: GoogleFonts.poppins(
        fontSize: 11.5,
        color: ParentPortalColors.textMuted(context),
      ),
    );
    final chevron = Icon(
      Icons.chevron_right_rounded,
      size: 18,
      color: ParentPortalColors.textMuted(context),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: ParentPortalSpacing.sm),
      child: Material(
        color: urgent
            ? ParentPortalColors.pendingBg(context)
            : ParentPortalColors.surfaceMuted(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(ParentPortalSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: stripe, width: 3)),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth < _twoLineBelow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      wrappedBadges,
                      const SizedBox(height: ParentPortalSpacing.sm),
                      title(2),
                      const SizedBox(height: ParentPortalSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [date, chevron],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    badges,
                    const SizedBox(width: ParentPortalSpacing.md),
                    Expanded(child: title(1)),
                    const SizedBox(width: ParentPortalSpacing.sm),
                    date,
                    chevron,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
