import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/discipline_case_model.dart';
import '../../models/escalation_report_model.dart';
import '../../theme/discipline_officer_colors.dart';

/// Colors shared by the escalation status badges (also used by the Guidance
/// Counselor's approvals view).
Color escalationStatusColor(EscalationReportModel r) => switch (r.status) {
      'Approved' => DisciplineOfficerColors.validateGreen,
      'Rejected' => DisciplineOfficerColors.denyRed,
      _ => const Color(0xFFD97706),
    };

class EscalationStatusBadge extends StatelessWidget {
  const EscalationStatusBadge({super.key, required this.report});

  final EscalationReportModel report;

  @override
  Widget build(BuildContext context) {
    final color = escalationStatusColor(report);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        report.statusLabel,
        style: GoogleFonts.poppins(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// The Parental Intervention tab: the history of escalated violations, every
/// escalation report with where it stands in the Guidance Counselor's
/// approval, and the "Issue Escalation Report" action. A report only reaches
/// the parent (SMS / email) after the Guidance Counselor approves it.
class ParentalInterventionView extends StatelessWidget {
  const ParentalInterventionView({
    super.key,
    required this.reports,
    required this.cases,
    this.onIssue,
  });

  final List<EscalationReportModel> reports;

  /// Every violation on record (the Violation History's source) — escalated
  /// ones form the history list, and any student with a violation can be
  /// escalated.
  final List<DisciplineCaseModel> cases;

  /// Persists a new report. When null the Issue button is hidden (demo).
  final Future<void> Function(EscalationDraft draft)? onIssue;

  Future<void> _issue(BuildContext context) async {
    final theme = Theme.of(context);
    final draft = await showDialog<EscalationDraft>(
      context: context,
      builder: (_) => Theme(data: theme, child: _IssueEscalationDialog(cases: cases)),
    );
    if (draft == null || onIssue == null) return;
    try {
      await onIssue!(draft);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Escalation report sent to the Guidance Counselor.'),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not send the report: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = DisciplineOfficerColors.rowText(context);
    final muted = DisciplineOfficerColors.mutedText(context);
    final escalated = cases.where((c) => c.isEscalated).toList()
      ..sort((a, b) => b.incidentDateTime.compareTo(a.incidentDateTime));

    Widget card({required String title, required List<Widget> children, Widget? trailing}) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: DisciplineOfficerColors.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DisciplineOfficerColors.cardBorder(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w700, color: text)),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card(
          title: 'Escalation Reports',
          trailing: onIssue == null
              ? null
              : FilledButton.icon(
                  onPressed: () => _issue(context),
                  icon: const Icon(Icons.campaign_outlined, size: 18),
                  label: const Text('Issue Escalation Report'),
                ),
          children: [
            Text(
              'Reports go to the Guidance Counselor first. The parent is only '
              'notified (SMS / email) once the counselor approves.',
              style: GoogleFonts.poppins(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 12),
            if (reports.isEmpty)
              Text('No escalation reports yet.',
                  style: GoogleFonts.poppins(fontSize: 12.5, color: muted))
            else
              for (final r in reports) _ReportTile(report: r),
          ],
        ),
        const SizedBox(height: 16),
        card(
          title: 'Escalated Violations History',
          children: [
            if (escalated.isEmpty)
              Text('No escalated violations on record.',
                  style: GoogleFonts.poppins(fontSize: 12.5, color: muted))
            else
              for (final c in escalated)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 18, color: Color(0xFFD97706)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${c.studentName} · ${c.studentNumber}',
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: text)),
                            Text(
                              '${c.violationType} · ${formatDateTime12h(c.incidentDateTime)}',
                              style: GoogleFonts.poppins(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});

  final EscalationReportModel report;

  @override
  Widget build(BuildContext context) {
    final text = DisciplineOfficerColors.rowText(context);
    final muted = DisciplineOfficerColors.mutedText(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.background(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${report.studentName} · ${report.studentNumber}',
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w600, color: text)),
              ),
              EscalationStatusBadge(report: report),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${report.isAuto ? 'Automatic flag' : 'By ${report.createdByName ?? 'Student Affairs'}'}'
            ' · ${report.channelsLabel} · ${formatDateTime12h(report.createdAt)}',
            style: GoogleFonts.poppins(fontSize: 11.5, color: muted),
          ),
          if (report.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(report.summary,
                style: GoogleFonts.poppins(fontSize: 12.5, color: text)),
          ],
          if (report.decisionNote != null && report.decisionNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Counselor note: ${report.decisionNote}',
                style: GoogleFonts.poppins(fontSize: 12, color: muted)),
          ],
        ],
      ),
    );
  }
}

