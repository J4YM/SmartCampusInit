/// Where a request for a parent's availability stands, as the Discipline
/// Officer's Endorsements tab shows it. The host app maps its own round record
/// to this, since the package cannot see the app's data layer.
class AvailabilityRoundInfo {
  const AvailabilityRoundInfo({
    required this.roundId,
    required this.roundNo,
    required this.status,
    required this.requestedAt,
    this.offeredAt,
    this.meetingId,
  });

  final String roundId;

  /// 1 for the first ask; higher when the parent was asked again.
  final int roundNo;

  /// `Open`, `Offered`, `Approved`, `Declined` or `Cancelled`.
  final String status;
  final DateTime requestedAt;
  final DateTime? offeredAt;
  final String? meetingId;

  /// Waiting for the parent to offer times.
  bool get isOpen => status == 'Open';

  /// The parent offered times; Guidance picks one.
  bool get isOffered => status == 'Offered';
}

/// A failure whose message is already written for people ("no linked parent",
/// "already in progress"): the Endorsements tab shows it as is. Any other
/// error gets a generic message instead.
class EndorsementActionException implements Exception {
  const EndorsementActionException(this.message);
  final String message;

  @override
  String toString() => message;
}
