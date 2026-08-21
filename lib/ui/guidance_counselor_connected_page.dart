import 'dart:async';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter/material.dart';
import 'package:guidance_counselor_module/pages/batch_student_analysis/batch_student_analysis_view.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';
import 'package:guidance_counselor_module/pages/single_student_analysis/single_student_analysis_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../data/guidance_counselor_repository.dart';
import '../data/ml_risk_repository.dart';
import '../data/notifications_repository.dart';
import '../env.dart';

/// Wires the presentation-only [GuidanceCounselorDashboard] to the standalone
/// dropout-risk ML service (Single/Batch Student Analysis) and to Supabase
/// (Overview tab metrics/queue, read from `risk_assessments` — see
/// `GuidanceCounselorRepository`).
///
/// Falls back to the page's own built-in mock/demo behavior when Supabase
/// and/or the ML service aren't configured, so this still renders something
/// reasonable rather than an empty/broken screen.
class GuidanceCounselorConnectedPage extends StatefulWidget {
  const GuidanceCounselorConnectedPage({
    super.key,
    this.counselorName,
    this.counselorProfileId,
    this.onReturnToHub,
    this.onSignOut,
  });

  final String? counselorName;

  /// The signed-in user's `profiles.id` — used to fetch/mark-read this
  /// counselor's own direct notifications (see [NotificationsRepository]),
  /// same role [ProfessorConnectedPage.professorProfileId] plays there.
  final String? counselorProfileId;
  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;

  @override
  State<GuidanceCounselorConnectedPage> createState() =>
      _GuidanceCounselorConnectedPageState();
}

