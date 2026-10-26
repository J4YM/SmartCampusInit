import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

import '../shared/guidance_tab_chrome.dart';
import 'referrals_models.dart';

/// Width of the table's far-right action column.
const double _kActionColumnWidth = 44;

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('From', flex: 3, minWidth: 160),
  DashboardTableColumn('Concern', flex: 4, minWidth: 190),
  DashboardTableColumn('Meeting', flex: 4, minWidth: 220),
  DashboardTableColumn('Submitted', flex: 3, minWidth: 170),
  DashboardTableColumn('Status', flex: 2, minWidth: 120),
  DashboardTableColumn('', width: _kActionColumnWidth, sticky: true),
];

const _outcomes = ['Completed', 'Missed', 'Cancelled'];

/// What the referral popup asks the tab to do.
sealed class _PopupResult {}

class _SaveResult extends _PopupResult {
  _SaveResult(this.status, this.note);
  final String status;
  final String note;
}

class _OutcomeResult extends _PopupResult {
  _OutcomeResult(this.meeting, this.status);
  final ReferralMeetingModel meeting;
  final String status;
}

/// The Guidance Associate's "Referrals" tab: the students who asked Guidance
/// for help themselves (a Self Referral) and the endorsements from Student
/// Affairs that Guidance accepted. Urgent and still-open ones come first. A
/// row opens the full referral, where the Associate sets the status and, for
/// a self referral, leaves a note the student reads; the icon ending an open
/// row schedules a meeting with the student, the parent, or both.
class GuidanceReferralsView extends StatefulWidget {
  const GuidanceReferralsView({
    super.key,
    required this.referrals,
    this.onUpdate,
    this.onScheduleMeeting,
    this.onSetMeetingOutcome,
  });

  final List<GuidanceReferralModel> referrals;

  /// Saves a status change / note. Null makes the tab read-only (demo).
  final Future<void> Function(
    GuidanceReferralModel referral, {
    required String status,
    String? note,
  })? onUpdate;

  /// Invites the student, the parent or both. Null hides the action.
  final Future<void> Function(
    GuidanceReferralModel referral,
    MeetingFormResult meeting,
  )? onScheduleMeeting;

  /// Marks a meeting `Completed`, `Missed` or `Cancelled`. Null hides them.
  final Future<void> Function(ReferralMeetingModel meeting, String status)?
      onSetMeetingOutcome;

  @override
  State<GuidanceReferralsView> createState() => _GuidanceReferralsViewState();
}

class _GuidanceReferralsViewState extends State<GuidanceReferralsView> {
  final _searchController = TextEditingController();
  String _query = '';

