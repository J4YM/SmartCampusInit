/// Display order of the behavior categories (`handbook_offenses
/// .behavior_category`) in every offense picker.
const kBehaviorCategoryOrder = <String>[
  'Academic_Integrity',
  'Attendance_Tardiness',
  'Uniform_Dress_Code',
  'Property_Damage',
  'Disruptive_Conduct',
  'Digital_Device_Policy',
  'Other',
];

const _headings = {
  'Academic_Integrity': 'Academic Integrity',
  'Attendance_Tardiness': 'Attendance / Tardiness',
  'Uniform_Dress_Code': 'Uniform / Dress Code',
  'Property_Damage': 'Property / Facility Damage',
  'Disruptive_Conduct': 'Behavioral / Disruptive Conduct',
  'Digital_Device_Policy': 'Digital / Device Policy',
  'Other': 'Other',
};

/// The heading for a behavior category value; unknown or missing values read
/// "Other".
String behaviorCategoryHeading(String? value) =>
    _headings[value] ?? _headings['Other']!;

/// "Minor", "Major A".."Major D" from `handbook_offenses.category`; empty when
/// unknown.
String severityDisplay(String? category) {
  if (category == null || category.isEmpty) return '';
  return category.replaceAll('_', ' ');
}

/// Minor first, then Major A to D; anything else after.
int _severityRank(String? category) {
  final c = (category ?? '').toLowerCase();
  if (c.startsWith('minor')) return 0;
  if (c.startsWith('major')) {
    final letter = c.replaceAll(RegExp(r'[^a-z]'), '').replaceFirst('major', '');
    return letter.isEmpty ? 1 : 1 + (letter.codeUnitAt(0) - 'a'.codeUnitAt(0)) + 1;
  }
  return 9;
}

/// One heading of an offense picker and the offenses under it.
class OffenseGroup<T> {
  OffenseGroup(this.heading, this.items);
  final String heading;
  final List<T> items;
}

/// Organizes offenses for a picker: grouped by behavior category (in
/// [kBehaviorCategoryOrder]), and inside a group Minor first, then Major A to
/// D, then alphabetically. Offenses with no category go under "Other".
///
/// When no offense has a behavior category (the database migration has not
/// been run), it falls back to the old severity groups (Minor, Major_A, ...)
/// so the picker never collapses into one long "Other" list.
List<OffenseGroup<T>> groupOffensesByBehavior<T>(
  Iterable<T> items, {
  required String? Function(T) behavior,
  required String? Function(T) severity,
  required String Function(T) label,
}) {
  final list = items.toList();
  if (list.isEmpty) return const [];

  int bySeverityThenLabel(T a, T b) {
    final bySeverity = _severityRank(severity(a)).compareTo(_severityRank(severity(b)));
    return bySeverity != 0
        ? bySeverity
        : label(a).toLowerCase().compareTo(label(b).toLowerCase());
  }

  final anyCategorized = list.any((o) {
    final b = behavior(o);
    return b != null && b.isNotEmpty;
  });

  if (!anyCategorized) {
    final byGroup = <String, List<T>>{};
    for (final o in list) {
      final s = severity(o);
      final key = (s == null || s.isEmpty) ? 'Other' : s;
      byGroup.putIfAbsent(key, () => []).add(o);
    }
    final keys = byGroup.keys.toList()
      ..sort((a, b) {
        final byRank = _severityRank(a).compareTo(_severityRank(b));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    return [
      for (final k in keys) OffenseGroup(k, byGroup[k]!..sort(bySeverityThenLabel)),
    ];
  }

  final byCategory = <String, List<T>>{};
  for (final o in list) {
    final b = behavior(o);
    final key = kBehaviorCategoryOrder.contains(b) ? b! : 'Other';
    byCategory.putIfAbsent(key, () => []).add(o);
  }
  return [
    for (final key in kBehaviorCategoryOrder)
      if (byCategory.containsKey(key))
        OffenseGroup(behaviorCategoryHeading(key),
            byCategory[key]!..sort(bySeverityThenLabel)),
  ];
}
