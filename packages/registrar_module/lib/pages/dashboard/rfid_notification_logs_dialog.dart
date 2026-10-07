import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'registrar_dashboard_page.dart' show MaxWidthAligned, SearchField, matchesSearchQuery;

// ---------------------------------------------------------------------------
// RFID Notify tab — "Notification Logs" popup (Figma node 532:3369), opened
// by RfidManagementView's "View Logs" button. Every student included in a
// "Submit & Notify" action gets appended here as a "Sent" row.
// ---------------------------------------------------------------------------

class RfidNotificationLogModel {
  const RfidNotificationLogModel({
    required this.studentName,
    required this.studentId,
    required this.section,
  });

  final String studentName;
  final String studentId;
  final String section;
}

class RfidNotificationLogsDialog extends StatefulWidget {
  const RfidNotificationLogsDialog({super.key, required this.logs});

  final List<RfidNotificationLogModel> logs;

  @override
  State<RfidNotificationLogsDialog> createState() =>
      _RfidNotificationLogsDialogState();
}

class _RfidNotificationLogsDialogState
    extends State<RfidNotificationLogsDialog> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = [
      for (final l in widget.logs)
        if (matchesSearchQuery(_query, [l.studentName, l.studentId, l.section])) l,
    ];
    return AppPopup(
      title: 'Notification Logs',
      subtitle: widget.logs.isEmpty
          ? null
          : '${widget.logs.length} '
              '${widget.logs.length == 1 ? 'student' : 'students'} notified',
      width: 998,
      // The table scrolls inside its own height cap.
      scrollBody: false,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MaxWidthAligned(
            child: SearchField(
              controller: _searchController,
              hintText: 'Search logs',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: DashboardTableSection(
                columns: _logColumns,
                body: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: logs.isEmpty
                      ? DashboardTableEmptyState(
                          icon: Icons.mark_email_read_outlined,
                          message: widget.logs.isEmpty
                              ? 'No notification logs yet'
                              : 'No logs match your search',
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: logs.length,
                          itemBuilder: (context, index) => _LogRow(
                            log: logs[index],
                            showDivider: index < logs.length - 1,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _logColumns = <DashboardTableColumn>[
  DashboardTableColumn('Student Name', flex: 3),
  DashboardTableColumn('Student ID', flex: 2),
  DashboardTableColumn('Grade & Section', flex: 2),
  DashboardTableColumn('Status', flex: 1, compact: true),
];

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log, required this.showDivider});

  final RfidNotificationLogModel log;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return DashboardTableRow(
      columns: _logColumns,
      showDivider: showDivider,
      cells: [
        Text(
          log.studentName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTablePrimaryStyle(context),
        ),
        Text(
          log.studentId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableIdStyle(context),
        ),
        Text(
          log.section,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0x3334C759),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Sent',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: RegistrarColors.successGreen,
            ),
          ),
        ),
      ],
    );
  }
}
