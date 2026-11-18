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

class _ConfirmMeetingResult extends _PopupResult {
  _ConfirmMeetingResult(this.meeting);
  final ReferralMeetingModel meeting;
}

class _ReturnMeetingResult extends _PopupResult {
  _ReturnMeetingResult(this.meeting);
  final ReferralMeetingModel meeting;
}

class _ViewFormResult extends _PopupResult {}

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
    this.onConfirmMeeting,
    this.onReturnMeeting,
    this.onViewForm,
    this.offeredAvailability = const [],
    this.onApproveAvailability,
    this.onDeclineAvailability,
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

  /// Confirms a meeting Student Affairs arranged for an endorsement, then the
  /// invitees are told. [scheduledAt] / [location] are set only when Guidance
  /// changed the proposal. Null hides Confirm.
  final Future<void> Function(
    ReferralMeetingModel meeting, {
    DateTime? scheduledAt,
    String? location,
  })? onConfirmMeeting;

  /// Sends an endorsement meeting back to Student Affairs with a
  /// recommendation. Null hides Return.
  final Future<void> Function(ReferralMeetingModel meeting, String note)?
      onReturnMeeting;

  /// Opens the External Referral Form of a self referral to view and print.
  /// Null hides the action.
  final void Function(ReferralFormDocument document)? onViewForm;

  /// Times parents offered, waiting for a decision. Empty hides the section.
  final List<OfferedAvailability> offeredAvailability;

  /// Approves one offered time ([location] optional). Null hides the section.
  final Future<void> Function(String roundId, String slotId, String? location)?
      onApproveAvailability;

  /// Declines every time offered in a round; the parent is asked again.
  final Future<void> Function(String roundId, String? note)?
      onDeclineAvailability;

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

  /// Like [_run], but a failed availability decision shows a friendly message
  /// rather than the raw error.
  Future<void> _runDecision(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not save your decision. Please try again.')));
    }
  }

  Future<void> _open(GuidanceReferralModel r) async {
    final result = await showAppPopup<_PopupResult>(
      context: context,
      builder: (_) => _ReferralDialog(
        referral: r,
        canEdit: widget.onUpdate != null,
        canSetOutcome: widget.onSetMeetingOutcome != null,
        canViewForm: widget.onViewForm != null,
        canConfirm: widget.onConfirmMeeting != null &&
            widget.onReturnMeeting != null,
      ),
    );
    if (result == null || !mounted) return;
    switch (result) {
      case _ConfirmMeetingResult(:final meeting):
        await _confirm(meeting);
      case _ViewFormResult():
        widget.onViewForm!(r.formDocument);
      case _ReturnMeetingResult(:final meeting):
        await _return(meeting);
      case _SaveResult(:final status, :final note):
        await _run(() => widget.onUpdate!(r, status: status, note: note),
            'Referral updated.');
      case _OutcomeResult(:final meeting, :final status):
        await _run(() => widget.onSetMeetingOutcome!(meeting, status),
            'Meeting marked ${status.toLowerCase()}.');
    }
  }

  /// Confirm the DO's proposal, starting from its time and place; only what
  /// Guidance changed is sent. The invitees are told once it is confirmed.
  Future<void> _confirm(ReferralMeetingModel m) async {
    final form = await showAppPopup<MeetingFormResult>(
      context: context,
      builder: (_) => ScheduleMeetingDialog(
        title: 'Confirm Meeting',
        subtitle: 'The invitees are told once you confirm. Change the time or '
            'place if it does not suit.',
        confirmLabel: 'Confirm and notify',
        initialWhen: m.scheduledAt,
        initialLocation: m.location,
        initialInvitee: m.invitee,
        showInvitee: false,
      ),
    );
    if (form == null || !mounted) return;
    bool sameMinute(DateTime a, DateTime b) =>
        a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        a.hour == b.hour &&
        a.minute == b.minute;
    final movedTime = !sameMinute(form.scheduledAt, m.scheduledAt);
    final movedPlace = (form.location ?? '') != (m.location ?? '');
    await _run(
      () => widget.onConfirmMeeting!(
        m,
        scheduledAt: movedTime ? form.scheduledAt : null,
        location: movedPlace ? form.location : null,
      ),
      'Meeting confirmed. The invitees have been notified.',
    );
  }

  Future<void> _return(ReferralMeetingModel m) async {
    final note = await showAppPopup<String>(
      context: context,
      builder: (_) => const _ReturnMeetingDialog(),
    );
    if (note == null || !mounted) return;
    await _run(() => widget.onReturnMeeting!(m, note),
        'Returned to Student Affairs with your recommendation.');
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
          onSchedule: widget.onScheduleMeeting == null ||
                  !pageItems[i].isOpen ||
                  pageItems[i].isEndorsement
              ? null
              : () => _schedule(pageItems[i]),
        ),
    ];

    final card = GuidanceTableCard(
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

    final showAvailability = widget.offeredAvailability.isNotEmpty &&
        widget.onApproveAvailability != null &&
        widget.onDeclineAvailability != null;
    if (!showAvailability) return card;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ParentAvailabilitySection(
          offered: widget.offeredAvailability,
          onApprove: (r, s, l) => _runDecision(
              () => widget.onApproveAvailability!(r, s, l),
              'Time approved. The parent has been notified.'),
          onDecline: (r, n) => _runDecision(
              () => widget.onDeclineAvailability!(r, n),
              'The parent will be asked for other times.'),
        ),
        const SizedBox(height: 16),
        card,
      ],
    );
  }
}

