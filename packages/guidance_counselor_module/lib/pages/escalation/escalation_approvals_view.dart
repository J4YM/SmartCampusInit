import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show EscalationReportModel, EscalationStatusBadge;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../shared/guidance_tab_chrome.dart';

/// Width of the table's far-right action column (approve + reject).
const double _kActionColumnWidth = 84;

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('Reported By', flex: 3, minWidth: 150),
  DashboardTableColumn('Violations', flex: 2, minWidth: 100),
  DashboardTableColumn('Sent Via', flex: 2, minWidth: 110),
  DashboardTableColumn('Submitted', flex: 3, minWidth: 170),
  DashboardTableColumn('Status', flex: 3, minWidth: 150),
  DashboardTableColumn('', width: _kActionColumnWidth, sticky: true),
];

/// What the detail popup asks the tab to do next.
enum _DetailAction { approve, reject }

/// Guidance Counselor's "Escalation Approvals" tab: reports from Student
/// Affairs (and the automatic 3-violations / major-offense flag) waiting for
/// sign-off. Approving sends the parent notification by the channels the
/// officer chose (SMS and/or email); the counselor may edit the message
/// first. Rejecting needs a reason, which goes back to Student Affairs.
///
/// One table card in the app-wide layout: waiting reports first, then the
/// decided ones, searchable and filterable by status. A row opens the full
/// report; the icon buttons ending a waiting row approve or reject it.
class EscalationApprovalsView extends StatefulWidget {
  const EscalationApprovalsView({
    super.key,
    required this.reports,
    this.onDecide,
  });

  final List<EscalationReportModel> reports;

  /// Persists the decision. [message] is the (possibly edited) parent
  /// message for an approval; [note] is the reason for a rejection / optional
  /// remark for an approval. Null hides the buttons (demo).
  final Future<void> Function(
    EscalationReportModel report, {
    required bool approve,
    String? note,
    String? message,
    DateTime? meetingAt,
    String? meetingLocation,
  })? onDecide;

  @override
  State<EscalationApprovalsView> createState() =>
      _EscalationApprovalsViewState();
}

class _EscalationApprovalsViewState extends State<EscalationApprovalsView> {
  final _searchController = TextEditingController();
  String _query = '';

  /// `Pending_GC`, `Approved` or `Rejected`; null = every report.
  String? _statusFilter;
  int _currentPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Waiting reports first (as the host ordered them), then the decided ones.
  List<EscalationReportModel> get _ordered => [
        ...widget.reports.where((r) => r.isPending),
        ...widget.reports.where((r) => !r.isPending),
      ];

