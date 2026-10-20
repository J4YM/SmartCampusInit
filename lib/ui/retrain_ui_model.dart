import 'package:dashboard_layout/dashboard_layout.dart'
    show RetrainStatusUiModel, RetrainUiState;

import '../data/ml_risk_repository.dart';

/// The Retrain card's view of the service's `/retrain/status`: state, whether
/// the new model replaced the live one, its headline metric, and how many
/// students it was trained and tested on (so a run on very little data is
/// visible, not just "Promoted").
RetrainStatusUiModel retrainUiModelFrom(RetrainStatusModel status) {
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
    challengerBestModelLabel:
        result == null ? null : titleCaseMlModelName(result.challengerBestModel),
    challengerRocAuc: result?.challengerMetrics['roc_auc'],
    trainingSamples: result?.nTrain,
    testSamples: result?.nTest,
    errorMessage: status.error,
  );
}
