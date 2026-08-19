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
/// wiring this mirrors.
///
/// Falls back to an empty model list (the page's own "no data" state) when
/// the ML service isn't configured (`AppEnv.mlApiConfigured` is false).
class MlThresholdsConnectedPage extends StatefulWidget {
  const MlThresholdsConnectedPage({super.key});

  @override
  State<MlThresholdsConnectedPage> createState() =>
      _MlThresholdsConnectedPageState();
}

class _MlThresholdsConnectedPageState
    extends State<MlThresholdsConnectedPage> {
  List<ModelMetricModel> _modelComparisons = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!AppEnv.mlApiConfigured) return;
    try {
      final info = await MlRiskRepository(AppEnv.mlApiBaseUrl).fetchModelInfo();
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

  @override
  Widget build(BuildContext context) {
    return MlThresholdsPage(
      thresholds: defaultRiskThresholds,
      modelComparisons: _modelComparisons,
    );
  }
}
