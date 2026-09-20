// packages/parent_portal_module/lib/models/good_moral_request_status.dart

/// One of the requester's own Good Moral (or other document) requests and
/// its current fulfillment status — 'Pending' or 'Fulfilled', matching
/// good_moral_requests.status (see
/// supabase/add_good_moral_status_and_insert_policies.sql).
class GoodMoralRequestStatus {
  const GoodMoralRequestStatus({
    required this.id,
    required this.documentType,
    required this.purpose,
    required this.status,
    required this.requestDate,
  });

  final String id;
  final String documentType;
  final String purpose;
  final String status;
  final DateTime requestDate;

  bool get isFulfilled => status == 'Fulfilled';
}
