import 'dart:async';

import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/discipline_repository.dart';
import '../../env.dart';

/// Wires the presentation-only [SystemOverviewPage] (from `admin_dashboard`)
/// to Supabase via [DisciplineRepository].
///
/// Every card is backed by real data: Discipline Alerts and Violation
/// Hotzone from `student_violations` (unchanged); "Today's Active Scans"
/// and "Recent Attendance Activity" from `attendance_records`; "High-Risk
/// Students" and "Early Warning Triggers" from `risk_assessments` (both
/// tables existed already but were never queried here — the counters
/// silently sat at zero even with real rows present). The 7-day trend
/// sparklines/chart are computed client-side over `created_at`/
/// `session_date`, matching this repository's existing no-RPC style.
/// Realtime-subscribed (not just a one-shot load) so the whole page
/// actually earns its "live" framing.
class SystemOverviewConnectedPage extends StatefulWidget {
  const SystemOverviewConnectedPage({super.key});

  @override
  State<SystemOverviewConnectedPage> createState() =>
      _SystemOverviewConnectedPageState();
}

class _SystemOverviewConnectedPageState
    extends State<SystemOverviewConnectedPage> {
  OverviewStatsModel _stats = defaultOverviewStats;
  List<ViolationHotzoneModel> _hotzones = defaultViolationHotzones;
  List<RfidLogModel> _attendanceFeed = defaultRfidLogs;
  List<AtRiskStudentModel> _earlyWarning = defaultAtRiskStudents;
  bool _loading = false;
  String? _error;

  RealtimeChannel? _channel;
  Timer? _reloadDebounce;

  static const _hotzoneColors = <Color>[
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
    Color(0xFF60A5FA),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
  ];

  static const _avatarColors = <Color>[
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
  ];

  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  DisciplineRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return DisciplineRepository(Supabase.instance.client);
  }

  /// Normalizes a 7-day count series to 0–1 against its own peak, for the
  /// stat cards' corner sparklines. A flat all-zero week still renders as a
  /// flat line rather than dividing by zero.
  List<double> _normalize(List<DailyCount> series) {
    final maxCount =
        series.map((d) => d.count).fold(0, (a, b) => a > b ? a : b);
    if (maxCount == 0) return List.filled(series.length, 0.0);
    return [for (final d in series) d.count / maxCount];
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return '$first$last'.toUpperCase();
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final counts = await repo.fetchStatusCounts();
      final hotzones = await repo.fetchHotzoneByCategory();
      final dailyAttendance = await repo.fetchDailyAttendanceCounts();
      final dailyViolations = await repo.fetchDailyNewViolationCounts();
      final dailyHighRisk = await repo.fetchDailyHighRiskCounts();
      final highRiskCount = await repo.fetchHighRiskCount();
      final attendanceActivity = await repo.fetchRecentAttendanceActivity();
      final earlyWarning = await repo.fetchEarlyWarningStudents();

      final maxHotzone = hotzones.isEmpty
          ? 1
          : hotzones.map((h) => h.count).reduce((a, b) => a > b ? a : b);

      final today = dailyAttendance.isEmpty ? 0 : dailyAttendance.last.count;
      final yesterday = dailyAttendance.length < 2
          ? 0
          : dailyAttendance[dailyAttendance.length - 2].count;
      final String scansTrend;
      if (yesterday == 0) {
        scansTrend = today == 0 ? 'No scans yet today' : 'First scans today';
      } else {
        final change = ((today - yesterday) / yesterday * 100).round();
        scansTrend = change == 0
            ? 'Same as yesterday'
            : '${change > 0 ? '+' : ''}$change% vs yesterday';
      }

      if (!mounted) return;
      setState(() {
        _stats = OverviewStatsModel(
          activeScans: today,
          activeScansTrend: scansTrend,
          pendingAlerts: counts.activeTotal,
          newAlerts: counts.pending,
          inReviewAlerts: counts.underInvestigation,
          resolvedAlerts: counts.resolved,
          highRiskCount: highRiskCount,
          activeScansTrendPoints: _normalize(dailyAttendance),
          alertsTrendPoints: _normalize(dailyViolations),
          highRiskTrendPoints: _normalize(dailyHighRisk),
          weeklyAlerts: [
            for (final day in dailyViolations)
              DailyCountModel(
                label: _weekdayLabels[day.date.weekday - 1],
                count: day.count,
                isToday: _isToday(day.date),
              ),
          ],
        );
        _hotzones = [
          for (var i = 0; i < hotzones.length; i++)
            ViolationHotzoneModel(
              categoryName: hotzones[i].displayLabel,
              percentageValue: hotzones[i].count / maxHotzone,
              barColor: _hotzoneColors[i % _hotzoneColors.length],
            ),
        ];
        _attendanceFeed = [
          for (var i = 0; i < attendanceActivity.length; i++)
            RfidLogModel(
              id: '$i-${attendanceActivity[i].recordedAt.microsecondsSinceEpoch}',
              avatarInitials: _initials(attendanceActivity[i].studentName),
              studentName: attendanceActivity[i].studentName.isEmpty
                  ? 'Unknown student'
                  : attendanceActivity[i].studentName,
              studentId: attendanceActivity[i].studentNumber,
              // Both Present and Late are real check-ins (a scan happened);
              // Absent rows are excluded upstream since no scan occurred —
              // there's nothing this feed's "IN/OUT" badge could honestly
              // show for an absence.
              scanType: RfidScanType.inScan,
              location: attendanceActivity[i].sectionName,
              timestamp: attendanceActivity[i].recordedAt,
              avatarColor: _avatarColors[i % _avatarColors.length],
            ),
        ];
        _earlyWarning = [
          for (var i = 0; i < earlyWarning.length; i++)
            AtRiskStudentModel(
              avatarInitials: _initials(earlyWarning[i].studentName),
              name: earlyWarning[i].studentName.isEmpty
                  ? 'Unknown student'
                  : earlyWarning[i].studentName,
              courseYear: earlyWarning[i].sectionName,
              riskPercentage: earlyWarning[i].riskPercent,
              riskColor: earlyWarning[i].riskLevel == 'CRITICAL' ||
                      earlyWarning[i].riskLevel == 'HIGH'
                  ? const Color(0xFFDC2626)
                  : const Color(0xFFF59E0B),
              riskTags: earlyWarning[i].factors.isEmpty
                  ? const ['Early Warning']
                  : earlyWarning[i].factors,
              // Neither is tracked anywhere in this schema — honest
              // placeholders rather than fabricated-looking values.
              lastSeen: 'Not tracked',
              assignedCounselor: 'Unassigned',
              avatarColor: _avatarColors[i % _avatarColors.length],
            ),
        ];
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load overview: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// Live-refreshes the whole Overview page when any of the tables it reads
  /// from change — the page previously fetched once on load and never
  /// updated again despite claiming to show "real-time" data.
  void _subscribeToChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _channel = Supabase.instance.client
        .channel('public:system-overview')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'student_violations',
          callback: (_) => _scheduleReload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance_records',
          callback: (_) => _scheduleReload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'risk_assessments',
          callback: (_) => _scheduleReload(),
        )
        .subscribe();
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 500), _load);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _subscribeToChanges();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    final channel = _channel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_loading && identical(_stats, defaultOverviewStats)) {
      return const Center(child: CircularProgressIndicator());
    }

    return SystemOverviewPage(
      stats: _stats,
      hotzones: _hotzones.isEmpty ? defaultViolationHotzones : _hotzones,
      rfidLogs: _attendanceFeed,
      atRiskStudents: _earlyWarning,
    );
  }
}
