/// Converts a raw "H:MM" time (the 12-hour clock every source format
/// uses, with no AM/PM marker) into 24-hour "HH:MM".
///
/// Verified against every sample schedule reviewed for this feature:
/// raw hour 12 is always noon, raw hours 1-6 are always PM (no class
/// starts 1-6 AM), and raw hours 7-11 are always AM (no class runs
/// 7-11 PM). Each endpoint of a range resolves independently — no
/// cross-referencing against its pair is needed.
String to24Hour(String raw) {
  final parts = raw.trim().split(':');
  final hour = int.parse(parts[0]);
  final minute = parts[1].padLeft(2, '0');
  final hour24 = hour == 12
      ? 12
      : (hour >= 1 && hour <= 6 ? hour + 12 : hour);
  return '${hour24.toString().padLeft(2, '0')}:$minute';
}

final _rangePattern = RegExp(r'(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})');

/// Extracts every "H:MM-H:MM" time range out of [cellText], converting
/// each endpoint to 24-hour time. A cell can hold more than one range
/// separated by "/" (two meeting blocks on the same day) — each becomes
/// its own entry, in the order they appear. A cell with no recognizable
/// range (blank, or a typo like "10:00:11:30" seen in real source data)
/// returns an empty list rather than throwing or guessing.
List<({String start, String end})> extractTimeRanges(String cellText) {
  return _rangePattern
      .allMatches(cellText)
      .map((m) => (start: to24Hour(m.group(1)!), end: to24Hour(m.group(2)!)))
      .toList();
}
