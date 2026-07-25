import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/discipline_repository.dart';
import '../../env.dart';

/// Wires the presentation-only [SystemOverviewPage] (from `admin_dashboard`)
/// to Supabase via [DisciplineRepository].
///
/// Only the Discipline Alerts card and Violation Hotzone chart are backed by
/// real data today — both come straight from `student_violations` (see
/// `DisciplineRepository.fetchStatusCounts` / `fetchHotzoneByCategory`).
/// "Today's Active Scans", "High-Risk Students" (ML), and the Live RFID
/// Activity / Early Warning panels have no backing table yet (no RFID
/// gate-scan log, no ML predictions table exist in this schema), so they
/// stay at their empty/zero defaults rather than showing fabricated numbers.
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
  bool _loading = false;
  String? _error;

  static const _hotzoneColors = <Color>[
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
    Color(0xFF60A5FA),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
  ];

  DisciplineRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return DisciplineRepository(Supabase.instance.client);
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
      final maxCount = hotzones.isEmpty
          ? 1
          : hotzones.map((h) => h.count).reduce((a, b) => a > b ? a : b);

      if (!mounted) return;
      setState(() {
        _stats = OverviewStatsModel(
          activeScans: 0,
          activeScansTrend: 'No RFID scan log yet',
          pendingAlerts: counts.activeTotal,
          newAlerts: counts.pending,
          inReviewAlerts: counts.underInvestigation,
          resolvedAlerts: counts.resolved,
          highRiskCount: 0,
        );
        _hotzones = [
          for (var i = 0; i < hotzones.length; i++)
            ViolationHotzoneModel(
              categoryName: hotzones[i].displayLabel,
              percentageValue: hotzones[i].count / maxCount,
              barColor: _hotzoneColors[i % _hotzoneColors.length],
            ),
        ];
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load overview: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      rfidLogs: defaultRfidLogs,
      atRiskStudents: defaultAtRiskStudents,
    );
  }
}
