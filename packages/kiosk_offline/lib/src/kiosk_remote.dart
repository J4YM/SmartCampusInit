import 'models.dart';

/// The server refused this write for a business/permanent reason (rule
/// violation, unknown or deactivated reader, permission). Retrying will not
/// help. Anything else a [KioskRemote] throws is treated as transient.
class RemoteRejected implements Exception {
  RemoteRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

class RemoteTapResult {
  const RemoteTapResult({
    required this.tapId,
    required this.studentId,
    required this.direction,
    required this.tappedAt,
  });

  final String tapId;

  /// Null when the card matches no student (the tap is still logged).
  final String? studentId;

  /// `'in'` or `'out'`, as decided by the server.
  final String direction;
  final DateTime tappedAt;
}

/// Everything the kiosk needs from the server. Implemented in the root app
/// over Supabase; faked in tests.
abstract class KioskRemote {
  /// `record_rfid_tap` with the original [tappedAt].
  Future<RemoteTapResult> recordTap({
    required String readerUsbSerial,
    required String rfidUid,
    required DateTime tappedAt,
  });

  /// `submit_admission_slip`. A duplicate slip id must return normally.
  Future<void> submitSlip(SlipSubmission slip);

  Future<ReferenceData> fetchReferenceData();

  /// Reports rejected outbox items so IT Technician / Admin can review and
  /// dismiss them. Must be idempotent on [FailureReport.clientKey] (reporting
  /// an item twice is a no-op).
  Future<void> reportFailures(
    String readerUsbSerial,
    List<FailureReport> reports,
  );

  /// The `clientKey`s of this kiosk's reported failures that staff have since
  /// dismissed — the kiosk then drops its local copy so its status chip clears.
  Future<Set<String>> fetchDismissedFailureKeys(String readerUsbSerial);

  /// True when the server is reachable.
  Future<bool> ping();
}
