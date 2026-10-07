import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_popup.dart';
import 'bento_card.dart';
import 'brightness_x.dart';
import 'control_metrics.dart';
import 'dashboard_table.dart';
import 'responsive_x.dart';
import 'secondary_pill_button.dart';
import 'time_format.dart';

/// One item the kiosk's server refused while replaying its offline queue,
/// reported to `kiosk_sync_failures` (supabase/add_kiosk_sync_failures.sql).
///
/// Lives here, not in the app, so the IT Technician and Admin dashboards —
/// which share only this package — can render the same panel.
class KioskSyncFailure {
  const KioskSyncFailure({
    required this.id,
    required this.readerUsbSerial,
    required this.kind,
    required this.occurredAt,
    required this.reason,
    required this.reportedAt,
    required this.isOpen,
    this.rfidUid,
    this.studentName,
    this.dismissedAt,
    this.dismissedBy,
    this.dismissNote,
  });

  final String id;
  final String readerUsbSerial;

  /// `'tap'` (a card tap) or `'slip'` (a violation report).
  final String kind;

  /// When it happened on the kiosk.
  final DateTime occurredAt;

  /// The server's refusal message, verbatim.
  final String reason;
  final DateTime reportedAt;
  final bool isOpen;
  final String? rfidUid;
  final String? studentName;
  final DateTime? dismissedAt;
  final String? dismissedBy;
  final String? dismissNote;

  String get kindLabel => kind == 'slip' ? 'Violation report' : 'Card tap';

  /// From one `kiosk_sync_failures` row (snake_case, as PostgREST returns it).
  factory KioskSyncFailure.fromJson(Map<String, dynamic> row) {
    DateTime? time(String key) {
      final raw = row[key] as String?;
      return raw == null ? null : DateTime.tryParse(raw);
    }

    String? text(String key) {
      final v = (row[key] as String?)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    final reported = time('reported_at') ?? DateTime.now();
    return KioskSyncFailure(
      id: row['id'] as String,
      readerUsbSerial: text('reader_usb_serial') ?? 'Unknown kiosk',
      kind: row['kind'] == 'slip' ? 'slip' : 'tap',
      occurredAt: time('occurred_at') ?? reported,
      reason: text('reason') ?? 'Rejected by the server.',
      reportedAt: reported,
      isOpen: row['status'] != 'dismissed',
      rfidUid: text('rfid_uid'),
      studentName: text('student_name'),
      dismissedAt: time('dismissed_at'),
      dismissedBy: text('dismissed_by'),
      dismissNote: text('dismiss_note'),
    );
  }
}

/// Review and dismiss kiosk sync failures. The kiosk itself has no clear
/// button (by design); once an item is dismissed here the kiosk drops its
/// local copy on its next sync and its "N failed" chip clears.
///
/// Data and actions come in as callbacks so this package stays free of
/// Supabase/app code.
class KioskSyncFailuresPanel extends StatefulWidget {
  const KioskSyncFailuresPanel({
    super.key,
    required this.loadFailures,
    required this.onDismiss,
  });

  /// Open AND recently dismissed items, newest first.
  final Future<List<KioskSyncFailure>> Function() loadFailures;

  /// Dismisses [ids] with an optional [note]. Throws on failure.
  final Future<void> Function(List<String> ids, String? note) onDismiss;

  @override
  State<KioskSyncFailuresPanel> createState() => _KioskSyncFailuresPanelState();
}

abstract final class _Colors {
  static Color primaryText(BuildContext c) =>
      c.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext c) =>
      c.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
  static Color chipFill(BuildContext c, bool selected) => selected
      ? (c.isDarkMode ? const Color(0xFF2E313A) : const Color(0xFFE2E8F0))
      : Colors.transparent;
  static const danger = Color(0xFFB91C1C);
}