/// Parent-offered times awaiting Guidance: pick one and approve it, or say
/// none of them work.
class _ParentAvailabilitySection extends StatelessWidget {
  const _ParentAvailabilitySection({
    required this.offered,
    required this.onApprove,
    required this.onDecline,
  });

  final List<OfferedAvailability> offered;
  final Future<void> Function(String roundId, String slotId, String? location)
      onApprove;
  final Future<void> Function(String roundId, String? note) onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GuidanceTabColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GuidanceTabColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parent availability',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: GuidanceTabColors.primaryText(context),
            ),
          ),
          const SizedBox(height: 12),
          for (final o in offered)
            _OfferedRoundTile(
              key: ValueKey('availability-round-${o.roundId}'),
              offered: o,
              onApprove: onApprove,
              onDecline: onDecline,
            ),
        ],
      ),
    );
  }
}

class _OfferedRoundTile extends StatefulWidget {
  const _OfferedRoundTile({
    super.key,
    required this.offered,
    required this.onApprove,
    required this.onDecline,
  });

  final OfferedAvailability offered;
  final Future<void> Function(String roundId, String slotId, String? location)
      onApprove;
  final Future<void> Function(String roundId, String? note) onDecline;

  @override
  State<_OfferedRoundTile> createState() => _OfferedRoundTileState();
}

class _OfferedRoundTileState extends State<_OfferedRoundTile> {
  final _location = TextEditingController();
  final _note = TextEditingController();
  String? _slotId;
  bool _busy = false;

