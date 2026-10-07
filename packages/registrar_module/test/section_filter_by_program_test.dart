import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Section lists (the Filter popup's Section facet, Change Section, ...) group
/// by program — BSIT: 1st-4th year, BSBA: 1st-4th year — not by year.
void main() {
  final entries = [
    PickerEntry.section(id: 'a', name: 'BSIT-3B'),
    PickerEntry.section(id: 'b', name: 'BSBA-2A'),
    PickerEntry.section(id: 'c', name: 'BSIT-1A'),
    PickerEntry.section(id: 'd', name: 'BSHM 1A'),
    PickerEntry.section(id: 'e', name: 'BSIT-4C'),
    PickerEntry.section(id: 'f', name: 'BSBA-4A'),
    PickerEntry.section(id: 'g', name: 'BSIT-2A'),
  ];

  const palette = PickerPalette(
    surface: Colors.white,
    field: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    text: Color(0xFF1E293B),
    muted: Color(0xFF64748B),
    placeholder: Color(0xFF94A3B8),
  );

  test('sections sort by program, then year, then name', () {
    final sorted = [...entries]..sort(comparePickerEntries);
    expect(sorted.map((e) => e.title), [
      'BSIT-1A', 'BSIT-2A', 'BSIT-3B', 'BSIT-4C', // BSIT, 1st-4th
      'BSHM 1A', //                                  then BSHM
      'BSBA-2A', 'BSBA-4A', //                       then BSBA
    ]);
  });

  test('a row says its year (the program is the heading); a professor follows',
      () {
    expect(PickerEntry.section(id: 'x', name: 'BSIT-3B').subtitle, '3rd Year');
    expect(
      PickerEntry.section(id: 'x', name: 'BSIT-3B', subtitle: 'Prof. Reyes')
          .subtitle,
      '3rd Year · Prof. Reyes',
    );
    // No year in the name: the explicit subtitle is all there is.
    expect(
      PickerEntry.section(id: 'x', name: 'Irregular', subtitle: 'Prof. Reyes')
          .subtitle,
      'Prof. Reyes',
    );
  });

  test('an unknown program is its own group, after the known ones', () {
    final list = [
      PickerEntry.section(id: '1', name: 'BSCpE-2A'),
      PickerEntry.section(id: '2', name: 'BSIT-1A'),
      PickerEntry.section(id: '3', name: 'BSCpE-1A'),
    ]..sort(comparePickerEntries);
    expect(list.map((e) => e.title), ['BSIT-1A', 'BSCpE-1A', 'BSCpE-2A']);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
    tester.takeException();
  }

  // The headings, top to bottom.
  List<String> headings(WidgetTester tester) {
    final bands = find.byType(FilterLabelBand).evaluate().toList()
      ..sort((a, b) => tester
          .getTopLeft(find.byWidget(a.widget))
          .dy
          .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy));
    return [for (final b in bands) (b.widget as FilterLabelBand).label];
  }

  testWidgets('the picker has one heading per program, years inside it',
      (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 1200,
        child: SearchablePickerList(
          entries: entries,
          palette: palette,
          groupByProgram: true,
          scrollable: false,
          onSelected: (_) {},
        ),
      ),
    );

    expect(headings(tester), [
      'BS Information Technology',
      'BS Hospitality Management',
      'BS Business Administration',
    ]);
    // No "1st Year" / "2nd Year" headings any more.
    expect(
      headings(tester).where((h) => h.endsWith('Year')),
      isEmpty,
    );
    // Within BSIT, the rows run 1st year to 4th, all above the BSHM heading.
    double top(String title) => tester.getTopLeft(find.text(title)).dy;
    expect(top('BSIT-1A'), lessThan(top('BSIT-2A')));
    expect(top('BSIT-2A'), lessThan(top('BSIT-3B')));
    expect(top('BSIT-3B'), lessThan(top('BSIT-4C')));
    expect(top('BSIT-4C'), lessThan(top('BSHM 1A')));
    expect(top('BSHM 1A'), lessThan(top('BSBA-2A')));
    expect(top('BSBA-2A'), lessThan(top('BSBA-4A')));
    // The count at each heading is that program's sections.
    expect(find.text('4 sections'), findsOneWidget); // BSIT
    expect(find.text('2 sections'), findsOneWidget); // BSBA
    expect(find.text('1 section'), findsOneWidget); // BSHM
  });

  testWidgets('searching keeps the grouping', (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 1200,
        child: SearchablePickerList(
          entries: entries,
          palette: palette,
          groupByProgram: true,
          scrollable: false,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'bsba');
    await tester.pumpAndSettle();
    expect(headings(tester), ['BS Business Administration']);
    await tester.enterText(find.byType(TextField), '1st');
    await tester.pumpAndSettle();
    // 1st-year sections across programs, still one heading per program.
    expect(headings(tester),
        ['BS Information Technology', 'BS Hospitality Management']);
  });

  testWidgets('the Filter popup groups its Section facet per program',
      (tester) async {
    String? picked = 'unset';
    await pump(
      tester,
      Center(
        child: FilterMenuButton(
          backgroundColor: palette.field,
          menuColor: palette.surface,
          borderColor: palette.border,
          iconColor: palette.text,
          textColor: palette.text,
          mutedTextColor: palette.muted,
          accentColor: palette.accent,
          sectionFilter: FilterSectionPicker(
            entries: [
              PickerEntry.section(id: 'BSIT-1A', name: 'BSIT-1A'),
              PickerEntry.section(id: 'BSIT-4C', name: 'BSIT-4C'),
              PickerEntry.section(id: 'BSHM 1A', name: 'BSHM 1A'),
              PickerEntry.section(id: 'BSBA-2A', name: 'BSBA-2A'),
            ],
            selectedId: null,
            onChanged: (id) => picked = id,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FilterMenuButton));
    await tester.pumpAndSettle();

    expect(headings(tester), [
      'BS Information Technology',
      'BS Hospitality Management',
      'BS Business Administration',
    ]);
    double top(String title) => tester.getTopLeft(find.text(title)).dy;
    expect(top('BSIT-1A'), lessThan(top('BSIT-4C')));
    expect(top('BSIT-4C'), lessThan(top('BSHM 1A')));

    await tester.tap(find.text('BSBA-2A'));
    await tester.pumpAndSettle();
    expect(picked, 'BSBA-2A');
  });
}