class _KioskSyncFailuresPanelState extends State<KioskSyncFailuresPanel> {
  static const _columns = <DashboardTableColumn>[
    DashboardTableColumn('When', flex: 3),
    DashboardTableColumn('Student', flex: 3),
    DashboardTableColumn('Kiosk', flex: 2),
    DashboardTableColumn('Type', flex: 2),
    DashboardTableColumn('Why it failed', flex: 5),
    DashboardTableColumn('Action', flex: 3),
  ];
  static const _minTableWidth = 1040.0;

  List<KioskSyncFailure> _items = const [];
  bool _loading = true;
  Object? _error;
  bool _showDismissed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.loadFailures();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<KioskSyncFailure> get _open =>
      [for (final f in _items) if (f.isOpen) f];
  List<KioskSyncFailure> get _visible =>
      [for (final f in _items) if (f.isOpen != _showDismissed) f];

  /// Asks for an optional note, then dismisses [targets].
  Future<void> _dismiss(List<KioskSyncFailure> targets, {required bool all}) async {
    if (targets.isEmpty || _busy) return;
    final result = await showAppPopup<_DismissResult>(
      context: context,
      builder: (_) => _DismissDialog(
          title: all
              ? 'Dismiss ${targets.length} failed '
                  '${targets.length == 1 ? 'item' : 'items'}?'
              : 'Dismiss this failed item?',
          message: all
              ? 'You have reviewed these. The kiosk will clear them from its '
                  '"failed" count on its next sync. They stay here as history.'
              : '${targets.single.studentName ?? 'Unknown card'} — '
                  '${targets.single.reason}\n\nThe kiosk will clear it from '
                  'its "failed" count on its next sync. It stays here as '
                  'history.',
          confirmLabel: all ? 'Dismiss all' : 'Dismiss',
      ),
    );
    if (result == null || !mounted) return;
    final note = result.note;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.onDismiss(
        [for (final t in targets) t.id],
        note.isEmpty ? null : note,
      );
      messenger?.showSnackBar(SnackBar(
        content: Text(targets.length == 1
            ? 'Dismissed. The kiosk will clear it on its next sync.'
            : 'Dismissed ${targets.length} items. The kiosk will clear them '
                'on its next sync.'),
      ));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not dismiss: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final openCount = _open.length;
    return BentoCard(
      backgroundColor: DashboardTableColors.card(context),
      borderColor: DashboardTableColors.border(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kiosk Sync Failures',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _Colors.primaryText(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Taps and violation reports a kiosk saved while offline '
                        'that the server then refused. Review why, then dismiss '
                        'them to clear the kiosk\'s "failed" count.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: _Colors.secondaryText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _FilterChip(
                      key: const Key('filter-open'),
                      label: 'Open ($openCount)',
                      selected: !_showDismissed,
                      onTap: () => setState(() => _showDismissed = false),
                    ),
                    _FilterChip(
                      key: const Key('filter-dismissed'),
                      label: 'Dismissed (${_items.length - openCount})',
                      selected: _showDismissed,
                      onTap: () => setState(() => _showDismissed = true),
                    ),
                    SecondaryPillButton(
                      key: const Key('refresh-failures'),
                      label: 'Refresh',
                      icon: Icons.refresh_rounded,
                      onTap: _loading ? null : _load,
                    ),
                    if (!_showDismissed && openCount > 0)
                      SecondaryPillButton(
                        key: const Key('clear-all-failures'),
                        label: 'Clear all open',
                        icon: Icons.done_all_rounded,
                        loading: _busy,
                        onTap: _busy ? null : () => _dismiss(_open, all: true),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _body(context),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          children: [
            Text(
              'Could not load kiosk sync failures.\n$_error\n\n'
              'If this is a new setup, run supabase/add_kiosk_sync_failures.sql '
              'in the Supabase SQL Editor.',
              key: const Key('failures-error'),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: _Colors.danger,
              ),
            ),
            const SizedBox(height: 12),
            SecondaryPillButton(
              key: const Key('retry-failures'),
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onTap: _load,
            ),
          ],
        ),
      );
    }

    final rows = _visible;
    return DashboardTableHorizontalScroll(
      minWidth: _minTableWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardTableHeader(columns: _columns, topBorder: true),
          if (rows.isEmpty)
            DashboardTableEmptyState(
              icon: Icons.check_circle_outline_rounded,
              message: _showDismissed
                  ? 'No dismissed items yet.'
                  : 'No failed kiosk items. Everything the kiosks saved '
                      'offline has synced.',
            )
          else
            for (var i = 0; i < rows.length; i++)
              DashboardTableRow(
                columns: _columns,
                showDivider: i < rows.length - 1,
                cells: _cells(context, rows[i]),
              ),
        ],
      ),
    );
  }

  List<Widget> _cells(BuildContext context, KioskSyncFailure f) {
    final name = f.studentName ??
        (f.rfidUid != null ? 'Unknown card' : 'Unknown student');
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatDateTime12h(f.occurredAt.toLocal()),
            style: dashboardTablePrimaryStyle(context),
          ),
          Text(
            'Reported ${formatDateTime12h(f.reportedAt.toLocal())}',
            style: dashboardTableSubStyle(context),
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: dashboardTablePrimaryStyle(context)),
          if (f.rfidUid != null)
            Text(f.rfidUid!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dashboardTableSubStyle(context)),
        ],
      ),
      Text(f.readerUsbSerial,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context)),
      Text(f.kindLabel, style: dashboardTableBodyStyle(context)),
      Text(f.reason,
          key: Key('reason-${f.id}'),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context)),
      if (f.isOpen)
        Align(
          alignment: Alignment.centerLeft,
          child: SecondaryPillButton(
            key: Key('dismiss-${f.id}'),
            label: 'Dismiss',
            onTap: _busy ? null : () => _dismiss([f], all: false),
          ),
        )
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Dismissed by ${f.dismissedBy ?? 'unknown'}',
              style: dashboardTableBodyStyle(context),
            ),
            if (f.dismissedAt != null)
              Text(formatDateTime12h(f.dismissedAt!.toLocal()),
                  style: dashboardTableSubStyle(context)),
            if (f.dismissNote != null)
              Text('“${f.dismissNote}”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: dashboardTableSubStyle(context)),
          ],
        ),
    ];
  }
}

