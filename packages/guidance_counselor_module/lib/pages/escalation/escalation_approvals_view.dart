import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        EndorsedViolation,
        EscalationReportModel,
        EscalationStatusBadge;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../shared/guidance_tab_chrome.dart';

/// Width of the table's far-right action column (approve + reject).
const double _kActionColumnWidth = 72;

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('Reported By', flex: 3, minWidth: 150),
  DashboardTableColumn('Asked For', flex: 3, minWidth: 150),
  DashboardTableColumn('Submitted', flex: 3, minWidth: 170),
  DashboardTableColumn('Status', flex: 3, minWidth: 150),
  DashboardTableColumn('', width: _kActionColumnWidth, sticky: true),
];

/// What the detail popup asks the tab to do next.
enum _DetailAction { approve, reject }

/// Guidance Associate's "Endorsement Approvals" tab: students Student Affairs
/// (and the automatic 3-violations / major-offense flag) asks Guidance to step
/// in for, waiting for sign-off. Approving a counseling endorsement just
/// accepts the student; one that includes a parent intervention also sends the
/// parent notification by the channels the officer chose (SMS and/or email),
/// and the counselor may edit the message first. Declining needs a reason,
/// which goes back to Student Affairs.
///
/// One table card in the app-wide layout: waiting endorsements first, then
/// the decided ones, searchable and filterable by status. A row opens the full
/// endorsement, with the student's violation history; the icon buttons ending
/// a waiting row approve or decline it.
class EscalationApprovalsView extends StatefulWidget {
  const EscalationApprovalsView({
    super.key,
    required this.reports,
    this.onDecide,
    this.onLoadHistory,
  });

  final List<EscalationReportModel> reports;

  /// An endorsed student's violation history (offense, date, status only).
  /// Null hides the section (demo).
  final Future<List<EndorsedViolation>> Function(EscalationReportModel report)?
      onLoadHistory;

