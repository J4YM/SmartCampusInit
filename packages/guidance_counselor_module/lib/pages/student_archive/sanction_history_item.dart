/// One sanction on a student's record, with the officer-only detail (basis and
/// override reason) that students and parents never see.
class SanctionHistoryItem {
  const SanctionHistoryItem({
    required this.id,
    required this.typeLabel,
    required this.description,
    required this.basisLabel,
    required this.effectiveOn,
    required this.affectsEnrollment,
    this.endsOn,
    this.overrideReason,
    this.status = 'Pending',
  });

  final String id;
  final String typeLabel;
  final String description;

  /// "Handbook" or "Custom".
  final String basisLabel;
  final DateTime effectiveOn;

  /// Null for an open-ended sanction.
  final DateTime? endsOn;
  final bool affectsEnrollment;
  final String? overrideReason;

  /// `Pending` | `Serving` | `Completed`.
  final String status;

  bool get isSuspension => typeLabel.toLowerCase() == 'suspension';

  /// A suspension that has not been completed.
  bool get isOngoingSuspension => isSuspension && status != 'Completed';
}