  @override
  void dispose() {
    _location.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      // The host reports the failure; just allow another try.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDecline() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ask the parent for other times?'),
        content: const Text('The parent will be asked to pick other dates '
            'and will receive an SMS.'),
        actions: [
          TextButton(
            key: const Key('availability-decline-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('availability-decline-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ask again'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _guard(
        () => widget.onDecline(widget.offered.roundId, _trimmed(_note)));
  }

  String? _trimmed(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offered;
    final body = GuidanceTabColors.primaryText(context);
    final muted = GuidanceTabColors.secondaryText(context);
    final accent = GuidanceTabColors.primaryAction;
    final title = (o.endorsementTitle ?? '').isEmpty
        ? o.studentName
        : '${o.studentName} · ${o.endorsementTitle}';

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          counterText: '',
          border: const OutlineInputBorder(),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: body)),
          Text(
            o.roundNo > 1
                ? 'Round ${o.roundNo}: the parent offered new times'
                : 'The parent offered these times',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 8),
          for (final s in o.slots)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: Key('availability-slot-${o.roundId}-${s.slotId}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _slotId = s.slotId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _slotId == s.slotId
                            ? accent
                            : GuidanceTabColors.cardBorder(context),
                        width: _slotId == s.slotId ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _slotId == s.slotId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: _slotId == s.slotId ? accent : muted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(formatDateTime12h(s.slotAt),
                              style: TextStyle(fontSize: 13.5, color: body)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          TextField(
            key: Key('availability-location-${o.roundId}'),
            controller: _location,
            maxLength: 120,
            decoration: deco('Location (optional)'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: Key('availability-approve-${o.roundId}'),
              onPressed: _slotId == null || _busy
                  ? null
                  : () => _guard(() => widget.onApprove(
                      o.roundId, _slotId!, _trimmed(_location))),
              child: const Text('Approve selected time'),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    key: Key('availability-busy'), strokeWidth: 2),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            key: Key('availability-note-${o.roundId}'),
            controller: _note,
            maxLength: 500,
            maxLines: 2,
            decoration: deco('Note to the parent (shown in their notification)'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: Key('availability-decline-${o.roundId}'),
              onPressed: _busy ? null : _confirmDecline,
              child: const Text('None of these work'),
            ),
          ),
        ],
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
    required this.canConfirm,
    required this.canViewForm,
  });

  final GuidanceReferralModel referral;
  final bool canEdit;
  final bool canSetOutcome;
  final bool canConfirm;
  final bool canViewForm;

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
          if (r.form != null && r.form!.hasPickedConcerns)
            fact('Specific concerns', r.form!.pickedConcerns.join(', ')),
          if (r.hasReferralForm && widget.canViewForm)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('referral-view-form'),
                onPressed: () => Navigator.of(context).pop(_ViewFormResult()),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('View referral form'),
              ),
            ),
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
                    if (m.status == 'Returned' &&
                        (m.guidanceNote ?? '').isNotEmpty)
                      Text('Your recommendation: ${m.guidanceNote}',
                          style: TextStyle(fontSize: 11.5, color: muted)),
                    if (m.isAwaitingGuidance && widget.canConfirm)
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            key: Key('meeting-confirm-${m.id}'),
                            onPressed: () => Navigator.of(context)
                                .pop(_ConfirmMeetingResult(m)),
                            child: const Text('Confirm'),
                          ),
                          TextButton(
                            key: Key('meeting-return-${m.id}'),
                            onPressed: () => Navigator.of(context)
                                .pop(_ReturnMeetingResult(m)),
                            child: const Text('Return to Student Affairs'),
                          ),
                        ],
                      ),
                    if (m.isOpen && !m.isAwaitingGuidance && widget.canSetOutcome)
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

/// The recommendation Guidance sends back with a meeting it cannot confirm.
class _ReturnMeetingDialog extends StatefulWidget {
  const _ReturnMeetingDialog();

  @override
  State<_ReturnMeetingDialog> createState() => _ReturnMeetingDialogState();
}

class _ReturnMeetingDialogState extends State<_ReturnMeetingDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _note.text.trim().isNotEmpty;
    return AppPopup(
      title: 'Return to Student Affairs',
      subtitle: 'Nobody is invited. Student Affairs will arrange another time.',
      width: 460,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('meeting-return-send'),
          label: 'Return',
          onPressed:
              valid ? () => Navigator.of(context).pop(_note.text.trim()) : null,
        ),
      ],
      body: AppPopupTextField(
        label: 'Your recommendation',
        fieldKey: const Key('meeting-return-note'),
        controller: _note,
        hint: 'e.g. Friday afternoon works better',
        maxLines: 3,
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}
