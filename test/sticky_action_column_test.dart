import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A table's action column is pinned to the right edge of the viewport while
/// the table scrolls sideways, so its buttons are never scrolled out of sight
/// or clipped.
void main() {
  _equalPaddingTests();

  List<DashboardTableColumn> columns({required bool sticky}) => [
        const DashboardTableColumn('Name', flex: 3, minWidth: 220),
        const DashboardTableColumn('Department', flex: 3, minWidth: 220),
        DashboardTableColumn('Actions',
            flex: 1, minWidth: 130, sticky: sticky),
      ];

  Future<ScrollPosition> show(
    WidgetTester tester, {
    required double width,
    required bool sticky,
    List<int> taps = const [],
    void Function(int row)? onAction,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 700);
    addTearDown(tester.view.reset);
    final cols = columns(sticky: sticky);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DashboardTableHorizontalScroll(
            minWidth: dashboardTableMinWidth(cols),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DashboardTableHeader(columns: cols, topBorder: true),
                for (var i = 0; i < 3; i++)
                  DashboardTableRow(
                    columns: cols,
                    showDivider: i < 2,
                    onTap: () {},
                    cells: [
                      Text('Student number $i'),
                      Text('Department $i'),
                      TextButton(
                        key: Key('act-$i'),
                        onPressed: () => onAction?.call(i),
                        child: const Text('Edit'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final scrollables = find.byType(Scrollable).evaluate().where((e) {
      final s = e.widget as Scrollable;
      return s.axisDirection == AxisDirection.right;
    });
    return scrollables.isEmpty
        ? throw StateError('table is not scrolling sideways')
        : (tester.state<ScrollableState>(find.byWidget(scrollables.first.widget))
            .position);
  }

  double actionRight(WidgetTester tester, int row) =>
      tester.getRect(find.byKey(Key('act-$row'))).right;

  testWidgets('without sticky the action scrolls off a narrow table',
      (tester) async {
    await show(tester, width: 400, sticky: false);
    // The control: table is ~700 wide, so the button sits far past 400.
    expect(actionRight(tester, 0), greaterThan(400));
  });

  testWidgets('sticky: the action is on screen at the start of the scroll',
      (tester) async {
    await show(tester, width: 400, sticky: true);
    final right = actionRight(tester, 0);
    expect(right, lessThanOrEqualTo(400));
    expect(right, greaterThan(300), reason: 'at the right edge, not mid-table');
    // Every row's, and the header's, action sits at the same place.
    for (var i = 1; i < 3; i++) {
      expect(actionRight(tester, i), closeTo(right, 0.5));
    }
  });

  testWidgets('sticky: it stays put while the table scrolls sideways',
      (tester) async {
    final position = await show(tester, width: 400, sticky: true);
    final start = actionRight(tester, 0);
    final startHeader =
        tester.getRect(find.text('ACTIONS')).right; // header label

    for (final offset in [60.0, 150.0, position.maxScrollExtent]) {
      position.jumpTo(offset);
      await tester.pump();
      expect(actionRight(tester, 0), closeTo(start, 0.5),
          reason: 'row action at scroll $offset');
      expect(tester.getRect(find.text('ACTIONS')).right,
          closeTo(startHeader, 0.5),
          reason: 'header label at scroll $offset');
    }
    // And the other columns really do scroll beneath it.
    position.jumpTo(0);
    await tester.pump();
    final nameAtStart = tester.getRect(find.text('Student number 0')).left;
    position.jumpTo(150);
    await tester.pump();
    expect(tester.getRect(find.text('Student number 0')).left,
        closeTo(nameAtStart - 150, 0.5));
  });

  testWidgets('sticky: the pinned button is tappable wherever it is scrolled',
      (tester) async {
    final hits = <int>[];
    final position =
        await show(tester, width: 400, sticky: true, onAction: hits.add);

    await tester.tap(find.byKey(const Key('act-1')));
    expect(hits, [1]);

    position.jumpTo(120);
    await tester.pump();
    await tester.tap(find.byKey(const Key('act-2')));
    expect(hits, [1, 2]);
  });

  testWidgets('sticky: paints an opaque background over what scrolls beneath',
      (tester) async {
    final position = await show(tester, width: 400, sticky: true);
    position.jumpTo(position.maxScrollExtent - 40);
    await tester.pump();

    // A row's own fill is transparent at rest; the pinned layer's is not.
    final opaque = find.descendant(
      of: find.byType(DashboardTableRow).first,
      matching: find.byWidgetPredicate((w) =>
          w is AnimatedContainer &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color?.alpha == 255),
    );
    expect(opaque, findsOneWidget);
  });

  testWidgets('not sticky: no pinned layer is added', (tester) async {
    await show(tester, width: 400, sticky: false);
    final opaque = find.descendant(
      of: find.byType(DashboardTableRow).first,
      matching: find.byWidgetPredicate((w) =>
          w is AnimatedContainer &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color?.alpha == 255),
    );
    expect(opaque, findsNothing);
  });

  testWidgets('wide table: nothing scrolls and the action sits at the end',
      (tester) async {
    final cols = columns(sticky: true);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardTableHorizontalScroll(
          minWidth: dashboardTableMinWidth(cols),
          child: Column(
            children: [
              DashboardTableHeader(columns: cols),
              DashboardTableRow(columns: cols, cells: [
                const Text('Student'),
                const Text('Dept'),
                TextButton(
                    key: const Key('act-0'),
                    onPressed: () {},
                    child: const Text('Edit')),
              ]),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final sideways = find.byType(Scrollable).evaluate().where((e) =>
        (e.widget as Scrollable).axisDirection == AxisDirection.right);
    expect(sideways, isEmpty);
    expect(find.text('Edit'), findsOneWidget);
    expect(actionRight(tester, 0), lessThanOrEqualTo(1400));
  });

  testWidgets('a custom row can pin its end with DashboardTableStickyEnd',
      (tester) async {
    final cols = columns(sticky: false);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 700);
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardTableHorizontalScroll(
          minWidth: dashboardTableMinWidth(cols),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashboardTableStickyEnd(
                endWidth: 36,
                background: const Color(0x00000000),
                end: IconButton(
                  key: const Key('end'),
                  onPressed: () => taps++,
                  icon: const Icon(Icons.send),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
                  child: Row(children: const [
                    Expanded(child: Text('A violation')),
                    SizedBox(width: 36),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final end = tester.getRect(find.byKey(const Key('end')));
    expect(end.right, lessThanOrEqualTo(400));
    await tester.tap(find.byKey(const Key('end')));
    expect(taps, 1);
  });
}

/// The pinned column has the same padding either side of its content, however
/// much wider the column is than what it holds.
void _equalPaddingTests() {
  testWidgets('pinned action has equal space on its left and right',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 700);
    addTearDown(tester.view.reset);
    // Wider column than the single small icon it holds.
    const cols = [
      DashboardTableColumn('Name', flex: 3, minWidth: 220),
      DashboardTableColumn('Dept', flex: 3, minWidth: 220),
      DashboardTableColumn('Actions', flex: 1, minWidth: 150, sticky: true),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardTableHorizontalScroll(
          minWidth: dashboardTableMinWidth(cols),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashboardTableRow(columns: cols, cells: [
                const Text('A'),
                const Text('B'),
                SizedBox(
                  key: const Key('icons'),
                  width: 100,
                  height: 40,
                  child: const ColoredBox(color: Colors.red),
                ),
              ]),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The pinned layer is side padding + column + side padding wide, flush
    // with the viewport's right edge.
    const layerWidth = 28 + 150 + 28.0;
    final layerLeft = 400 - layerWidth;
    final r = tester.getRect(find.byKey(const Key('icons')));
    expect(r.left - layerLeft, closeTo(400 - r.right, 0.5));
  });
}
