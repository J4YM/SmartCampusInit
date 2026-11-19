import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/availability_round_info.dart' show EndorsementActionException;
import '../../models/investigation_availability_round.dart';
import '../../theme/discipline_officer_colors.dart';

/// One meeting the officer set up for an investigation, with the invitee's
/// answer (`guidance_meetings`, see supabase/add_guidance_investigations.sql).
class InvestigationMeetingModel {
  const InvestigationMeetingModel({
    required this.id,
    required this.scheduledAt,
    required this.invitee,
    required this.status,
    this.location,
    this.responseNote,
  });

  final String id;
  final DateTime scheduledAt;

  /// `student`, `parent` or `both`.
  final String invitee;

  /// `Proposed`, `Confirmed`, `Declined`, `Reschedule_Requested`, `Completed`,
  /// `Missed` or `Cancelled`.
  final String status;
  final String? location;
  final String? responseNote;

  /// No further changes: it happened, was missed or was cancelled.
  bool get isFinished =>
      status == 'Completed' || status == 'Missed' || status == 'Cancelled';

  /// Still expected to take place.
  bool get isUpcoming =>
      status == 'Proposed' || status == 'Confirmed';

  String get statusLabel => switch (status) {
        'Reschedule_Requested' => 'Reschedule requested',
        _ => status,
      };

  String get inviteeLabel => switch (invitee) {
        'student' => 'Student',
        'parent' => 'Parent',
        _ => 'Student & parent',
      };
}

/// A case under investigation by the Discipline Office.
class InvestigationModel {
  const InvestigationModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.section,
    required this.offenseLabel,
    required this.incidentNotes,
    required this.createdAt,
    required this.status,
    required this.meetings,
    required this.evidencePaths,
    this.offenseCategory,
    this.incidentAt,
    this.findings,
    this.recommendation,
    this.outcome,
    this.violationId,
    this.sanctioned = false,
  });

  final String id;

  /// The violation this investigation belongs to (`student_violations.id`);
  /// the sanction is recorded against it.
  final String? violationId;

  /// A sanction already exists for the violation (`sanctions.violation_id`),
  /// so the verdict is locked and nothing more can be recorded.
  final bool sanctioned;
  final String studentName;
  final String studentNumber;
  final String section;
  final String offenseLabel;
  final String? offenseCategory;
  final String incidentNotes;
  final DateTime? incidentAt;
  final DateTime createdAt;

  /// `Open` or `Complete`.
  final String status;
  final List<InvestigationMeetingModel> meetings;
  final List<String> evidencePaths;
  final String? findings;
  final String? recommendation;

  /// `Proven` or `Not_Proven`; null until the investigation is completed.
  final String? outcome;

  bool get isOpen => status == 'Open';

  /// Completed with a `Proven` verdict and no sanction yet.
  bool get canSanction => !isOpen && outcome == 'Proven' && !sanctioned;

  /// The verdict can still be changed: completed, has one, nothing sanctioned.
  bool get canChangeOutcome => !isOpen && outcome != null && !sanctioned;

  /// An open investigation with no meeting still expected to happen.
  bool get needsMeeting => isOpen && !meetings.any((m) => m.isUpcoming);
}

const double _kActionColumnWidth = 176;

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('Violation', flex: 4, minWidth: 220),
  DashboardTableColumn('Meeting', flex: 4, minWidth: 210),
  DashboardTableColumn('Status', flex: 2, minWidth: 110),
  DashboardTableColumn('', width: _kActionColumnWidth, sticky: true),
];

/// The Discipline Officer's "Investigations" tab: cases under investigation.
/// For each, the officer schedules a meeting with the student and/or parent
/// (who confirm or decline from their own dashboard), records how it went,
/// and files findings, after which the case can be sanctioned.
///
/// A table like every other DO tab; a row (or its eye button) opens the
/// whole case — incident, photo evidence, meetings and findings — in a popup.
class InvestigationsView extends StatefulWidget {
  const InvestigationsView({
    super.key,
    required this.investigations,
    this.onSchedule,
    this.onSetMeetingOutcome,
    this.onComplete,
    this.onChangeOutcome,
    this.onRecordSanction,
    this.onLoadEvidence,
    this.availabilityRounds,
    this.onRequestAvailability,
    this.onCancelAvailability,
    this.onApproveAvailability,
    this.onDeclineAvailability,
  });

