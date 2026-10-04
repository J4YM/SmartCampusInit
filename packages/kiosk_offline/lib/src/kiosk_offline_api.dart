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

/// What the kiosk UI talks to. Implemented on top of SQLite for desktop
/// ([openKioskOffline]); web gets `null` and keeps using Supabase directly.
abstract class KioskOffline {
  Future<OfflineStudent?> identifyStudent(String rfidUid);
  Future<OfflineStaff?> identifyStaff(String rfidCardId);
  Future<List<OfflineStudent>> searchStudents(String numberPrefix, {int limit = 8});
  Future<List<OfflineOffense>> offenses();
  Future<List<OfflineTeacher>> teachers();

  /// Throws [TapRejectedException] when a rule (local or server) refuses it.
  Future<TapOutcome> recordTap(String rfidUid);

  /// Sends now when online, otherwise queues. Throws `RemoteRejected` when
  /// the server refuses it.
  Future<void> submitSlip(SlipSubmission slip);

  Future<SyncStatus> currentStatus();
  Stream<SyncStatus> get status;
  Future<List<OutboxDiagnostic>> diagnostics();
  Future<void> dispose();
}
