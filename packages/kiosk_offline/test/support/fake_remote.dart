import 'package:kiosk_offline/src/kiosk_remote.dart';
import 'package:kiosk_offline/src/models.dart';

class FakeRemote implements KioskRemote {
  final taps = <({String serial, String uid, DateTime at})>[];
  final slips = <SlipSubmission>[];
  Object? tapError;
  Object? slipError;
  Object? referenceError;
  ReferenceData? reference;
  bool pingResult = true;
  int referenceFetches = 0;
  String Function(String uid, DateTime at)? directionFor;
  String? Function(String uid)? studentIdFor;

  @override
  Future<RemoteTapResult> recordTap({
    required String readerUsbSerial,
    required String rfidUid,
    required DateTime tappedAt,
  }) async {
    final err = tapError;
    if (err != null) throw err;
    taps.add((serial: readerUsbSerial, uid: rfidUid, at: tappedAt));
    return RemoteTapResult(
      tapId: 'tap-${taps.length}',
      studentId: studentIdFor?.call(rfidUid),
      direction: directionFor?.call(rfidUid, tappedAt) ?? 'in',
      tappedAt: tappedAt,
    );
  }

  @override
  Future<void> submitSlip(SlipSubmission slip) async {
    final err = slipError;
    if (err != null) throw err;
    slips.add(slip);
  }

  @override
  Future<ReferenceData> fetchReferenceData() async {
    referenceFetches++;
    final err = referenceError;
    if (err != null) throw err;
    return reference ??
        const ReferenceData(students: [], staff: [], offenses: [], teachers: []);
  }

  /// Everything passed to [reportFailures], one entry per call.
  final reported = <({String serial, List<FailureReport> reports})>[];
  Object? reportError;
  Object? dismissedFetchError;
  Set<String> dismissedKeys = {};

  @override
  Future<void> reportFailures(
    String readerUsbSerial,
    List<FailureReport> reports,
  ) async {
    final err = reportError;
    if (err != null) throw err;
    reported.add((serial: readerUsbSerial, reports: reports));
  }

  @override
  Future<Set<String>> fetchDismissedFailureKeys(String readerUsbSerial) async {
    final err = dismissedFetchError;
    if (err != null) throw err;
    return dismissedKeys;
  }

  @override
  Future<bool> ping() async => pingResult;
}