  final List<InvestigationModel> investigations;

  /// The latest availability round per investigation id. Null means they could
  /// not be loaded: the availability actions are then not offered and the
  /// officer schedules directly.
  final Map<String, InvestigationAvailabilityRound>? availabilityRounds;

  /// Asks the parent when they are free. Null hides the availability flow.
  final Future<void> Function(InvestigationModel investigation)?
      onRequestAvailability;

  /// Cancels a request still waiting on the parent.
  final Future<void> Function(String roundId)? onCancelAvailability;

  /// Approves one offered time: the meeting is proposed to the parent.
  final Future<void> Function(String roundId, String slotId, String? location)?
      onApproveAvailability;

  /// Declines every offered time; the parent is asked for others.
  final Future<void> Function(String roundId, String? note)?
      onDeclineAvailability;

  /// Schedules a meeting: when, where (nullable) and who (`student`,
  /// `parent`, `both`). Null makes the tab read-only (demo).
  final Future<void> Function(
    InvestigationModel investigation,
    DateTime scheduledAt,
    String? location,
    String invitee,
  )? onSchedule;

  /// Marks a meeting `Completed`, `Missed` or `Cancelled`.
  final Future<void> Function(InvestigationMeetingModel meeting, String status)?
      onSetMeetingOutcome;

  /// Files findings (and an optional recommendation) and the verdict
  /// (`Proven` or `Not_Proven`) and completes the case.
  final Future<void> Function(
    InvestigationModel investigation,
    String findings,
    String? recommendation,
    String outcome,
  )? onComplete;

  /// Changes the verdict (`Proven` / `Not_Proven`) of a completed
  /// investigation that has not been sanctioned yet.
  final Future<void> Function(InvestigationModel investigation, String outcome)?
      onChangeOutcome;

  /// Opens the existing sanction form for a `Proven` investigation and records
  /// the sanction. The host shows the form; null hides the action.
  final Future<void> Function(InvestigationModel investigation)?
      onRecordSanction;

  /// Signed viewing links for evidence photos, keyed by storage path.
  final Future<Map<String, String>> Function(List<String> paths)?
      onLoadEvidence;

  @override
  State<InvestigationsView> createState() => _InvestigationsViewState();
}

/// What the details popup asks the tab to do once it closes.
typedef _DetailResult = ({
  String kind, // 'schedule' | 'complete' | 'outcome' | 'verdict' | 'sanction'
  InvestigationMeetingModel? meeting,
  String? status,
});

class _InvestigationsViewState extends State<InvestigationsView> {
  final _search = TextEditingController();
  String _query = '';

