import 'package:capstone_dashboard/data/ml_risk_repository.dart';
import 'package:capstone_dashboard/ui/retrain_ui_model.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RetrainResultModel _result({
  bool promoted = true,
  int nTrain = 1200,
  int nTest = 300,
}) =>
    RetrainResultModel(
      timestampUtc: '2026-10-20T01:00:00Z',
      promoted: promoted,
      reason: 'challenger better',
      challengerBestModel: 'gradient_boosting',
      challengerMetrics: const {'roc_auc': 0.91},
      nTrain: nTrain,
      nTest: nTest,
    );

RetrainStatusModel _status(RetrainResultModel? r,
        {RetrainState state = RetrainState.completed}) =>
    RetrainStatusModel(
      state: state,
      startedAt: null,
      finishedAt: null,
      lastResult: r,
      error: null,
    );

Future<void> _pump(
  WidgetTester tester,
  RetrainStatusUiModel status, {
  VoidCallback? onRetrain,
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RetrainCard(
        status: status,
        retraining: false,
        onRetrain: onRetrain ?? () {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('retrainUiModelFrom', () {
    test('carries the sample sizes and result', () {
      final m = retrainUiModelFrom(_status(_result(nTrain: 80, nTest: 20)));
      expect(m.state, RetrainUiState.completed);
      expect(m.promoted, isTrue);
      expect(m.trainingSamples, 80);
      expect(m.testSamples, 20);
      expect(m.challengerRocAuc, 0.91);
      expect(m.challengerBestModelLabel, isNotNull);
    });

    test('no result yet means no sample sizes', () {
      final m = retrainUiModelFrom(_status(null, state: RetrainState.idle));
      expect(m.state, RetrainUiState.idle);
      expect(m.trainingSamples, isNull);
    });
  });

  group('small-sample caution', () {
    test('is flagged under the thresholds, not above', () {
      bool small(int train, int test) => RetrainStatusUiModel(
            state: RetrainUiState.completed,
            trainingSamples: train,
            testSamples: test,
          ).isSmallSample;
      expect(small(80, 20), isTrue);
      expect(small(kMinReliableTrainSamples - 1, 500), isTrue);
      expect(small(5000, kMinReliableTestSamples - 1), isTrue);
      expect(small(kMinReliableTrainSamples, kMinReliableTestSamples), isFalse);
      expect(small(5000, 1000), isFalse);
    });

    test('unknown sizes are not flagged', () {
      expect(const RetrainStatusUiModel(state: RetrainUiState.completed)
          .isSmallSample, isFalse);
    });
  });

  group('RetrainCard', () {
    testWidgets('shows how many students it was trained and tested on',
        (tester) async {
      await _pump(
        tester,
        retrainUiModelFrom(_status(_result(nTrain: 1200, nTest: 300))),
      );
      expect(find.text('Trained on 1,200 students · tested on 300'),
          findsOneWidget);
      expect(find.byKey(const Key('retrain-small-sample-warning')), findsNothing);
    });

    testWidgets('warns when a promoted model rests on very little data',
        (tester) async {
      await _pump(
        tester,
        retrainUiModelFrom(_status(_result(nTrain: 80, nTest: 20))),
      );
      expect(find.byKey(const Key('retrain-small-sample-warning')), findsOneWidget);
      expect(find.textContaining('replaced the live model'), findsOneWidget);
      expect(find.textContaining('only when students are analyzed again'),
          findsOneWidget);
    });

    testWidgets('a small run that was not promoted gets the milder note',
        (tester) async {
      await _pump(
        tester,
        retrainUiModelFrom(
            _status(_result(promoted: false, nTrain: 80, nTest: 20))),
      );
      expect(find.byKey(const Key('retrain-small-sample-warning')), findsOneWidget);
      expect(find.textContaining('replaced the live model'), findsNothing);
    });

    testWidgets('retraining asks first and explains the consequence',
        (tester) async {
      var runs = 0;
      await _pump(
        tester,
        const RetrainStatusUiModel(state: RetrainUiState.idle),
        onRetrain: () => runs++,
      );
      await tester.tap(find.text('Retrain Model Now').last);
      await tester.pumpAndSettle();
      expect(runs, 0);
      expect(find.textContaining('risk levels'), findsOneWidget);

      await tester.tap(find.byKey(const Key('retrain-cancel')));
      await tester.pumpAndSettle();
      expect(runs, 0);

      await tester.tap(find.text('Retrain Model Now').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('retrain-confirm')));
      await tester.pumpAndSettle();
      expect(runs, 1);
    });
  });
}