  /// Persists the decision. [message] is the (possibly edited) parent
  /// message for an approval; [note] is the reason for a rejection / optional
  /// remark for an approval. Null hides the buttons (demo).
  final Future<void> Function(
    EscalationReportModel report, {
    required bool approve,
    String? note,
    String? message,
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
      builder: (_) => _ReportDetailDialog(
        report: r,
        canDecide: canDecide,
        onLoadHistory: widget.onLoadHistory,
      ),
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
      message: r.kind.notifiesParent ? result.message : null,
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
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onDecide!(
        r,
        approve: approve,
        note: note,
        message: message,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(approve
            ? (!r.kind.notifiesParent
                ? 'Approved. Student Affairs will arrange a meeting for you to confirm.'
                : 'Approved. The parent is being notified.')
            : 'Endorsement declined.'),
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
      title: 'Endorsement Approvals',
      subtitle: Text(
        '$total ${total == 1 ? 'endorsement' : 'endorsements'}'
        '${awaiting > 0 ? ' | $awaiting awaiting your approval' : ''}',
        style: GuidanceTableCard.subtitleStyle(context),
      ),
      toolbar: Row(
        children: [
          Expanded(
            child: GuidanceSearchField(
              key: const Key('escalation-search'),
              controller: _searchController,
              hint: 'Search student, sender or reason',
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
                  FilterMenuOption(label: 'Declined', value: 'Rejected'),
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
            ? 'No endorsements yet'
            : 'No endorsements match your search',
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
        line(r.kind.label, dashboardTableBodyStyle(context)),
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
                  tooltip: r.kind.notifiesParent ? 'Approve & notify parent' : 'Approve',
                  onPressed: onApprove,
                ),
              if (onReject != null)
                GuidanceRowIconButton(
                  key: ValueKey('reject-${r.id}'),
                  icon: Icons.close_rounded,
                  tooltip: 'Decline',
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
  const _ReportDetailDialog({
    required this.report,
    required this.canDecide,
    this.onLoadHistory,
  });

  final EscalationReportModel report;
  final bool canDecide;
  final Future<List<EndorsedViolation>> Function(EscalationReportModel report)?
      onLoadHistory;

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
      title: 'Endorsement',
      subtitle: '${r.studentName} · ${r.studentNumber}',
      width: 540,
      actions: [
        if (canDecide) ...[
          SecondaryPillButton(
            key: const Key('detail-reject'),
            label: 'Decline',
            destructive: true,
            onTap: () => Navigator.of(context).pop(_DetailAction.reject),
          ),
          AppPopupPrimaryButton(
            key: const Key('detail-approve'),
            label: r.kind.notifiesParent ? 'Approve & notify parent' : 'Approve',
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
          fact('Asked for', text(r.kind.label)),
          if ((r.otherDescription ?? '').trim().isNotEmpty)
            fact('Intervention', text(r.otherDescription!)),
          if (r.excludeParent) fact('Parent', text('Parent excluded')),
          if (r.kind.notifiesParent) fact('Sent via', text(r.channelsLabel)),
          fact('Submitted', text(formatDateTime12h(r.createdAt))),
          if (r.decidedByName != null)
            fact(
              'Decided by',
              text(r.decidedAt == null
                  ? r.decidedByName!
                  : '${r.decidedByName} · ${formatDateTime12h(r.decidedAt!)}'),
            ),
          if (r.summary.isNotEmpty) ...[
            const AppPopupSection('Reason'),
            well(r.summary),
          ],
          if (r.kind.notifiesParent) ...[
            const AppPopupSection('Message to the parent'),
            well(r.message),
          ],
          if (onLoadHistory != null) ...[
            const AppPopupSection('Violation history'),
            _HistoryList(load: () => onLoadHistory!(r)),
          ],
          if (r.decisionNote != null && r.decisionNote!.isNotEmpty) ...[
            const AppPopupSection('Guidance note'),
            well(r.decisionNote!),
          ],
        ],
      ),
    );
  }
}

/// What the approve dialog hands back.
class _ApproveResult {
  const _ApproveResult({required this.message, required this.note});

  final String message;
  final String note;
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

  @override
  void dispose() {
    _message.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parent = widget.report.kind.notifiesParent;
    final valid = !parent || _message.text.trim().isNotEmpty;

    return AppPopup(
      title: parent ? 'Approve & notify parent' : 'Approve endorsement',
      subtitle: parent
          ? 'Sent by ${widget.report.channelsLabel} to the guardian of '
              '${widget.report.studentName}.'
          : 'Guidance accepts ${widget.report.studentName}. Student Affairs '
              'can then arrange a meeting for you to confirm.',
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
                  ))
              : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (parent) ...[
            AppPopupTextField(
              label: 'Message to the parent',
              controller: _message,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
            ),
            kAppPopupFieldGap,
          ],
          AppPopupTextField(
            label: 'Note (optional)',
            controller: _note,
          ),
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
      title: 'Decline endorsement',
      subtitle: '${widget.report.studentName} · ${widget.report.studentNumber}',
      width: 460,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('reject-confirm'),
          label: 'Decline',
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

/// The endorsed student's violations: offense, date and status, nothing more.
/// Loads once when the popup opens; a failure says so without hiding the rest
/// of the endorsement.
class _HistoryList extends StatefulWidget {
  const _HistoryList({required this.load});

  final Future<List<EndorsedViolation>> Function() load;

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  late final Future<List<EndorsedViolation>> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final style = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 12.5,
      color: c.text,
    );
    final muted = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 12.5,
      color: c.muted,
    );

    return FutureBuilder<List<EndorsedViolation>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Text('Loading…', style: muted);
        }
        if (snapshot.hasError) {
          return Text('Could not load the violation history', style: muted);
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return Text('No violations on record', style: muted);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final v in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.fieldFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.offense,
                          style: style.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        [
                          if (v.incidentAt != null)
                            formatDateTime12h(v.incidentAt!),
                          v.status.replaceAll('_', ' '),
                        ].join(' · '),
                        style: muted,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
