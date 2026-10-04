import 'models.dart';

/// A tap refused by a business rule — locally (offline rules) or by the
/// server. [message] is a complete, student-facing sentence.
class TapRejectedException implements Exception {
  TapRejectedException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TapOutcome {
  const TapOutcome({
    required this.direction,
    required this.studentId,
    required this.student,
  });

  /// `'in'` or `'out'`.
  final String direction;

  /// Set when the card belongs to a student the server (or cache) recognised.
  final String? studentId;

  /// Cached details, or null when the card is unrecognised or the student is
  /// not in the cache yet (even though [studentId] may be set).
  final OfflineStudent? student;
}
