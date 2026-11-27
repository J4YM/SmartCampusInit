/// One sanction as a parent sees it: what it was, when, and whether it
/// affects re-enrollment. Never the officer's internal override reason.
class SanctionHistoryEntry {
  const SanctionHistoryEntry({
    required this.id,
    required this.typeLabel,
    required this.description,
    required this.effectiveOn,
    required this.affectsEnrollment,
    this.endsOn,
    this.violationId,
    this.status = 'Pending',
  });

  final String id;

  /// e.g. "Suspension".
  final String typeLabel;
  final String description;
  final DateTime effectiveOn;

  /// Null for an open-ended sanction.
  final DateTime? endsOn;
  final bool affectsEnrollment;

  /// The violation this sanction closed (null for older callers).
  final String? violationId;

  /// 'Pending' | 'Serving' | 'Completed'.
  final String status;

  bool get isSuspension => typeLabel.toLowerCase() == 'suspension';

  /// A suspension that has not been completed yet.
  bool get isOngoingSuspension => isSuspension && status != 'Completed';
}
