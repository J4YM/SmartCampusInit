// packages/student_portal_module/lib/models/good_moral_request_status.dart

/// One of the requester's own Good Moral (or other document) requests and
/// its current status — 'Pending', 'Fulfilled' or 'Returned' (sent back by the
/// Discipline Office), matching good_moral_requests.status (see
/// supabase/add_good_moral_status_and_insert_policies.sql and
/// supabase/add_good_moral_form_data.sql).
class GoodMoralRequestStatus {
  const GoodMoralRequestStatus({
    required this.id,
    required this.documentType,
    required this.purpose,
    required this.status,
    required this.requestDate,
    this.flagNote,
    this.formData,
  });

  final String id;
  final String documentType;
  final String purpose;
  final String status;
  final DateTime requestDate;

  /// The officer's note when the request was flagged or sent back.
  final String? flagNote;

  /// The slip as submitted (`GoodMoralFormData.toJson`), so a returned
  /// request can be reopened for editing. Null for requests from before the
  /// slip was stored field by field.
  final Map<String, dynamic>? formData;

  bool get isFulfilled => status == 'Fulfilled';
  bool get isReturned => status == 'Returned';
}