  /// `Open` or `Complete`; null = every investigation.
  String? _statusFilter;
  int _currentPage = 1;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Open before complete, then newest first.
  List<InvestigationModel> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = widget.investigations.where((i) {
      if (_statusFilter == 'Open' && !i.isOpen) return false;
      if (_statusFilter == 'Complete' && i.isOpen) return false;
      if (q.isEmpty) return true;
      return i.studentName.toLowerCase().contains(q) ||
          i.studentNumber.toLowerCase().contains(q) ||
          i.offenseLabel.toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  Future<void> _run(
    Future<void> Function() action,
    String done, {
    String failure = 'Something went wrong. Please try again.',
  }) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      debugPrint('Investigation action failed: $e');
      messenger.showSnackBar(SnackBar(
          content: Text(e is EndorsementActionException ? e.message : failure)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _schedule(InvestigationModel inv) async {
    final result = await showAppPopup<MeetingFormResult>(
      context: context,
      builder: (_) => const ScheduleMeetingDialog(),
    );
    final onSchedule = widget.onSchedule;
    if (result == null || onSchedule == null || !mounted) return;
    await _run(
      () => onSchedule(inv, result.scheduledAt, result.location, result.invitee),
      'Meeting scheduled. The invitee has been notified.',
    );
  }

  bool get _availabilityEnabled =>
      widget.onRequestAvailability != null && widget.availabilityRounds != null;

  Future<void> _requestAvailability(InvestigationModel inv) => _run(
        () => widget.onRequestAvailability!(inv),
        'The parent has been asked for their availability.',
        failure: 'Could not request the parent availability. Please try again.',
      );

  Future<void> _cancelAvailability(InvestigationAvailabilityRound round) =>
      _run(
        () => widget.onCancelAvailability!(round.roundId),
        'The availability request was cancelled.',
      );

  Future<void> _reviewAvailability(
    InvestigationModel inv,
    InvestigationAvailabilityRound round,
  ) async {
    final result = await showAppPopup<_AvailabilityDecision>(
      context: context,
      builder: (_) => _ReviewOfferedTimesDialog(
        studentName: inv.studentName,
        round: round,
      ),
    );
    if (result == null || !mounted) return;
    if (result.slotId == null) {
      await _run(
        () => widget.onDeclineAvailability!(round.roundId, result.note),
        'The parent has been asked for other times.',
      );
    } else {
      await _run(
        () => widget.onApproveAvailability!(
            round.roundId, result.slotId!, result.location),
        'Meeting scheduled. The parent has been notified.',
      );
    }
  }

  Future<void> _complete(InvestigationModel inv) async {
    final result = await showAppPopup<
        ({String findings, String? recommendation, String outcome})>(
      context: context,
      builder: (_) => CompleteInvestigationDialog(studentName: inv.studentName),
    );
    final onComplete = widget.onComplete;
    if (result == null || onComplete == null || !mounted) return;
    await _run(
      () => onComplete(
          inv, result.findings, result.recommendation, result.outcome),
      result.outcome == 'Proven'
          ? 'Investigation complete. You can now sanction the case.'
          : 'Investigation complete. Marked as not proven.',
      failure: 'Could not complete the investigation. Please try again.',
    );
  }

  Future<void> _changeOutcome(InvestigationModel inv, String outcome) async {
    final onChange = widget.onChangeOutcome;
    if (onChange == null) return;
    await _run(
      () => onChange(inv, outcome),
      outcome == 'Proven'
          ? 'Verdict changed to proven.'
          : 'Verdict changed to not proven.',
      failure: 'Could not change the verdict. Please try again.',
    );
  }

  Future<void> _recordSanction(InvestigationModel inv) async {
    final onRecord = widget.onRecordSanction;
    if (onRecord == null) return;
    // The host opens the sanction form and shows its own result messages.
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await onRecord(inv);
    } catch (e) {
      debugPrint('Recording the sanction failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not record the sanction. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _outcome(InvestigationMeetingModel m, String status) async {
    final onOutcome = widget.onSetMeetingOutcome;
    if (onOutcome == null) return;
    await _run(() => onOutcome(m, status),
        'Meeting marked ${status.toLowerCase()}.');
  }

  Future<void> _openDetails(InvestigationModel inv) async {
    final result = await showAppPopup<_DetailResult>(
      context: context,
      builder: (_) => _InvestigationDetailDialog(
        investigation: inv,
        canSchedule: widget.onSchedule != null,
        canComplete: widget.onComplete != null,
        canEditMeetings: widget.onSetMeetingOutcome != null,
        canChangeOutcome: widget.onChangeOutcome != null,
        canSanction: widget.onRecordSanction != null,
        onLoadEvidence: widget.onLoadEvidence,
      ),
    );
    if (result == null || !mounted) return;
    switch (result.kind) {
      case 'verdict':
        await _changeOutcome(inv, result.status!);
      case 'sanction':
        await _recordSanction(inv);
      case 'schedule':
        await _schedule(inv);
      case 'complete':
        await _complete(inv);
      case 'outcome':
        await _outcome(result.meeting!, result.status!);
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

    final total = widget.investigations.length;
    final open = widget.investigations.where((i) => i.isOpen).length;
    final needMeeting =
        widget.investigations.where((i) => i.needsMeeting).length;

    final rows = <Widget>[
      for (var i = 0; i < pageItems.length; i++)
        _InvestigationRow(
          key: ValueKey('investigation-${pageItems[i].id}'),
          investigation: pageItems[i],
          showDivider: i < pageItems.length - 1,
          busy: _busy,
          onOpen: () => _openDetails(pageItems[i]),
          availability: _availabilityEnabled
              ? widget.availabilityRounds![pageItems[i].id]
              : null,
          availabilityEnabled:
              _availabilityEnabled && pageItems[i].needsMeeting,
          onRequestAvailability: () => _requestAvailability(pageItems[i]),
          onCancelAvailability: widget.onCancelAvailability == null
              ? null
              : (round) => _cancelAvailability(round),
          onReviewAvailability:
              widget.onApproveAvailability == null ||
                      widget.onDeclineAvailability == null
                  ? null
                  : (round) => _reviewAvailability(pageItems[i], round),
          onSchedule: widget.onSchedule != null &&
                  pageItems[i].needsMeeting &&
                  !(_availabilityEnabled &&
                      (widget.availabilityRounds![pageItems[i].id]?.isLive ??
                          false))
              ? () => _schedule(pageItems[i])
              : null,
          scheduleTooltip: pageItems[i].meetings.isEmpty
              ? 'Schedule meeting'
              : 'Reschedule meeting',
          onComplete: widget.onComplete != null && pageItems[i].isOpen
              ? () => _complete(pageItems[i])
              : null,
          onRecordSanction:
              widget.onRecordSanction != null && pageItems[i].canSanction
                  ? () => _recordSanction(pageItems[i])
                  : null,
        ),
    ];

    return TitledTableCard(
      title: 'Investigations',
      subtitle: Text(
        '$total ${total == 1 ? 'investigation' : 'investigations'}'
        ' | $open open'
        '${needMeeting > 0 ? ' | $needMeeting need a meeting' : ''}',
        style: TitledTableCard.subtitleStyle(context,
            color: DisciplineOfficerColors.placeholderText(context)),
      ),
      toolbar: Row(
        children: [
          Expanded(
            child: DashboardSearchField(
              key: const Key('investigations-search'),
              controller: _search,
              hint: 'Search student or violation',
              fillColor: DisciplineOfficerColors.background(context),
              textColor: DisciplineOfficerColors.rowText(context),
              hintColor: DisciplineOfficerColors.placeholderText(context),
              onChanged: (v) => setState(() {
                _query = v;
                _currentPage = 1;
              }),
            ),
          ),
          const SizedBox(width: 10),
          FilterMenuButton(
            key: const Key('investigations-filter'),
            compact: true,
            backgroundColor: DisciplineOfficerColors.background(context),
            menuColor: DisciplineOfficerColors.card(context),
            borderColor: DisciplineOfficerColors.cardBorder(context),
            iconColor: DisciplineOfficerColors.placeholderText(context),
            textColor: DisciplineOfficerColors.rowText(context),
            mutedTextColor: DisciplineOfficerColors.placeholderText(context),
            accentColor: DisciplineOfficerColors.azureBlue,
            sections: [
              FilterMenuSection(
                title: 'Status',
                options: const [
                  FilterMenuOption(label: 'Open', value: 'Open'),
                  FilterMenuOption(label: 'Complete', value: 'Complete'),
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
        icon: Icons.manage_search_rounded,
        message: widget.investigations.isEmpty
            ? 'No investigations yet'
            : 'No investigations match your search',
      ),
      footer: filtered.isEmpty
          ? null
          : CardPaginationFooter(
              currentPage: currentPage,
              totalPages: totalPages,
              totalCount: filtered.length,
              textColor: DisciplineOfficerColors.placeholderText(context),
              accentColor: DisciplineOfficerColors.azureBlue,
              mutedBackground: DisciplineOfficerColors.background(context),
              onPrevious: () => setState(() => _currentPage = currentPage - 1),
              onNext: () => setState(() => _currentPage = currentPage + 1),
            ),
      backgroundColor: DisciplineOfficerColors.card(context),
      borderColor: DisciplineOfficerColors.cardBorder(context),
      titleColor: DisciplineOfficerColors.rowText(context),
    );
  }
}

/// A soft status pill — the same look as the Escalation / Referral badges
/// (pill radius, 14% tint of its color, 11px w600).
class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label, this.color, {super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// "Proven" / "Not proven" verdict pill.
class _OutcomeBadge extends StatelessWidget {
  const _OutcomeBadge(this.outcome, {super.key});

  final String outcome;

  @override
  Widget build(BuildContext context) => outcome == 'Proven'
      ? const _StatusPill('Proven', _red)
      : const _StatusPill('Not proven', _slate);
}

const _green = Color(0xFF2E9E6A);
const _red = Color(0xFFCD4855);
const _amber = Color(0xFFD97706);
const _slate = Color(0xFF64748B);

Color _meetingColor(String status) => switch (status) {
      'Confirmed' || 'Completed' => _green,
      'Declined' || 'Missed' || 'Cancelled' => _red,
      'Reschedule_Requested' => _amber,
      _ => _slate,
    };

class _InvestigationRow extends StatelessWidget {
  const _InvestigationRow({
    super.key,
    required this.investigation,
    required this.showDivider,
    required this.busy,
    required this.onOpen,
    required this.onSchedule,
    required this.scheduleTooltip,
    required this.onComplete,
    required this.onRecordSanction,
    this.availability,
    this.availabilityEnabled = false,
    this.onRequestAvailability,
    this.onCancelAvailability,
    this.onReviewAvailability,
  });

  final InvestigationModel investigation;

  /// The latest availability round, when the flow is wired.
  final InvestigationAvailabilityRound? availability;

  /// The availability flow applies to this row (wired, open, needs a meeting).
  final bool availabilityEnabled;
  final VoidCallback? onRequestAvailability;
  final void Function(InvestigationAvailabilityRound round)?
      onCancelAvailability;
  final void Function(InvestigationAvailabilityRound round)?
      onReviewAvailability;
  final bool showDivider;
  final bool busy;
  final VoidCallback onOpen;

  /// Null hides the button (not Proven, already sanctioned, or read-only).
  final VoidCallback? onRecordSanction;

  /// Null hides the button (read-only, or a meeting is already pending).
  final VoidCallback? onSchedule;
  final String scheduleTooltip;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final inv = investigation;
    Widget line(String text, TextStyle style) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

    // The most recent meeting stands for the case: when it is and how the
    // invitee answered.
    InvestigationMeetingModel? latest;
    for (final m in inv.meetings) {
      if (latest == null || m.scheduledAt.isAfter(latest.scheduledAt)) latest = m;
    }

    return DashboardTableRow(
      columns: _columns,
      showDivider: showDivider,
      onTap: onOpen,
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            line(inv.studentName, dashboardTablePrimaryStyle(context)),
            line('${inv.studentNumber} · ${inv.section}',
                dashboardTableSubStyle(context)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            line(inv.offenseLabel, dashboardTableBodyStyle(context)),
            if (inv.incidentAt != null)
              line(formatDateTime12h(inv.incidentAt!),
                  dashboardTableMetaStyle(context)),
          ],
        ),
        if (latest == null && availability != null && availability!.isOpen)
          line("Waiting for the parent's times", dashboardTableMetaStyle(context))
        else if (latest == null &&
            availability != null &&
            availability!.isOffered)
          line('Parent offered ${availability!.offeredTimes.length} time(s)',
              dashboardTableMetaStyle(context))
        else if (latest == null)
          line('No meeting yet', dashboardTableMetaStyle(context))
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              line(formatDateTime12h(latest.scheduledAt),
                  dashboardTableBodyStyle(context)),
              const SizedBox(height: 3),
              _StatusPill(latest.statusLabel, _meetingColor(latest.status),
                  key: Key('meeting-status-${latest.id}')),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusPill(
                inv.isOpen ? 'Open' : 'Complete',
                inv.isOpen ? _amber : _green,
              ),
              if (!inv.isOpen && inv.outcome != null) ...[
                const SizedBox(height: 3),
                _OutcomeBadge(inv.outcome!, key: Key('outcome-badge-${inv.id}')),
              ],
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DashboardRowIconButton(
                key: ValueKey('investigation-view-${inv.id}'),
                icon: Icons.visibility_outlined,
                tooltip: 'View case',
                onPressed: onOpen,
              ),
              if (availabilityEnabled &&
                  (availability == null || !availability!.isLive) &&
                  onRequestAvailability != null)
                DashboardRowIconButton(
                  key: Key('request-availability-${inv.id}'),
                  icon: Icons.mark_email_read_outlined,
                  tooltip: 'Request parent availability',
                  onPressed: busy ? null : onRequestAvailability,
                ),
              if (availabilityEnabled &&
                  availability != null &&
                  availability!.isOffered &&
                  onReviewAvailability != null)
                DashboardRowIconButton(
                  key: Key('review-availability-${inv.id}'),
                  icon: Icons.event_note_outlined,
                  tooltip: 'Review the times the parent offered',
                  onPressed: busy ? null : () => onReviewAvailability!(availability!),
                ),
              if (availabilityEnabled &&
                  availability != null &&
                  availability!.isLive &&
                  onCancelAvailability != null)
                DashboardRowIconButton(
                  key: Key('cancel-availability-${inv.id}'),
                  icon: Icons.cancel_outlined,
                  tooltip: 'Cancel the availability request',
                  onPressed: busy ? null : () => onCancelAvailability!(availability!),
                ),
              if (onSchedule != null)
                DashboardRowIconButton(
                  key: Key('schedule-meeting-${inv.id}'),
                  icon: Icons.event_available_outlined,
                  tooltip: scheduleTooltip,
                  onPressed: busy ? null : onSchedule,
                ),
              if (onComplete != null)
                DashboardRowIconButton(
                  key: Key('complete-investigation-${inv.id}'),
                  icon: Icons.task_alt_rounded,
                  tooltip: 'Complete investigation',
                  onPressed: busy ? null : onComplete,
                ),
              if (onRecordSanction != null)
                DashboardRowIconButton(
                  key: Key('record-sanction-${inv.id}'),
                  icon: Icons.gavel_rounded,
                  tooltip: 'Record sanction',
                  onPressed: busy ? null : onRecordSanction,
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

/// The whole case: incident and notes, photo evidence, every meeting with the
/// invitee's answer, and — once complete — the findings.
class _InvestigationDetailDialog extends StatefulWidget {
  const _InvestigationDetailDialog({
    required this.investigation,
    required this.canSchedule,
    required this.canComplete,
    required this.canEditMeetings,
    required this.canChangeOutcome,
    required this.canSanction,
    required this.onLoadEvidence,
  });

  final InvestigationModel investigation;
  final bool canSchedule;
  final bool canComplete;
  final bool canEditMeetings;
  final bool canChangeOutcome;
  final bool canSanction;
  final Future<Map<String, String>> Function(List<String> paths)?
      onLoadEvidence;

  @override
  State<_InvestigationDetailDialog> createState() =>
      _InvestigationDetailDialogState();
}

class _InvestigationDetailDialogState
    extends State<_InvestigationDetailDialog> {
  Map<String, String> _urls = const {};

  @override
  void initState() {
    super.initState();
    _loadEvidence();
  }

  Future<void> _loadEvidence() async {
    final loader = widget.onLoadEvidence;
    final paths = widget.investigation.evidencePaths;
    if (loader == null || paths.isEmpty) return;
    try {
      final urls = await loader(paths);
      if (mounted) setState(() => _urls = urls);
    } catch (e) {
      debugPrint('Could not load evidence photos: $e');
    }
  }

  void _close(String kind, {InvestigationMeetingModel? meeting, String? status}) =>
      Navigator.of(context).pop<_DetailResult>(
          (kind: kind, meeting: meeting, status: status));

  @override
  Widget build(BuildContext context) {
    final inv = widget.investigation;
    final c = AppPopupColors.of(context);
    final open = inv.isOpen;
    final meetings = [...inv.meetings]
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

    TextStyle text({double size = 12.5, FontWeight? weight, Color? color}) =>
        GoogleFonts.poppins(
            fontSize: size, fontWeight: weight, color: color ?? c.text);

    return AppPopup(
      title: 'Investigation',
      subtitle: '${inv.studentName} · ${inv.studentNumber} · ${inv.section}',
      width: 580,
      actions: [
        AppPopupSecondaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (open && widget.canSchedule && inv.needsMeeting)
          AppPopupSecondaryButton(
            key: const Key('detail-schedule'),
            label: inv.meetings.isEmpty ? 'Schedule meeting' : 'Reschedule meeting',
            icon: Icons.event_available_outlined,
            onPressed: () => _close('schedule'),
          ),
        if (open && widget.canComplete)
          AppPopupPrimaryButton(
            key: const Key('detail-complete'),
            label: 'Complete investigation',
            icon: Icons.task_alt_rounded,
            onPressed: () => _close('complete'),
          ),
        if (inv.canChangeOutcome && widget.canChangeOutcome)
          AppPopupSecondaryButton(
            key: const Key('detail-change-outcome'),
            label: inv.outcome == 'Proven'
                ? 'Change to not proven'
                : 'Change to proven',
            icon: Icons.swap_horiz_rounded,
            onPressed: () => _close('verdict',
                status: inv.outcome == 'Proven' ? 'Not_Proven' : 'Proven'),
          ),
        if (inv.canSanction && widget.canSanction)
          AppPopupPrimaryButton(
            key: const Key('detail-record-sanction'),
            label: 'Record sanction',
            icon: Icons.gavel_rounded,
            onPressed: () => _close('sanction'),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppPopupSection('Incident', icon: Icons.report_gmailerrorred_outlined),
          Text(inv.offenseLabel,
              style: text(size: 13, weight: FontWeight.w600)),
          if (inv.incidentAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Incident: ${formatDateTime12h(inv.incidentAt!)}',
                  style: text(size: 11.5, color: c.muted)),
            ),
          if (inv.incidentNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(inv.incidentNotes, style: text()),
            ),
          if (inv.evidencePaths.isNotEmpty) ...[
            const SizedBox(height: 14),
            AppPopupSection('Photo evidence (${inv.evidencePaths.length})',
                icon: Icons.photo_library_outlined),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in inv.evidencePaths) _Thumb(url: _urls[p]),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const AppPopupSection('Meetings', icon: Icons.event_outlined),
          if (meetings.isEmpty)
            Text('No meeting scheduled yet.',
                style: text(color: c.muted))
          else
            for (final m in meetings)
              _MeetingRow(
                meeting: m,
                canEdit: open && widget.canEditMeetings,
                onOutcome: (s) => _close('outcome', meeting: m, status: s),
              ),
          if (!open && (inv.findings ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            const AppPopupSection('Findings', icon: Icons.fact_check_outlined),
            if (inv.outcome != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _OutcomeBadge(inv.outcome!,
                      key: Key('detail-outcome-${inv.id}')),
                ),
              ),
            Text(inv.findings!, style: text()),
            if ((inv.recommendation ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Recommendation: ${inv.recommendation}',
                    style: text(size: 12, color: c.muted)),
              ),
          ],
        ],
      ),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({
    required this.meeting,
    required this.canEdit,
    required this.onOutcome,
  });

  final InvestigationMeetingModel meeting;
  final bool canEdit;
  final ValueChanged<String> onOutcome;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final note = (meeting.responseNote ?? '').trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.fieldFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDateTime12h(meeting.scheduledAt) +
                      (meeting.location == null ? '' : ' · ${meeting.location}'),
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: c.text),
                ),
                Text('Invited: ${meeting.inviteeLabel}',
                    style: GoogleFonts.poppins(fontSize: 11.5, color: c.muted)),
                if (note.isNotEmpty)
                  Text('Reply: $note',
                      style: GoogleFonts.poppins(fontSize: 11.5, color: c.muted)),
                // Under the details (not beside them), so a long status such as
                // "Reschedule requested" never squeezes the text on a phone.
                const SizedBox(height: 6),
                _StatusPill(meeting.statusLabel, _meetingColor(meeting.status)),
              ],
            ),
          ),
          if (canEdit && !meeting.isFinished)
            PopupMenuButton<String>(
              key: Key('meeting-menu-${meeting.id}'),
              tooltip: 'Meeting outcome',
              icon: Icon(Icons.more_vert_rounded, size: 20, color: c.muted),
              color: c.card,
              onSelected: onOutcome,
              itemBuilder: (_) => [
                for (final (value, label) in const [
                  ('Completed', 'Mark completed'),
                  ('Missed', 'Mark missed'),
                  ('Cancelled', 'Cancel meeting'),
                ])
                  PopupMenuItem(
                    value: value,
                    child: Text(label,
                        style: GoogleFonts.poppins(fontSize: 13, color: c.text)),
                  ),
              ],
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final placeholder = Container(
      width: 80,
      height: 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.fieldFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.image_outlined, color: c.muted),
    );
    final link = url;
    if (link == null) return placeholder;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showAppPopup<void>(
        context: context,
        builder: (dialogContext) => AppPopup(
          title: 'Photo evidence',
          width: 640,
          actions: [
            AppPopupSecondaryButton(
              label: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
          body: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: InteractiveViewer(child: Image.network(link)),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(link,
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder),
      ),
    );
  }
}

/// File findings (required) and an optional recommendation to complete the
/// investigation.
class CompleteInvestigationDialog extends StatefulWidget {
  const CompleteInvestigationDialog({super.key, required this.studentName});

  final String studentName;

  @override
  State<CompleteInvestigationDialog> createState() =>
      _CompleteInvestigationDialogState();
}

class _CompleteInvestigationDialogState
    extends State<CompleteInvestigationDialog> {
  final _findings = TextEditingController();
  final _recommendation = TextEditingController();

  /// `Proven` or `Not_Proven`; null until the officer chooses (no default).
  String? _outcome;
  bool _submitted = false;

  @override
  void dispose() {
    _findings.dispose();
    _recommendation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _findings.text.trim().isNotEmpty && _outcome != null;
    final c = AppPopupColors.of(context);
    Widget choice(Key key, String label, String value) => ChoiceChip(
          key: key,
          label: Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _outcome == value ? Colors.white : c.text)),
          selected: _outcome == value,
          showCheckmark: false,
          selectedColor: DisciplineOfficerColors.azureBlue,
          backgroundColor: c.fieldFill,
          onSelected: (_) => setState(() => _outcome = value),
        );
    return AppPopup(
      title: 'Complete Investigation',
      subtitle: '${widget.studentName} · findings go back to the Discipline Officer',
      width: 520,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('complete-save'),
          label: 'Complete',
          onPressed: canSave
              ? () {
                  // A double tap would pop twice; pop once only.
                  if (_submitted) return;
                  _submitted = true;
                  final rec = _recommendation.text.trim();
                  Navigator.of(context).pop((
                    findings: _findings.text.trim(),
                    recommendation: rec.isEmpty ? null : rec,
                    outcome: _outcome!,
                  ));
                }
              : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppPopupTextField(
            label: 'Findings',
            fieldKey: const Key('findings-field'),
            controller: _findings,
            minLines: 4,
            maxLines: 7,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text('Verdict (required)',
              style: GoogleFonts.poppins(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              choice(const Key('outcome-proven'), 'Proven', 'Proven'),
              choice(const Key('outcome-not-proven'), 'Not proven', 'Not_Proven'),
            ],
          ),
          const SizedBox(height: 12),
          AppPopupTextField(
            label: 'Recommendation (optional)',
            fieldKey: const Key('recommendation-field'),
            controller: _recommendation,
            minLines: 2,
            maxLines: 4,
          ),
        ],
      ),
    );
  }
}

/// What the review dialog decided: approve [slotId] (at [location]) or, with no
/// slot, decline every offered time with [note].
typedef _AvailabilityDecision = ({
  String? slotId,
  String? location,
  String? note,
});

/// The times the parent offered for an investigation meeting. The officer picks
/// one (and where it is held) to approve, or declines them all.
class _ReviewOfferedTimesDialog extends StatefulWidget {
  const _ReviewOfferedTimesDialog({
    required this.studentName,
    required this.round,
  });

  final String studentName;
  final InvestigationAvailabilityRound round;

  @override
  State<_ReviewOfferedTimesDialog> createState() =>
      _ReviewOfferedTimesDialogState();
}

class _ReviewOfferedTimesDialogState extends State<_ReviewOfferedTimesDialog> {
  String? _slotId;
  final _location = TextEditingController(text: 'Guidance Office');
  final _note = TextEditingController();

  @override
  void dispose() {
    _location.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _trimmed(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    final body = DisciplineOfficerColors.rowText(context);
    final muted = DisciplineOfficerColors.placeholderText(context);

    return AppPopup(
      title: 'Times the parent offered',
      subtitle: widget.studentName,
      width: 520,
      actions: [
        AppPopupSecondaryButton(
          key: const Key('availability-decline'),
          label: 'Decline all times',
          onPressed: () => Navigator.of(context)
              .pop((slotId: null, location: null, note: _trimmed(_note))),
        ),
        AppPopupPrimaryButton(
          key: const Key('availability-approve'),
          label: 'Approve selected time',
          onPressed: _slotId == null
              ? null
              : () => Navigator.of(context).pop(
                  (slotId: _slotId, location: _trimmed(_location), note: null)),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Pick the time for the meeting. The parent is told, and can '
              'still confirm or decline it.',
              style: TextStyle(fontSize: 12.5, color: muted)),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _slotId,
            onChanged: (v) => setState(() => _slotId = v),
            child: Column(
              children: [
                for (final t in widget.round.offeredTimes)
                  RadioListTile<String>(
                    key: Key('availability-slot-${t.id}'),
                    value: t.id,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(formatDateTime12h(t.at),
                        style: TextStyle(fontSize: 13.5, color: body)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AppPopupTextField(
            key: const Key('availability-location'),
            label: 'Where',
            controller: _location,
          ),
          const SizedBox(height: 12),
          AppPopupTextField(
            key: const Key('availability-note'),
            label: 'Note to the parent if you decline all times (optional)',
            controller: _note,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
