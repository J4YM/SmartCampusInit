import 'dart:async';

import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/discipline_repository.dart';
import '../env.dart';

/// Wires the presentation-only [DisciplineOfficerDashboardPage] to Supabase
/// via [DisciplineRepository] — active violations, Good Moral requests, the
/// student directory, and summary metrics all come from real tables; Modify
/// and Validate/Deny persist back to `student_violations`.
///
/// Falls back to the page's own built-in mock data when Supabase isn't
/// configured (`AppEnv.supabaseConfigured` is false), so this still renders
/// something reasonable in that case rather than an empty/broken screen.
class DisciplineOfficerConnectedPage extends StatefulWidget {
  const DisciplineOfficerConnectedPage({
    super.key,
    this.onReturnToHub,
    this.onSignOut,
  });

  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;

  @override
  State<DisciplineOfficerConnectedPage> createState() =>
      _DisciplineOfficerConnectedPageState();
}

class _DisciplineOfficerConnectedPageState
    extends State<DisciplineOfficerConnectedPage> {
  bool _loading = true;
  String? _error;

  static const _studentDirectoryPageSize = 25;

  DisciplineSummaryMetricsModel? _metrics;
  List<DisciplineCaseModel>? _pendingQueue;
  List<GoodMoralRequestModel>? _goodMoralRequests;
  List<StudentDirectoryEntryModel>? _studentDirectory;
  int? _studentDirectoryTotalCount;
  List<OffenseOption>? _offenseOptions;

  RealtimeChannel? _violationsChannel;
  Timer? _reloadDebounce;

  DisciplineRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return DisciplineRepository(Supabase.instance.client);
  }

  /// [silent] skips the full-screen loading spinner — used for realtime-
  /// triggered reloads so a change elsewhere (e.g. a kiosk submission)
  /// refreshes the queue in place instead of flashing the whole dashboard
  /// back to a spinner.
  Future<void> _load({bool silent = false}) async {
    final repo = _repo;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final violations = await repo.fetchActiveViolations();
      final counts = await repo.fetchStatusCounts();
      final goodMoral = await repo.fetchGoodMoralRequests();
      final studentPage = await repo.fetchStudentDirectoryPage(
        page: 1,
        pageSize: _studentDirectoryPageSize,
      );
      final offenses = await repo.fetchOffenseOptions();

      if (!mounted) return;
      setState(() {
        _pendingQueue = violations;
        _metrics = DisciplineSummaryMetricsModel(
          pendingQueueCount: counts.activeTotal,
          escalatedCount: counts.escalatedActive,
          processedTodayCount: counts.resolvedToday,
          avgResponseTimeMinutes: counts.avgResolutionMinutes,
        );
        _goodMoralRequests = goodMoral;
        _studentDirectory = studentPage.items;
        _studentDirectoryTotalCount = studentPage.totalCount;
        _offenseOptions = offenses;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent) {
        // A transient background-refresh failure shouldn't kick the officer
        // out to the full error screen away from data they can already see.
        debugPrint('Could not silently refresh discipline data: $e');
      } else {
        setState(() => _error = 'Could not load discipline data: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<StudentDirectoryEntryModel>> _loadStudentDirectoryPage(int page) async {
    final repo = _repo;
    if (repo == null) return const [];
    final result = await repo.fetchStudentDirectoryPage(
      page: page,
      pageSize: _studentDirectoryPageSize,
    );
    if (mounted) setState(() => _studentDirectoryTotalCount = result.totalCount);
    return result.items;
  }

  Future<void> _resolveCase(String caseId) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.resolveViolation(caseId);
  }

  Future<void> _modifyCase(
    String caseId, {
    String? offenseId,
    bool? isEscalated,
    String? penaltyImposed,
  }) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.updateViolation(
      caseId,
      offenseId: offenseId,
      isEscalated: isEscalated,
      penaltyImposed: penaltyImposed,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _subscribeToViolationChanges();
  }

  /// Live-refreshes the Approval Queue when `student_violations` changes —
  /// e.g. a new violation submitted at the Virtual Admission Kiosk, or an
  /// edit from another Discipline Officer — without a manual page reload.
  /// Requires `student_violations` to be added to the `supabase_realtime`
  /// publication (see supabase/add_realtime_publication.sql).
  void _subscribeToViolationChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _violationsChannel = Supabase.instance.client
        .channel('public:student_violations')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'student_violations',
          callback: (_) => _scheduleReload(),
        )
        .subscribe();
  }

  /// Debounced so a burst of changes (e.g. the mock-data populate script,
  /// or several kiosk submissions in a row) triggers one reload, not one
  /// per row.
  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    final channel = _violationsChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
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
        ),
      );
    }

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final repo = _repo;
    return DisciplineOfficerDashboardPage(
      onReturnToHub: widget.onReturnToHub,
      onSignOut: widget.onSignOut,
      initialMetrics: _metrics,
      initialPendingQueue: _pendingQueue,
      initialGoodMoralRequests: _goodMoralRequests,
      initialStudentDirectory: _studentDirectory,
      studentDirectoryTotalCount: _studentDirectoryTotalCount,
      studentDirectoryPageSize: _studentDirectoryPageSize,
      onLoadStudentDirectoryPage: repo == null ? null : _loadStudentDirectoryPage,
      availableOffenses: _offenseOptions,
      onResolveCase: repo == null ? null : _resolveCase,
      onModifyCase: repo == null ? null : _modifyCase,
    );
  }
}