class _GuidanceCounselorConnectedPageState
    extends State<GuidanceCounselorConnectedPage> {
  bool _loading = true;
  String? _error;

  GuidanceCounselorMetricsModel? _metrics;
  RiskDistributionModel? _riskDistribution;
  List<ModelMetricModel>? _modelComparisons;
  List<StudentRiskQueueItemModel>? _approvalQueue;
  List<NotificationItemModel>? _notifications;
  Map<String, String> _studentIdsByNumber = const {};

  RealtimeChannel? _notificationsChannel;
  Timer? _notificationsReloadDebounce;

  GuidanceCounselorRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return GuidanceCounselorRepository(Supabase.instance.client);
  }

  MlRiskRepository? get _mlRepo {
    if (!AppEnv.mlApiConfigured) return null;
    return MlRiskRepository(AppEnv.mlApiBaseUrl);
  }

  NotificationsRepository? get _notifRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return NotificationsRepository(Supabase.instance.client);
  }

  /// A real Supabase Auth id safe to filter `notifications.user_id` (a uuid
  /// column) by — `null` for the static demo accounts
  /// (lib/auth/static_demo_accounts.dart), whose ids like "u_counselor"
  /// aren't valid UUIDs and have no real `profiles` row to match anyway.
  String? get _notifiableUserId {
    final id = widget.counselorProfileId;
    if (id == null || id.startsWith('u_')) return null;
    return id;
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ids = await repo.fetchStudentIdsByNumber();
      final overview = await repo.fetchOverview();
      final modelComparisons = await _tryFetchModelComparisons();
      final notifications = await _notifRepo?.fetchForRole(
        AppRole.guidanceCounselor,
        userId: _notifiableUserId,
      );

      if (!mounted) return;
      setState(() {
        _studentIdsByNumber = ids;
        _metrics = overview.metrics;
        _riskDistribution = overview.riskDistribution;
        _approvalQueue = overview.approvalQueue;
        _modelComparisons = modelComparisons;
        if (notifications != null) _notifications = notifications;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not load guidance counselor data: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Non-fatal: the ML service being unreachable shouldn't block the rest
  /// of the Overview tab from loading — falls back to the dashboard's own
  /// demo model comparisons.
  Future<List<ModelMetricModel>?> _tryFetchModelComparisons() async {
    final ml = _mlRepo;
    if (ml == null) return null;
    try {
      final info = await ml.fetchModelInfo();
      return [
        for (final entry in info.metrics.entries)
          ModelMetricModel(
            modelName: titleCaseMlModelName(entry.key),
            rocAuc: entry.value['roc_auc'] ?? 0,
            prAuc: entry.value['pr_auc'] ?? 0,
            recall: entry.value['recall'] ?? 0,
            f1: entry.value['f1'] ?? 0,
          ),
      ];
    } catch (e) {
      debugPrint('Could not fetch ML model info: $e');
      return null;
    }
  }

  Future<void> _refreshOverview() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final overview = await repo.fetchOverview();
      if (!mounted) return;
      setState(() {
        _metrics = overview.metrics;
        _riskDistribution = overview.riskDistribution;
        _approvalQueue = overview.approvalQueue;
      });
    } catch (e) {
      debugPrint('Could not refresh guidance counselor overview: $e');
    }
  }

  Future<RiskAnalysisResultModel> _analyzeSingle(
    StudentRiskInputModel input,
  ) async {
    final result = await _mlRepo!.predictSingle(input);
    unawaited(_persistSingle(input.studentId, result));
    return result;
  }

  Future<void> _persistSingle(
    String studentNumber,
    RiskAnalysisResultModel result,
  ) async {
    final repo = _repo;
    final studentId = _studentIdsByNumber[studentNumber.trim()];
    if (repo == null || studentId == null) return;
    try {
      await repo.insertRiskAssessment(studentId: studentId, result: result);
      await _refreshOverview();
    } catch (e) {
      debugPrint('Could not persist risk assessment: $e');
    }
  }

  Future<List<BatchAnalysisResultModel>> _analyzeBatch(
    List<BatchStudentRecordModel> records,
  ) async {
    final results = await _mlRepo!.predictBatch(records);
    unawaited(_persistBatch(results));
    return results;
  }

  Future<void> _persistBatch(List<BatchAnalysisResultModel> results) async {
    final repo = _repo;
    if (repo == null) return;
    try {
      for (final result in results) {
        final studentId = _studentIdsByNumber[result.studentId.trim()];
        if (studentId == null) continue;
        await repo.insertBatchRiskAssessment(
          studentId: studentId,
          result: result,
        );
      }
      await _refreshOverview();
    } catch (e) {
      debugPrint('Could not persist batch risk assessments: $e');
    }
  }

  Future<void> _approveSlip(String assessmentId) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.markReviewed(assessmentId);
  }

  Future<void> _markNotificationsRead() async {
    final repo = _notifRepo;
    if (repo == null) return;
    await repo.markAllReadForRole(
      AppRole.guidanceCounselor,
      userId: _notifiableUserId,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _subscribeToNotificationChanges();
  }

  /// Live-refreshes the bell when a new notification lands for this
  /// dashboard. Requires `notifications` to be in the `supabase_realtime`
  /// publication (see supabase/add_notifications_schema.sql).
  void _subscribeToNotificationChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _notificationsChannel = Supabase.instance.client
        .channel('public:notifications:guidance_counselor')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) {
            _notificationsReloadDebounce?.cancel();
            _notificationsReloadDebounce =
                Timer(const Duration(milliseconds: 400), _reloadNotifications);
          },
        )
        .subscribe();
  }

  /// Refetches only the bell's notifications — deliberately not [_load],
  /// which would flash the whole Overview tab back to its loading spinner
  /// just because a notification arrived elsewhere.
  Future<void> _reloadNotifications() async {
    if (!mounted) return;
    final notifications = await _notifRepo?.fetchForRole(
      AppRole.guidanceCounselor,
      userId: _notifiableUserId,
    );
    if (!mounted || notifications == null) return;
    setState(() => _notifications = notifications);
  }

  @override
  void dispose() {
    _notificationsReloadDebounce?.cancel();
    final channel = _notificationsChannel;
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

    final ml = _mlRepo;
    return GuidanceCounselorDashboard(
      counselorName: widget.counselorName ?? 'Juan Dela Cruz',
      onReturnToHub: widget.onReturnToHub,
      onSignOut: widget.onSignOut,
      initialMetrics: _metrics,
      initialRiskDistribution: _riskDistribution,
      initialModelComparisons: _modelComparisons,
      initialApprovalQueue: _approvalQueue,
      onApproveSlip: _repo == null ? null : _approveSlip,
      onAnalyzeSingle: ml == null ? null : _analyzeSingle,
      onAnalyzeBatch: ml == null ? null : _analyzeBatch,
      initialNotifications: _notifications,
      onMarkNotificationsRead:
          _notifRepo == null ? null : _markNotificationsRead,
    );
  }
}
