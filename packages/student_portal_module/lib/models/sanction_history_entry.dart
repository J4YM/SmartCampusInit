/// One sanction as a student sees it: what it was, when, and whether it
/// affects re-enrollment. Never the officer's internal override reason.
class SanctionHistoryEntry {
  const SanctionHistoryEntry({
    required this.id,
    required this.typeLabel,
    required this.description,
    required this.effectiveOn,
    required this.affectsEnrollment,
    this.endsOn,
  });

  final String id;

  /// e.g. "Suspension".
  final String typeLabel;
  final String description;
  final DateTime effectiveOn;

  /// Null for an open-ended sanction.
  final DateTime? endsOn;
  final bool affectsEnrollment;
}
