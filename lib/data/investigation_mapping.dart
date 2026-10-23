import 'package:discipline_officer_module/discipline_officer_module.dart'
    show InvestigationMeetingModel, InvestigationModel;

import 'guidance_investigation_repository.dart';

/// The row the repository read, as the Discipline Officer's Investigations tab
/// shows it.
InvestigationModel toInvestigationModel(GuidanceInvestigation i) =>
    InvestigationModel(
      id: i.id,
      studentName: i.studentName,
      studentNumber: i.studentNumber,
      section: i.section,
      offenseLabel: i.offenseDescription,
      offenseCategory: i.offenseCategory,
      incidentNotes: i.incidentNotes,
      incidentAt: i.incidentAt,
      createdAt: i.createdAt,
      status: i.status,
      findings: i.findings,
      recommendation: i.recommendation,
      evidencePaths: i.evidencePaths,
      meetings: [
        for (final m in i.meetings)
          InvestigationMeetingModel(
            id: m.id,
            scheduledAt: m.scheduledAt,
            invitee: m.invitee.value,
            status: m.status.value,
            location: m.location,
            responseNote: m.responseNote,
          ),
      ],
    );
