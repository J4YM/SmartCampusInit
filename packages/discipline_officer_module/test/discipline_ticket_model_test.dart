import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DisciplineCaseModel makeCase({
    required String id,
    String studentName = 'Jane Doe',
    String? admissionSlipId,
  }) {
    return DisciplineCaseModel(
      id: id,
      studentName: studentName,
      studentNumber: '2024-0001',
      programGradeSection: 'BSIT 3-A',
      violationType: 'Improper uniform',
      submittedBy: 'System',
      submitterRole: '',
      incidentDateTime: DateTime(2026, 1, 1),
      description: '',
      admissionSlipId: admissionSlipId,
    );
  }

  test('cases with no admissionSlipId each become their own single-case ticket', () {
    final cases = [makeCase(id: 'v1'), makeCase(id: 'v2')];

    final tickets = groupCasesIntoTickets(cases);

    expect(tickets, hasLength(2));
    expect(tickets[0].ticketId, 'v1');
    expect(tickets[0].cases, [cases[0]]);
    expect(tickets[1].ticketId, 'v2');
    expect(tickets[1].cases, [cases[1]]);
  });

  test('cases sharing an admissionSlipId collapse into one ticket, in original order', () {
    final cases = [
      makeCase(id: 'v1', admissionSlipId: 'slip-A'),
      makeCase(id: 'v2', admissionSlipId: 'slip-A'),
      makeCase(id: 'v3', admissionSlipId: 'slip-A'),
    ];

    final tickets = groupCasesIntoTickets(cases);

    expect(tickets, hasLength(1));
    expect(tickets.single.ticketId, 'slip-A');
    expect(tickets.single.cases, cases);
  });

  test('tickets preserve first-seen order across a mix of grouped and single cases', () {
    final cases = [
      makeCase(id: 'v1', admissionSlipId: 'slip-A'),
      makeCase(id: 'v2'),
      makeCase(id: 'v3', admissionSlipId: 'slip-A'),
    ];

    final tickets = groupCasesIntoTickets(cases);

    expect(tickets.map((t) => t.ticketId), ['slip-A', 'v2']);
    expect(tickets[0].cases, [cases[0], cases[2]]);
    expect(tickets[1].cases, [cases[1]]);
  });
}
