import 'dart:async';

import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

import '../../data/ml_risk_repository.dart';
import '../../env.dart';

/// Wires the presentation-only [MlThresholdsPage] to the same deployed
/// dropout-risk ML service the Guidance Counselor's Overview tab already
/// reads (`GET /model-info`), so Admin sees the identical "Trained Model
/// Comparison" chart against the same real data instead of its own
/// disconnected mock. See [GuidanceCounselorConnectedPage] for the sibling
/// wiring this mirrors. Also owns the "Retrain Model Now" flow: triggers
/// `POST /retrain`, then polls `GET /retrain/status` every ~5s while a run
/// is in progress.
///
/// Falls back to an empty model list (the page's own "no data" state) when
/// the ML service isn't configured (`AppEnv.mlApiConfigured` is false).
/// Retrain itself needs the separate `AppEnv.mlRetrainConfigured` (the ML
/// service base URL *and* an API key) — this page is Admin-only already
/// (see `lib/modules/module_access.dart`'s `adminOverview` case, the only
/// route that builds this page), so no additional role gating is needed
/// here.
class MlThresholdsConnectedPage extends StatefulWidget {
  const MlThresholdsConnectedPage({super.key});

  @override
  State<MlThresholdsConnectedPage> createState() =>
      _MlThresholdsConnectedPageState();
}

class _MlThresholdsConnectedPageState
    extends State<MlThresholdsConnectedPage> {
  List<ModelMetricModel> _modelComparisons = const [];
  RetrainStatusUiModel? _retrainStatus;
  Timer? _retrainPollTimer;

  MlRiskRepository? get _repo {
    if (!AppEnv.mlApiConfigured) return null;
    return MlRiskRepository(
      AppEnv.mlApiBaseUrl,
      retrainApiKey: AppEnv.mlRetrainApiKey,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      if (AppEnv.mlRetrainConfigured) _loadRetrainStatus();
    });
  }

  @override
  void dispose() {
    _retrainPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final info = await repo.fetchModelInfo();
      if (!mounted) return;
      setState(() {
        _modelComparisons = [
          for (final entry in info.metrics.entries)
            ModelMetricModel(
              modelName: titleCaseMlModelName(entry.key),
              rocAuc: entry.value['roc_auc'] ?? 0,
              prAuc: entry.value['pr_auc'] ?? 0,
              recall: entry.value['recall'] ?? 0,
              f1: entry.value['f1'] ?? 0,
            ),
        ];
      });
    } catch (e) {
      debugPrint('Could not fetch ML model info: $e');
    }
  }

  RetrainStatusUiModel _toUiModel(RetrainStatusModel status) {
    final state = switch (status.state) {
      RetrainState.idle => RetrainUiState.idle,
      RetrainState.running => RetrainUiState.running,
      RetrainState.completed => RetrainUiState.completed,
      RetrainState.failed => RetrainUiState.failed,
    };
    final result = status.lastResult;
    return RetrainStatusUiModel(
      state: state,
      promoted: result?.promoted,
      challengerBestModelLabel: result == null
          ? null
          : titleCaseMlModelName(result.challengerBestModel),
      challengerRocAuc: result?.challengerMetrics['roc_auc'],
      errorMessage: status.error,
    );
  }

  Future<void> _loadRetrainStatus() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final status = await repo.fetchRetrainStatus();
      if (!mounted) return;
      setState(() => _retrainStatus = _toUiModel(status));
      if (status.state == RetrainState.running) {
        _schedulePoll();
      } else {
        _retrainPollTimer?.cancel();
      }
    } catch (e) {
      debugPrint('Could not fetch retrain status: $e');
    }
  }

  void _schedulePoll() {
    _retrainPollTimer?.cancel();
    _retrainPollTimer = Timer(const Duration(seconds: 5), _loadRetrainStatus);
  }

  Future<void> _triggerRetrain() async {
    final repo = _repo;
    if (repo == null) return;
    await repo.triggerRetrain();
    // The service runs training in the background (a 202 just means it
    // accepted the request) — start polling immediately rather than
    // waiting for the first 5s tick, so the "Running…" badge appears
    // right away instead of looking like nothing happened.
    await _loadRetrainStatus();
    // Reload the model comparison chart too, in case a previous run
    // already promoted a new champion since this page last loaded.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return MlThresholdsPage(
      thresholds: defaultRiskThresholds,
      modelComparisons: _modelComparisons,
      retrainStatus: _retrainStatus,
      onRetrain: AppEnv.mlRetrainConfigured ? _triggerRetrain : null,
    );
  }
}
