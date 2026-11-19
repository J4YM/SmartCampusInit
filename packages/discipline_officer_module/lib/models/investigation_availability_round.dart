/// One time a parent offered for an investigation meeting.
class OfferedTime {
  const OfferedTime({required this.id, required this.at});

  final String id;
  final DateTime at;
}

/// Where the request for a parent's availability stands for one investigation,
/// as the Investigations tab shows it. The host app maps its own round record
/// to this (the package cannot see the data layer).
class InvestigationAvailabilityRound {
  const InvestigationAvailabilityRound({
    required this.roundId,
    required this.roundNo,
    required this.status,
    required this.requestedAt,
    this.offeredTimes = const [],
  });

  final String roundId;

  /// 1 for the first ask; higher when the parent was asked again.
  final int roundNo;

  /// `Open`, `Offered`, `Approved`, `Declined` or `Cancelled`.
  final String status;
  final DateTime requestedAt;

  /// The times the parent offered, earliest first; empty until they answer.
  final List<OfferedTime> offeredTimes;

  /// Waiting for the parent to offer times.
  bool get isOpen => status == 'Open';

  /// The parent offered times; the officer picks one.
  bool get isOffered => status == 'Offered';

  /// A request is in progress (the officer cannot start another).
  bool get isLive => isOpen || isOffered;
}
