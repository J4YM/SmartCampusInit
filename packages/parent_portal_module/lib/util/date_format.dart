const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Sep 6, 2026" — hand-rolled so this module doesn't need to add the
/// `intl` package as a new pubspec dependency.
String formatMonthDayYear(DateTime date) {
  return '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
}

const _monthNamesFull = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdayNamesFull = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "September 2026" — the Attendance History page's month-nav header.
String formatMonthYear(DateTime date) {
  return '${_monthNamesFull[date.month - 1]} ${date.year}';
}

/// "FRIDAY, SEPTEMBER 5" — the hero card's eyebrow date.
String formatFullWeekdayDate(DateTime date) {
  final weekday = _weekdayNamesFull[date.weekday - 1].toUpperCase();
  final month = _monthNamesFull[date.month - 1].toUpperCase();
  return '$weekday, $month ${date.day}';
}

/// "Good morning" / "Good afternoon" / "Good evening" — the hero card's
/// greeting word, based on the 24-hour clock.
String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// "3h ago" / "2d ago" / falls back to [formatMonthDayYear] past a week —
/// used by the notification feed.
String formatRelativeTime(DateTime timestamp) {
  final diff = DateTime.now().difference(timestamp);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatMonthDayYear(timestamp);
}
