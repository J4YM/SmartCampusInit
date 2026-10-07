import 'dart:async';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:kiosk_offline/kiosk_offline.dart';

String describeSyncStatus(SyncStatus s) {
  if (s.rejected > 0) return '${s.rejected} failed';
  if (!s.online) return 'Offline · ${s.pending} pending';
  if (s.pending > 0) return 'Syncing · ${s.pending} pending';
  return 'Online';
}

/// `2026-10-05 8:00 AM` (local, 12-hour, no seconds).
String formatDiagnosticTime(DateTime t) {
  final l = t.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final ampm = l.hour >= 12 ? 'PM' : 'AM';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} $h:${two(l.minute)} $ampm';
}

Color _colorFor(SyncStatus s) {
  if (s.rejected > 0) return const Color(0xFFB91C1C);
  if (!s.online) return const Color(0xFFB45309);
  if (s.pending > 0) return const Color(0xFF1D4ED8);
  return const Color(0xFF15803D);
}

/// Small corner chip showing connectivity and sync backlog; tap for details.
class OfflineStatusChip extends StatefulWidget {
  const OfflineStatusChip({super.key, required this.offline});

  final KioskOffline offline;

  @override
  State<OfflineStatusChip> createState() => _OfflineStatusChipState();
}

class _OfflineStatusChipState extends State<OfflineStatusChip> {
  SyncStatus _status = const SyncStatus(online: false, pending: 0, rejected: 0);
  StreamSubscription<SyncStatus>? _sub;
  bool _gotStreamEvent = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.offline.status.listen((s) {
      _gotStreamEvent = true;
      if (mounted) setState(() => _status = s);
    });
    widget.offline.currentStatus().then((s) {
      if (mounted && !_gotStreamEvent) setState(() => _status = s);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _showDetails() async {
    final rows = await widget.offline.diagnostics();
    if (!mounted) return;
    await showAppPopup<void>(
      context: context,
      builder: (ctx) => AppPopup(
        title: 'Sync details',
        // The list scrolls itself, so it gets a bounded height.
        scrollBody: false,
        body: SizedBox(
          width: double.infinity,
          child: rows.isEmpty
              ? const Text('Nothing waiting to sync.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    if (rows.any((r) => r.status == 'rejected'))
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Failed items are reported to the IT Technician and '
                          'Admin dashboards, where they can be reviewed and '
                          'cleared. This count clears on the next sync after '
                          'they do.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    for (final r in rows)
                      ListTile(
                        dense: true,
                        title: Text('${r.type} · ${r.status} · ${r.attempts} tries'),
                        subtitle: Text(
                          [
                            formatDiagnosticTime(r.createdAt),
                            if (r.lastError != null) r.lastError!,
                          ].join('\n'),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          AppPopupSecondaryButton(
            label: 'Close',
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(_status);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        canRequestFocus: false,
        onTap: _showDetails,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            describeSyncStatus(_status),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