class _IssueEscalationDialog extends StatefulWidget {
  const _IssueEscalationDialog({required this.cases});

  final List<DisciplineCaseModel> cases;

  @override
  State<_IssueEscalationDialog> createState() => _IssueEscalationDialogState();
}

class _IssueEscalationDialogState extends State<_IssueEscalationDialog> {
  String? _studentNumber;
  final Set<String> _selected = {};
  final _summary = TextEditingController();
  final _message = TextEditingController();
  bool _sms = true;
  bool _email = false;

  late final Map<String, DisciplineCaseModel> _students = {
    for (final c in widget.cases) c.studentNumber: c,
  };

  List<DisciplineCaseModel> get _studentCases =>
      widget.cases.where((c) => c.studentNumber == _studentNumber).toList();

  @override
  void dispose() {
    _summary.dispose();
    _message.dispose();
    super.dispose();
  }

  bool get _valid =>
      _studentNumber != null &&
      _selected.isNotEmpty &&
      _message.text.trim().isNotEmpty &&
      (_sms || _email);

  void _pickStudent(String? number) {
    setState(() {
      _studentNumber = number;
      _selected
        ..clear()
        ..addAll(_studentCases.where((c) => c.isEscalated).map((c) => c.id));
      final name = number == null ? '' : _students[number]!.studentName;
      _message.text = number == null
          ? ''
          : '$name has repeated conduct concerns on record. Please visit '
              'the Guidance Office to discuss. Thank you.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = DisciplineOfficerColors.mutedText(context);
    return BentoFormDialog(
      title: 'Issue Escalation Report',
      width: 460,
      cancelLabel: 'Cancel',
      onCancel: () => Navigator.of(context).pop(),
      confirmLabel: 'Send to Guidance',
      confirmEnabled: _valid,
      onConfirm: () => Navigator.of(context).pop(EscalationDraft(
        studentNumber: _studentNumber!,
        violationIds: _selected.toList(),
        summary: _summary.text.trim(),
        message: _message.text.trim(),
        channels: [if (_sms) 'sms', if (_email) 'email'],
      )),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _studentNumber,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Student'),
              items: [
                for (final e in _students.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: Text('${e.value.studentName} · ${e.key}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _pickStudent,
            ),
            if (_studentNumber != null) ...[
              const SizedBox(height: 12),
              Text('Violations to include',
                  style: GoogleFonts.poppins(fontSize: 12, color: muted)),
              for (final c in _studentCases)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _selected.contains(c.id),
                  onChanged: (v) => setState(() {
                    v == true ? _selected.add(c.id) : _selected.remove(c.id);
                  }),
                  title: Text(c.violationType,
                      style: GoogleFonts.poppins(fontSize: 12.5)),
                  subtitle: Text(formatDateTime12h(c.incidentDateTime),
                      style: GoogleFonts.poppins(fontSize: 11)),
                ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _summary,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Report to the Guidance Counselor',
                hintText: 'What happened and why this needs intervention',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Message to the parent (counselor may edit)',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(value: _sms, onChanged: (v) => setState(() => _sms = v ?? false)),
                const Text('SMS'),
                const SizedBox(width: 16),
                Checkbox(value: _email, onChanged: (v) => setState(() => _email = v ?? false)),
                const Text('Email'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
