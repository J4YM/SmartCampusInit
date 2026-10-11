import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_portal_module/widgets/section_header.dart' as parent;
import 'package:student_portal_module/widgets/section_header.dart' as student;

/// Every card's title is the same size: 18px on a desktop-width window, 16px
/// on a phone, semi-bold — whichever dashboard or portal the card is on. The
/// cards below were each a different size (14/16 bold on Admin, 15 bold on
/// the portals) before they shared `dashboardCardTitleStyle`.
void main() {
  Future<void> pump(WidgetTester tester, Widget child, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
    await tester.pumpAndSettle();
  }

  void expectTitle(WidgetTester tester, String text, double size) {
    // `.first`: the Retrain card's button repeats its title's words.
    final style = tester.widget<Text>(find.text(text).first).style!;
    expect(style.fontSize, size, reason: '"$text" font size');
    expect(style.fontWeight, FontWeight.w600, reason: '"$text" weight');
  }

  final cards = <String, Widget Function()>{
    'Retrain Model Now': () => RetrainCard(
          status: const RetrainStatusUiModel(state: RetrainUiState.idle),
          retraining: false,
          onRetrain: () {},
        ),
    'Trained Model Comparison': () => const ModelComparisonCard(models: [
          ModelMetricModel(
              modelName: 'xgboost', rocAuc: 0.9, prAuc: 0.8, recall: 0.7, f1: 0.6),
        ]),
    'Student portal card': () => const student.SectionHeader(title: 'Student portal card'),
    'Parent portal card': () => const parent.SectionHeader(title: 'Parent portal card'),
  };

  test('the shared style is 18 on desktop and 16 on a phone', () {
    expect(kCardTitleFontSizeDesktop, 18);
    expect(kCardTitleFontSizeMobile, 16);
  });

  for (final entry in cards.entries) {
    testWidgets('${entry.key}: desktop title is the shared size',
        (tester) async {
      await pump(tester, entry.value(), 1400);
      expectTitle(tester, entry.key, kCardTitleFontSizeDesktop);
    });

    testWidgets('${entry.key}: phone title is the shared size', (tester) async {
      await pump(tester, entry.value(), 380);
      expectTitle(tester, entry.key, kCardTitleFontSizeMobile);
    });
  }
}