/// What the dismiss dialog resolves to; null (not this) means cancelled.
class _DismissResult {
  const _DismissResult(this.note);
  final String note;
}

/// Owns the note field's controller so it is disposed together with the
/// dialog — disposing it from the caller right after `showDialog` returns
/// would run while the closing animation is still rebuilding the field.
class _DismissDialog extends StatefulWidget {
  const _DismissDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;

  @override
  State<_DismissDialog> createState() => _DismissDialogState();
}

class _DismissDialogState extends State<_DismissDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: widget.title,
      width: 440,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.message,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 11 : 13,
              height: 1.5,
              color: AppPopupColors.of(context).muted,
            ),
          ),
          kAppPopupFieldGap,
          AppPopupTextField(
            fieldKey: const Key('dismiss-note'),
            label: 'Note (optional)',
            controller: _note,
            maxLines: 2,
            hint: 'e.g. Duplicate tap, already counted',
          ),
        ],
      ),
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('dismiss-confirm'),
          label: widget.confirmLabel,
          onPressed: () =>
              Navigator.of(context).pop(_DismissResult(_note.text.trim())),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _Colors.chipFill(context, selected),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: kDashboardControlHeight),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DashboardTableColors.border(context)),
          ),
          // widthFactor/heightFactor 1: size to the label (then to the minimum
          // height above) while keeping it centered. A Container's own
          // `alignment` would instead stretch the chip across whatever width
          // it is offered — the full card, inside a Wrap.
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: _Colors.primaryText(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
