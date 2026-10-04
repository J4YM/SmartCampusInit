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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: 998,
        child: BentoCard(
          backgroundColor: RegistrarColors.card(context),
          borderColor: RegistrarColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Notification Logs',
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 16 : 18,
                          fontWeight: FontWeight.w600,
                          color: RegistrarColors.rowText(context),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Close',
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 22,
                            color: RegistrarColors.rowText(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: MaxWidthAligned(
                  child: SearchField(
                    controller: _searchController,
                    hintText: 'Search logs',
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              ),
              DashboardTableSection(
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
              const SizedBox(height: 8),
            ],
          ),
        ),
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
