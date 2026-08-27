import 'discipline_case_model.dart';

/// One or more [DisciplineCaseModel]s filed in the same submission —
/// [ValidationQueueCard] renders one row per ticket instead of one per
/// underlying violation, while each case inside keeps its own independent
/// status and actions (resolve/escalate/modify/archive).
class DisciplineTicketModel {
  const DisciplineTicketModel({required this.ticketId, required this.cases});

  /// [DisciplineCaseModel.admissionSlipId] for a grouped ticket, or the
  /// lone case's own id when it has no admission slip.
  final String ticketId;

  final List<DisciplineCaseModel> cases;

  /// The case shown for a ticket's summary line (student name, grade &
  /// section, etc.) — all cases in a ticket share the same student, so any
  /// of them would do; the first keeps ticket order stable.
  DisciplineCaseModel get primaryCase => cases.first;
}

/// Groups [cases] by [DisciplineCaseModel.admissionSlipId] into
/// [DisciplineTicketModel]s, preserving each ticket's first-seen order.
/// Cases with no `admissionSlipId` each become their own single-case
/// ticket, keyed by their own id.
List<DisciplineTicketModel> groupCasesIntoTickets(
  List<DisciplineCaseModel> cases,
) {
  final ticketOrder = <String>[];
  final casesByTicket = <String, List<DisciplineCaseModel>>{};

  for (final caseItem in cases) {
    final ticketId = caseItem.admissionSlipId ?? caseItem.id;
    if (!casesByTicket.containsKey(ticketId)) {
      ticketOrder.add(ticketId);
    }
    casesByTicket.putIfAbsent(ticketId, () => []).add(caseItem);
  }

  return [
    for (final ticketId in ticketOrder)
      DisciplineTicketModel(
        ticketId: ticketId,
        cases: casesByTicket[ticketId]!,
      ),
  ];
}
