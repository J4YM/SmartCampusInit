import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter_test/flutter_test.dart';

class _O {
  const _O(this.label, this.severity, [this.behavior]);
  final String label;
  final String? severity;
  final String? behavior;
}

List<OffenseGroup<_O>> _group(List<_O> items) => groupOffensesByBehavior<_O>(
      items,
      behavior: (o) => o.behavior,
      severity: (o) => o.severity,
      label: (o) => o.label,
    );

void main() {
  test('groups by behavior category in the standard order', () {
    final groups = _group(const [
      _O('Phone in class', 'Minor', 'Digital_Device_Policy'),
      _O('Cheating', 'Major_A', 'Academic_Integrity'),
      _O('Late', 'Minor', 'Attendance_Tardiness'),
    ]);
    expect(groups.map((g) => g.heading),
        ['Academic Integrity', 'Attendance / Tardiness', 'Digital / Device Policy']);
  });

  test('inside a group: Minor first, then Major A to D, then by name', () {
    final groups = _group(const [
      _O('Zeta', 'Major_B', 'Academic_Integrity'),
      _O('Beta', 'Minor', 'Academic_Integrity'),
      _O('Alpha', 'Minor', 'Academic_Integrity'),
      _O('Gamma', 'Major_A', 'Academic_Integrity'),
    ]);
    expect(groups.single.items.map((o) => o.label),
        ['Alpha', 'Beta', 'Gamma', 'Zeta']);
  });

  test('uncategorized offenses go under Other, last', () {
    final groups = _group(const [
      _O('Mystery', 'Minor'),
      _O('Cheating', 'Major_A', 'Academic_Integrity'),
      _O('Odd', 'Minor', 'Other'),
    ]);
    expect(groups.map((g) => g.heading), ['Academic Integrity', 'Other']);
    expect(groups.last.items.map((o) => o.label), ['Mystery', 'Odd']);
  });

  test('with no behavior categories at all it falls back to severity groups',
      () {
    final groups = _group(const [
      _O('Late', 'Minor'),
      _O('Fight', 'Major_B'),
      _O('Cheating', 'Major_A'),
      _O('Phone', 'Minor'),
    ]);
    expect(groups.map((g) => g.heading), ['Minor', 'Major_A', 'Major_B']);
    expect(groups.first.items.map((o) => o.label), ['Late', 'Phone']);
  });

  test('empty input gives no groups', () {
    expect(_group(const []), isEmpty);
  });

  test('severityDisplay is readable', () {
    expect(severityDisplay('Minor'), 'Minor');
    expect(severityDisplay('Major_C'), 'Major C');
    expect(severityDisplay(null), '');
  });

  test('behaviorCategoryHeading names every category', () {
    expect(behaviorCategoryHeading('Uniform_Dress_Code'), 'Uniform / Dress Code');
    expect(behaviorCategoryHeading('Property_Damage'), 'Property / Facility Damage');
    expect(behaviorCategoryHeading('Disruptive_Conduct'),
        'Behavioral / Disruptive Conduct');
    expect(behaviorCategoryHeading(null), 'Other');
    expect(behaviorCategoryHeading('Nonsense'), 'Other');
  });
}