  List<EscalationReportModel> get _filtered {
    final q = _query.trim().toLowerCase();
    return _ordered.where((r) {
      if (_statusFilter != null && r.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return r.studentName.toLowerCase().contains(q) ||
          r.studentNumber.toLowerCase().contains(q) ||
          (r.createdByName ?? '').toLowerCase().contains(q) ||
          r.summary.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _open(EscalationReportModel r) async {
    final canDecide = r.isPending && widget.onDecide != null;
    final action = await showAppPopup<_DetailAction>(
      context: context,
      builder: (_) => _ReportDetailDialog(report: r, canDecide: canDecide),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _DetailAction.approve:
        await _approve(r);
      case _DetailAction.reject:
        await _reject(r);
    }
  }

  Future<void> _approve(EscalationReportModel r) async {
    final result = await showAppPopup<_ApproveResult>(
      context: context,
      builder: (_) => _ApproveDialog(report: r),
    );
    if (result == null || !mounted) return;
    await _decide(
      r,
      approve: true,
      note: result.note,
      message: result.message,
      meetingAt: result.meetingAt,
      meetingLocation: result.meetingLocation,
    );
  }

  Future<void> _reject(EscalationReportModel r) async {
    final note = await showAppPopup<String>(
      context: context,
      builder: (_) => _RejectDialog(report: r),
    );
    if (note == null || !mounted) return;
    await _decide(r, approve: false, note: note);
  }

  Future<void> _decide(
    EscalationReportModel r, {
    required bool approve,
    String? note,
    String? message,
    DateTime? meetingAt,
    String? meetingLocation,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onDecide!(
        r,
        approve: approve,
        note: note,
        message: message,
        meetingAt: meetingAt,
        meetingLocation: meetingLocation,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(approve
            ? (meetingAt == null
                ? 'Approved. The parent is being notified.'
                : 'Approved. The parent is being notified and invited to the meeting.')
            : 'Report rejected.'),
      ));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Could not save the decision: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pageSize = context.cardPageSize;
    final totalPages = filtered.isEmpty ? 1 : (filtered.length / pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageItems =
        filtered.skip((currentPage - 1) * pageSize).take(pageSize).toList();

    final total = widget.reports.length;
    final awaiting = widget.reports.where((r) => r.isPending).length;
    final canDecide = widget.onDecide != null;

    final rows = <Widget>[
      for (var i = 0; i < pageItems.length; i++)
        _ReportRow(
          // A report that arrives (or moves to Decided) drops in at the top.
          key: ValueKey('${pageItems[i].isPending ? 'pending' : 'decided'}-'
              '${pageItems[i].id}'),
          report: pageItems[i],
          showDivider: i < pageItems.length - 1,
          onOpen: () => _open(pageItems[i]),
          onApprove: pageItems[i].isPending && canDecide
              ? () => _approve(pageItems[i])
              : null,
          onReject: pageItems[i].isPending && canDecide
              ? () => _reject(pageItems[i])
              : null,
        ),
    ];

    return GuidanceTableCard(
      title: 'Escalation Approvals',
      subtitle: Text(
        '$total ${total == 1 ? 'report' : 'reports'}'
        '${awaiting > 0 ? ' | $awaiting awaiting your approval' : ''}',
        style: GuidanceTableCard.subtitleStyle(context),
      ),
      toolbar: Row(
        children: [
          Expanded(
            child: GuidanceSearchField(
              key: const Key('escalation-search'),
              controller: _searchController,
              hint: 'Search student, sender or summary',
              onChanged: (value) => setState(() {
                _query = value;
                _currentPage = 1;
              }),
            ),
          ),
          const SizedBox(width: 10),
          FilterMenuButton(
            compact: true,
            backgroundColor: GuidanceTabColors.searchFill(context),
            menuColor: GuidanceTabColors.card(context),
            borderColor: GuidanceTabColors.cardBorder(context),
            iconColor: GuidanceTabColors.mutedIcon(context),
            textColor: GuidanceTabColors.primaryText(context),
            mutedTextColor: GuidanceTabColors.secondaryText(context),
            accentColor: GuidanceTabColors.primaryAction,
            sections: [
              FilterMenuSection(
                title: 'Status',
                options: const [
                  FilterMenuOption(
                      label: 'Awaiting approval', value: 'Pending_GC'),
                  FilterMenuOption(label: 'Approved', value: 'Approved'),
                  FilterMenuOption(label: 'Rejected', value: 'Rejected'),
                ],
                selectedValue: _statusFilter,
                onChanged: (value) => setState(() {
                  _statusFilter = value;
                  _currentPage = 1;
                }),
              ),
            ],
          ),
        ],
      ),
      columns: _columns,
      rows: rows,
      empty: DashboardTableEmptyState(
        icon: Icons.fact_check_outlined,
        message: widget.reports.isEmpty
            ? 'No escalation reports yet'
            : 'No reports match your search',
      ),
      footer: filtered.isEmpty
          ? null
          : CardPaginationFooter(
              currentPage: currentPage,
              totalPages: totalPages,
              totalCount: filtered.length,
              textColor: GuidanceTabColors.secondaryText(context),
              accentColor: GuidanceTabColors.primaryAction,
              mutedBackground: GuidanceTabColors.surfaceBackground(context),
              onPrevious: () => setState(() => _currentPage = currentPage - 1),
              onNext: () => setState(() => _currentPage = currentPage + 1),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row
// ---------------------------------------------------------------------------

class _ReportRow extends StatelessWidget {
  const _ReportRow({
    super.key,
    required this.report,
    required this.showDivider,
    required this.onOpen,
    this.onApprove,
    this.onReject,
  });

  final EscalationReportModel report;
  final bool showDivider;
  final VoidCallback onOpen;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final r = report;
    Widget line(String text, TextStyle style) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

    return DashboardTableRow(
      columns: _columns,
      showDivider: showDivider,
      onTap: onOpen,
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            line(r.studentName, dashboardTablePrimaryStyle(context)),
            line(r.studentNumber, dashboardTableSubStyle(context)),
          ],
        ),
        line(
          r.isAuto ? 'Automatic flag' : (r.createdByName ?? 'Student Affairs'),
          dashboardTableBodyStyle(context),
        ),
        line('${r.violationCount}', dashboardTableBodyStyle(context)),
        line(r.channelsLabel, dashboardTableBodyStyle(context)),
        line(formatDateTime12h(r.createdAt), dashboardTableMetaStyle(context)),
        Align(
          alignment: Alignment.centerLeft,
          child: EscalationStatusBadge(report: r),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onApprove != null)
                GuidanceRowIconButton(
                  key: ValueKey('approve-${r.id}'),
                  icon: Icons.check_rounded,
                  tooltip: 'Approve & notify parent',
                  onPressed: onApprove,
                ),
              if (onReject != null)
                GuidanceRowIconButton(
                  key: ValueKey('reject-${r.id}'),
                  icon: Icons.close_rounded,
                  tooltip: 'Reject',
                  color: kDangerTextColor,
                  onPressed: onReject,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Popups
// ---------------------------------------------------------------------------

/// The whole report: who, how many violations, the officer's summary, the
/// message the parent would get and (once decided) the counselor's note.
class _ReportDetailDialog extends StatelessWidget {
  const _ReportDetailDialog({required this.report, required this.canDecide});

  final EscalationReportModel report;
  final bool canDecide;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final c = AppPopupColors.of(context);
    final mobile = context.isMobileWidth;
    final bodyStyle = GoogleFonts.poppins(
      fontSize: mobile ? 11 : 13,
      height: 1.5,
      color: c.text,
    );

    Widget fact(String label, Widget value) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                child: Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: mobile ? 10 : 12, color: c.muted)),
              ),
              Expanded(child: value),
            ],
          ),
        );

    Widget text(String value) =>
        Text(value, style: GoogleFonts.poppins(fontSize: mobile ? 11 : 12.5, color: c.text));

    Widget well(String value) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.fieldFill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(value, style: bodyStyle),
        );

    return AppPopup(
      title: 'Escalation report',
      subtitle: '${r.studentName} · ${r.studentNumber}',
      width: 540,
      actions: [
        if (canDecide) ...[
          SecondaryPillButton(
            key: const Key('detail-reject'),
            label: 'Reject',
            destructive: true,
            onTap: () => Navigator.of(context).pop(_DetailAction.reject),
          ),
          AppPopupPrimaryButton(
            key: const Key('detail-approve'),
            label: 'Approve & notify parent',
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(context).pop(_DetailAction.approve),
          ),
        ] else
          AppPopupSecondaryButton(
            label: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fact('Status', Align(
              alignment: Alignment.centerLeft,
              child: EscalationStatusBadge(report: r))),
          fact(
              'Reported by',
              text(r.isAuto
                  ? 'Automatic flag'
                  : (r.createdByName ?? 'Student Affairs'))),
          fact('Violations', text('${r.violationCount}')),
          fact('Sent via', text(r.channelsLabel)),
          fact('Submitted', text(formatDateTime12h(r.createdAt))),
          if (r.decidedByName != null)
            fact(
              'Decided by',
              text(r.decidedAt == null
                  ? r.decidedByName!
                  : '${r.decidedByName} · ${formatDateTime12h(r.decidedAt!)}'),
            ),
          if (r.summary.isNotEmpty) ...[
            const AppPopupSection('Summary'),
            well(r.summary),
          ],
          const AppPopupSection('Message to the parent'),
          well(r.message),
          if (r.decisionNote != null && r.decisionNote!.isNotEmpty) ...[
            const AppPopupSection('Counselor note'),
            well(r.decisionNote!),
          ],
        ],
      ),
    );
  }
}

/// What the approve dialog hands back. [meetingAt] is set when the counselor
/// also invites the parent to a meeting.
class _ApproveResult {
  const _ApproveResult({
    required this.message,
    required this.note,
    this.meetingAt,
    this.meetingLocation,
  });

  final String message;
  final String note;
  final DateTime? meetingAt;
  final String? meetingLocation;
}

class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({required this.report});

  final EscalationReportModel report;

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  late final _message = TextEditingController(text: widget.report.message);
  final _note = TextEditingController();
  final _location = TextEditingController();

  /// Off by default: approving alone keeps working as before.
  bool _scheduleMeeting = false;
  late DateTime _when = () {
    final t = DateTime.now().add(const Duration(days: 1));
    return DateTime(t.year, t.month, t.day, 9);
  }();

  @override
  void dispose() {
    _message.dispose();
    _note.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _when.isBefore(now) ? now : _when,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked == null || !mounted) return;
    setState(() => _when =
        DateTime(picked.year, picked.month, picked.day, _when.hour, _when.minute));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (picked == null || !mounted) return;
    setState(() => _when =
        DateTime(_when.year, _when.month, _when.day, picked.hour, picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final fieldStyle = appPopupFieldStyle(context);
    final loc = MaterialLocalizations.of(context);
    final timeError =
        _scheduleMeeting && !_when.isAfter(DateTime.now())
            ? 'Choose a time in the future.'
            : null;
    final valid = _message.text.trim().isNotEmpty && timeError == null;

    Widget pickerField(Key key, IconData icon, String text, VoidCallback onTap) =>
        Material(
          color: c.fieldFill,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                Icon(icon, size: 18, color: c.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: fieldStyle)),
              ]),
            ),
          ),
        );

    return AppPopup(
      title: 'Approve & notify parent',
      subtitle: 'Sent by ${widget.report.channelsLabel} to the guardian of '
          '${widget.report.studentName}.',
      width: 480,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('approve-confirm'),
          label: 'Approve',
          onPressed: valid
              ? () => Navigator.of(context).pop(_ApproveResult(
                    message: _message.text.trim(),
                    note: _note.text.trim(),
                    meetingAt: _scheduleMeeting ? _when : null,
                    meetingLocation: _scheduleMeeting &&
                            _location.text.trim().isNotEmpty
                        ? _location.text.trim()
                        : null,
                  ))
              : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPopupTextField(
            label: 'Message to the parent',
            controller: _message,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
          ),
          kAppPopupFieldGap,
          AppPopupTextField(
            label: 'Note (optional)',
            controller: _note,
          ),
          const SizedBox(height: 14),
          const AppPopupSection('Meeting with the parent',
              icon: Icons.event_outlined),
          AppPopupCheckboxTile(
            key: const Key('escalation-meeting-toggle'),
            title: 'Schedule a meeting',
            subtitle: 'The parent confirms or declines in the Parent Portal.',
            value: _scheduleMeeting,
            onChanged: (v) => setState(() => _scheduleMeeting = v),
          ),
          if (_scheduleMeeting) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                flex: 3,
                child: pickerField(
                  const Key('escalation-meeting-date'),
                  Icons.calendar_today_outlined,
                  loc.formatMediumDate(_when),
                  _pickDate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: pickerField(
                  const Key('escalation-meeting-time'),
                  Icons.schedule_rounded,
                  loc.formatTimeOfDay(TimeOfDay.fromDateTime(_when)),
                  _pickTime,
                ),
              ),
            ]),
            if (timeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(timeError,
                    key: const Key('escalation-meeting-error'),
                    style: GoogleFonts.poppins(
                        fontSize: 11.5, color: AppPopupColors.danger)),
              ),
            const SizedBox(height: 14),
            AppPopupTextField(
              label: 'Where (optional)',
              fieldKey: const Key('escalation-meeting-location'),
              controller: _location,
              hint: 'e.g. Guidance Office',
            ),
          ],
        ],
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.report});

  final EscalationReportModel report;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _reason.text.trim().isNotEmpty;
    return AppPopup(
      title: 'Reject report',
      subtitle: '${widget.report.studentName} · ${widget.report.studentNumber}',
      width: 460,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('reject-confirm'),
          label: 'Reject',
          destructive: true,
          onPressed:
              valid ? () => Navigator.of(context).pop(_reason.text.trim()) : null,
        ),
      ],
      body: AppPopupTextField(
        label: 'Reason (sent back to Student Affairs)',
        controller: _reason,
        maxLines: 3,
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}