  /// `Pending`, `In_Progress` or `Closed`; null = every referral.
  String? _statusFilter;
  int _currentPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Open before closed, urgent before routine, then newest first.
  List<GuidanceReferralModel> get _ordered {
    final list = [...widget.referrals];
    list.sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      if (a.isUrgent != b.isUrgent) return a.isUrgent ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  List<GuidanceReferralModel> get _filtered {
    final q = _query.trim().toLowerCase();
    return _ordered.where((r) {
      if (_statusFilter != null && r.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return r.studentName.toLowerCase().contains(q) ||
          r.studentNumber.toLowerCase().contains(q) ||
          r.concernLabel.toLowerCase().contains(q) ||
          r.details.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _open(GuidanceReferralModel r) async {
    final result = await showAppPopup<_PopupResult>(
      context: context,
      builder: (_) => _ReferralDialog(
        referral: r,
        canEdit: widget.onUpdate != null,
        canSetOutcome: widget.onSetMeetingOutcome != null,
      ),
    );
    if (result == null || !mounted) return;
    switch (result) {
      case _SaveResult(:final status, :final note):
        await _run(() => widget.onUpdate!(r, status: status, note: note),
            'Referral updated.');
      case _OutcomeResult(:final meeting, :final status):
        await _run(() => widget.onSetMeetingOutcome!(meeting, status),
            'Meeting marked ${status.toLowerCase()}.');
    }
  }

  Future<void> _schedule(GuidanceReferralModel r) async {
    final form = await showAppPopup<MeetingFormResult>(
      context: context,
      builder: (_) => const ScheduleMeetingDialog(),
    );
    if (form == null || !mounted) return;
    await _run(() => widget.onScheduleMeeting!(r, form),
        'Meeting scheduled. The invitee has been notified.');
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pageSize = context.cardPageSize;
    final totalPages = filtered.isEmpty ? 1 : (filtered.length / pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageItems =
        filtered.skip((currentPage - 1) * pageSize).take(pageSize).toList();

    final total = widget.referrals.length;
    final waiting = widget.referrals.where((r) => r.status == 'Pending').length;
    final urgent = widget.referrals.where((r) => r.isOpen && r.isUrgent).length;

    final rows = <Widget>[
      for (var i = 0; i < pageItems.length; i++)
        _ReferralRow(
          key: ValueKey('referral-${pageItems[i].id}'),
          referral: pageItems[i],
          showDivider: i < pageItems.length - 1,
          onOpen: () => _open(pageItems[i]),
          onSchedule: widget.onScheduleMeeting == null || !pageItems[i].isOpen
              ? null
              : () => _schedule(pageItems[i]),
        ),
    ];

    return GuidanceTableCard(
      title: 'Referrals',
      subtitle: Text(
        '$total ${total == 1 ? 'referral' : 'referrals'}'
        '${waiting > 0 ? ' | $waiting waiting' : ''}'
        '${urgent > 0 ? ' | $urgent urgent' : ''}',
        style: GuidanceTableCard.subtitleStyle(context),
      ),
      toolbar: Row(
        children: [
          Expanded(
            child: GuidanceSearchField(
              key: const Key('referrals-search'),
              controller: _searchController,
              hint: 'Search student or concern',
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
                  FilterMenuOption(label: 'Pending', value: 'Pending'),
                  FilterMenuOption(label: 'In progress', value: 'In_Progress'),
                  FilterMenuOption(label: 'Closed', value: 'Closed'),
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
        icon: Icons.volunteer_activism_outlined,
        message: widget.referrals.isEmpty
            ? 'No referrals yet'
            : 'No referrals match your search',
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

class _ReferralRow extends StatelessWidget {
  const _ReferralRow({
    super.key,
    required this.referral,
    required this.showDivider,
    required this.onOpen,
    required this.onSchedule,
  });

  final GuidanceReferralModel referral;
  final bool showDivider;
  final VoidCallback onOpen;
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) {
    final r = referral;
    Widget line(String text, TextStyle style) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

    final next = r.nextMeeting;

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
        line(r.sourceLabel, dashboardTableBodyStyle(context)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            line(r.concernLabel, dashboardTableBodyStyle(context)),
            if (r.isUrgent)
              line(
                'Urgent',
                dashboardTableBodyStyle(context).copyWith(
                  color: kDangerTextColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        next == null
            ? line('—', dashboardTableSubStyle(context))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  line(formatDateTime12h(next.scheduledAt),
                      dashboardTableBodyStyle(context)),
                  line('${next.inviteeLabel} · ${next.statusLabel}',
                      dashboardTableSubStyle(context)),
                ],
              ),
        line(formatDateTime12h(r.createdAt), dashboardTableMetaStyle(context)),
        line(r.statusLabel, dashboardTableBodyStyle(context)),
        onSchedule == null
            ? const SizedBox.shrink()
            : GuidanceRowIconButton(
                key: ValueKey('schedule-meeting-${r.id}'),
                icon: Icons.event_outlined,
                tooltip: 'Schedule meeting',
                onPressed: onSchedule,
              ),
      ],
    );
  }
}

class _ReferralDialog extends StatefulWidget {
  const _ReferralDialog({
    required this.referral,
    required this.canEdit,
    required this.canSetOutcome,
  });

  final GuidanceReferralModel referral;
  final bool canEdit;
  final bool canSetOutcome;

  @override
  State<_ReferralDialog> createState() => _ReferralDialogState();
}

class _ReferralDialogState extends State<_ReferralDialog> {
  late String _status = widget.referral.status;
  late final TextEditingController _note =
      TextEditingController(text: widget.referral.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.referral;
    final body = GuidanceTabColors.primaryText(context);
    final muted = GuidanceTabColors.secondaryText(context);

    Widget fact(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11.5, color: muted)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 13.5, color: body)),
            ],
          ),
        );

    return AppPopup(
      title: 'Referral',
      subtitle: '${r.studentName} · ${r.studentNumber}',
      width: 520,
      actions: [
        AppPopupSecondaryButton(
          label: widget.canEdit ? 'Cancel' : 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (widget.canEdit)
          AppPopupPrimaryButton(
            key: const Key('referral-save'),
            label: 'Save',
            onPressed: () => Navigator.of(context)
                .pop(_SaveResult(_status, _note.text.trim())),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          fact('From', r.sourceLabel),
          fact('Concern', r.concernLabel),
          fact('Priority', r.isUrgent ? 'Urgent' : 'Routine'),
          fact('Details', r.details),
          if (r.meetings.isNotEmpty) ...[
            const AppPopupSection('Meetings', icon: Icons.event_outlined),
            for (final m in r.meetings)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatDateTime12h(m.scheduledAt)}'
                      '${(m.location ?? '').isEmpty ? '' : ' · ${m.location}'}',
                      style: TextStyle(fontSize: 13.5, color: body),
                    ),
                    Text('${m.inviteeLabel} · ${m.statusLabel}',
                        style: TextStyle(fontSize: 11.5, color: muted)),
                    if (m.isOpen && widget.canSetOutcome)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final o in _outcomes)
                            TextButton(
                              key: Key('meeting-outcome-${m.id}-$o'),
                              onPressed: () => Navigator.of(context)
                                  .pop(_OutcomeResult(m, o)),
                              child: Text(o == 'Cancelled' ? 'Cancel' : o),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
          if (widget.canEdit) ...[
            const SizedBox(height: 4),
            AppPopupDropdown<String>(
              label: 'Status',
              value: _status,
              items: const [
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(
                    value: 'In_Progress', child: Text('In progress')),
                DropdownMenuItem(value: 'Closed', child: Text('Closed')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _status = v);
              },
            ),
            if (!r.isEndorsement) ...[
              const SizedBox(height: 12),
              AppPopupTextField(
                label: 'Note (visible to the student)',
                controller: _note,
                maxLines: 3,
              ),
            ],
          ] else if ((r.note ?? '').isNotEmpty)
            fact('Note', r.note!),
        ],
      ),
    );
  }
}
