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

/// Every violation in the queue for one student — what the Violation Queue
/// shows as a single entry however many slips those violations came from.
/// [cases] run newest first, so a violation filed later always lands on top.
class DisciplineStudentGroup {
  const DisciplineStudentGroup({required this.studentKey, required this.cases});

  /// Identifies the student: their student number, or (for a case that has
  /// none) their lower-cased name.
  final String studentKey;

  /// This student's cases, newest incident first. Never empty.
  final List<DisciplineCaseModel> cases;

  /// The case whose student details (name, section, number) head the entry.
  /// The newest one: if the student's section changed between violations, the
  /// latest is the current one.
  DisciplineCaseModel get primaryCase => cases.first;
}

/// Groups [cases] by student into [DisciplineStudentGroup]s: one entry per
/// student, each student's violations newest first. Students keep the order
/// they first appear in [cases], so a new violation for a student already in
/// the queue joins their existing entry instead of adding another one.
List<DisciplineStudentGroup> groupCasesByStudent(
  List<DisciplineCaseModel> cases,
) {
  String keyOf(DisciplineCaseModel c) {
    final number = c.studentNumber.trim();
    return number.isNotEmpty ? number : c.studentName.trim().toLowerCase();
  }

  final order = <String>[];
  final byStudent = <String, List<DisciplineCaseModel>>{};
  for (final c in cases) {
    final key = keyOf(c);
    if (!byStudent.containsKey(key)) order.add(key);
    byStudent.putIfAbsent(key, () => []).add(c);
  }

  return [
    for (final key in order)
      DisciplineStudentGroup(
        studentKey: key,
        cases: _newestFirst(byStudent[key]!),
      ),
  ];
}

/// [cases] sorted by incident time, newest first. List.sort isn't stable, so
/// equal times keep their incoming order through an index tie-break.
List<DisciplineCaseModel> _newestFirst(List<DisciplineCaseModel> cases) {
  final indexed = [for (var i = 0; i < cases.length; i++) (i, cases[i])];
  indexed.sort((a, b) {
    final byTime = b.$2.incidentDateTime.compareTo(a.$2.incidentDateTime);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}
