/// An open request from Guidance for the parent's available times, reduced to
/// what the portal card shows (the host maps its own round model to this).
class AvailabilityRequest {
  const AvailabilityRequest({
    required this.roundId,
    required this.roundNo,
    this.studentName,
  });

  final String roundId;

  /// 1 for the first ask; higher when Guidance could not make earlier times.
  final int roundNo;
  final String? studentName;
}
