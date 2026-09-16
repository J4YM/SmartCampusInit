import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Container decorationOf(WidgetTester tester) => tester.widget<Container>(
        find.descendant(
          of: find.byType(BentoCard),
          matching: find.byType(Container),
        ),
      );

  testWidgets('elevated (default) card has a 20px radius and a drop shadow',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BentoCard(
          backgroundColor: Colors.white,
          borderColor: Colors.black12,
          child: Text('content'),
        ),
      ),
    ));

    final decoration = decorationOf(tester).decoration as BoxDecoration;
    expect((decoration.borderRadius as BorderRadius).topLeft,
        const Radius.circular(20));
    expect(decoration.boxShadow, isNotNull);
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets(
      'non-elevated card (nested sub-card) has no shadow and honors a custom radius',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BentoCard(
          backgroundColor: Colors.white,
          borderColor: Colors.black12,
          borderRadius: 14,
          elevated: false,
          child: const Text('content'),
        ),
      ),
    ));

    final decoration = decorationOf(tester).decoration as BoxDecoration;
    expect((decoration.borderRadius as BorderRadius).topLeft,
        const Radius.circular(14));
    expect(decoration.boxShadow, isNull);
  });

  testWidgets('shadow opacity is 0.04 in light mode', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(
        body: BentoCard(
          backgroundColor: Colors.white,
          borderColor: Colors.black12,
          child: const Text('content'),
        ),
      ),
    ));
    final decoration = decorationOf(tester).decoration as BoxDecoration;
    expect(decoration.boxShadow!.single.color.opacity, closeTo(0.04, 0.005));
  });

  testWidgets('shadow opacity is 0.25 in dark mode (stronger, for contrast)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: BentoCard(
          backgroundColor: Colors.white,
          borderColor: Colors.black12,
          child: const Text('content'),
        ),
      ),
    ));
    final decoration = decorationOf(tester).decoration as BoxDecoration;
    expect(decoration.boxShadow!.single.color.opacity, closeTo(0.25, 0.005));
  });
}
