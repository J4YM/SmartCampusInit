import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A row with its own state, so a test can tell "kept in place" from
/// "rebuilt from scratch".
class _Row extends StatefulWidget {
  const _Row(this.id, {super.key});
  final String id;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 60, child: Text('row ${widget.id}'));
}

Widget _host(List<String> ids, {Widget? empty, int max = 6}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DashboardTableRows(
          maxAnimatedArrivals: max,
          empty: empty,
          rows: [for (final id in ids) _Row(id, key: ValueKey(id))],
        ),
      ),
    ),
  );
}

double _rowTop(WidgetTester tester, String id) =>
    tester.getTopLeft(find.text('row $id')).dy;

void main() {
  testWidgets('first paint shows every row at once, no animation',
      (tester) async {
    await tester.pumpWidget(_host(['a', 'b', 'c']));
    expect(tester.getSize(find.byType(DashboardTableRows)).height, 180);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a new row stacks in at the top and pushes the rest down',
      (tester) async {
    await tester.pumpWidget(_host(['a', 'b']));
    final topBefore = _rowTop(tester, 'a');
    final stateA = tester.state(find.byKey(const ValueKey('a')));

    await tester.pumpWidget(_host(['new', 'a', 'b']));
    // Just arrived: takes no room yet.
    expect(tester.getSize(find.byType(DashboardTableRows)).height, 120);
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pump(const Duration(milliseconds: 150));
    final mid = tester.getSize(find.byType(DashboardTableRows)).height;
    expect(mid, greaterThan(120));
    expect(mid, lessThan(180));
    expect(_rowTop(tester, 'a'), greaterThan(topBefore));

    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DashboardTableRows)).height, 180);
    expect(_rowTop(tester, 'a'), topBefore + 60);
    // The rows that were already there were never rebuilt.
    expect(tester.state(find.byKey(const ValueKey('a'))), same(stateA));
  });

  testWidgets('a row that finishes animating keeps its state', (tester) async {
    await tester.pumpWidget(_host(['a']));
    await tester.pumpWidget(_host(['new', 'a']));
    final stateNew = tester.state(find.byKey(const ValueKey('new')));
    await tester.pumpAndSettle();
    expect(tester.state(find.byKey(const ValueKey('new'))), same(stateNew));
  });

  testWidgets('a whole-page swap (pagination) does not animate',
      (tester) async {
    await tester.pumpWidget(_host(['a', 'b', 'c']));
    await tester.pumpWidget(_host(['x', 'y', 'z']));
    expect(tester.getSize(find.byType(DashboardTableRows)).height, 180);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('more arrivals than the cap is a reload and does not animate',
      (tester) async {
    await tester.pumpWidget(_host(['a'], max: 2));
    await tester.pumpWidget(_host(['a', 'b', 'c', 'd'], max: 2));
    expect(tester.getSize(find.byType(DashboardTableRows)).height, 240);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the first row into an empty table animates in', (tester) async {
    await tester.pumpWidget(_host([], empty: const Text('nothing here')));
    expect(find.text('nothing here'), findsOneWidget);

    await tester.pumpWidget(_host(['a'], empty: const Text('nothing here')));
    expect(find.text('nothing here'), findsNothing);
    expect(tester.getSize(find.byType(DashboardTableRows)).height, 0);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DashboardTableRows)).height, 60);
  });

  testWidgets('a burst stacks in one after another', (tester) async {
    await tester.pumpWidget(_host(['a']));
    await tester.pumpWidget(_host(['n1', 'n2', 'n3', 'a']));
    await tester.pump(const Duration(milliseconds: 120));
    // n1 is well on its way, n3 has barely started.
    double boxHeight(String id) => tester
        .getSize(find
            .ancestor(
              of: find.byKey(ValueKey(id)),
              matching: find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_RevealBox'),
            )
            .first)
        .height;
    final h1 = boxHeight('n1');
    final h3 = boxHeight('n3');
    expect(h1, greaterThan(h3));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DashboardTableRows)).height, 240);
  });

  testWidgets('a duplicate key does not crash', (tester) async {
    await tester.pumpWidget(_host(['a', 'a']));
    await tester.pumpWidget(_host(['a', 'a', 'b']));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('row a'), findsNWidgets(2));
  });

  testWidgets('reduced motion skips the animation', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_host(['a']));
    await tester.pumpWidget(_host(['new', 'a']));
    expect(tester.getSize(find.byType(DashboardTableRows)).height, 120);
  });
}
