/// One time a parent offered (`public.meeting_availability_slots`).
class AvailabilitySlot {
  const AvailabilitySlot({
    required this.id,
    required this.slotAt,
    required this.status,
  });

  final String id;
  final DateTime slotAt;

  /// `Offered`, `Approved`, `Declined` or `Not_Chosen`.
  final String status;

  factory AvailabilitySlot.fromJson(Map<String, dynamic> json) =>
      AvailabilitySlot(
        id: json['id'] as String,
        slotAt: DateTime.parse(json['slot_at'] as String).toLocal(),
        status: json['status'] as String? ?? 'Offered',
      );
}

/// A request for a parent's availability for an endorsement meeting
/// (`public.meeting_availability_rounds`, supabase/add_parent_availability_scheduling.sql).
class ParentAvailabilityRound {
  const ParentAvailabilityRound({
    required this.id,
    required this.escalationReportId,
    required this.studentId,
    required this.roundNo,
    required this.status,
    required this.requestedAt,
    required this.slots,
    this.offeredAt,
    this.meetingId,
  });

  final String id;
  final String escalationReportId;
  final String studentId;
  final int roundNo;

  /// `Open`, `Offered`, `Approved`, `Declined` or `Cancelled`.
  final String status;
  final DateTime requestedAt;
  final DateTime? offeredAt;
  final String? meetingId;
  final List<AvailabilitySlot> slots;

  /// Parses a round row; nested slots come from the
  /// `meeting_availability_slots` embed, earliest first.
  factory ParentAvailabilityRound.fromJson(Map<String, dynamic> json) {
    final slots = [
      for (final s
          in (json['meeting_availability_slots'] as List<dynamic>? ?? const []))
        AvailabilitySlot.fromJson(s as Map<String, dynamic>),
    ]..sort((a, b) => a.slotAt.compareTo(b.slotAt));
    final offeredAt = json['offered_at'] as String?;
    return ParentAvailabilityRound(
      id: json['id'] as String,
      escalationReportId: json['escalation_report_id'] as String,
      studentId: json['student_id'] as String,
      roundNo: (json['round_no'] as num?)?.toInt() ?? 1,
      status: json['status'] as String? ?? 'Open',
      requestedAt: DateTime.parse(json['requested_at'] as String).toLocal(),
      offeredAt: offeredAt == null ? null : DateTime.parse(offeredAt).toLocal(),
      meetingId: json['meeting_id'] as String?,
      slots: slots,
    );
  }
}
