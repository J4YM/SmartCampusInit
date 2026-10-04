/// The one place the app turns a time of day into text: always the 12-hour
/// clock with an AM/PM marker ("3:05 PM"), never 24-hour ("15:05"). Every
/// dashboard's timestamps, schedule times and live clocks go through these,
/// so the format can't drift from one screen to the next.
library;

String _two(int n) => n.toString().padLeft(2, '0');

/// "3:05 PM" — or "3:05:09 PM" with [seconds]. Midnight is "12:00 AM", noon
/// "12:00 PM".
String formatTime12h(DateTime time, {bool seconds = false}) {
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final period = time.hour < 12 ? 'AM' : 'PM';
  final tail = seconds ? ':${_two(time.second)}' : '';
  return '$hour12:${_two(time.minute)}$tail $period';
}

/// "2026-10-04 3:05 PM" — a numeric date, then the 12-hour time.
String formatDateTime12h(DateTime time, {bool seconds = false}) =>
    '${time.year}-${_two(time.month)}-${_two(time.day)} '
    '${formatTime12h(time, seconds: seconds)}';

/// Turns a stored time-of-day string — Postgres `time` ("13:30", "13:30:00")
/// — into "1:30 PM". Anything it can't read as 24-hour (already "1:30 PM",
/// blank, free text) is returned untouched rather than mangled.
String formatClock12h(String raw) {
  final text = raw.trim();
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$').firstMatch(text);
  if (match == null) return raw;
  final hour = int.parse(match.group(1)!);
  final minute = match.group(2)!;
  if (hour > 23) return raw;
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12:$minute ${hour < 12 ? 'AM' : 'PM'}';
}

/// "08:00" + "09:30" -> "8:00 AM - 9:30 AM".
String formatClockRange12h(String start, String end) =>
    '${formatClock12h(start)} - ${formatClock12h(end)}';
