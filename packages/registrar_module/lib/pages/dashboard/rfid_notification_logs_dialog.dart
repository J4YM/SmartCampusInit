import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';

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

class RfidNotificationLogsDialog extends StatelessWidget {
  const RfidNotificationLogsDialog({super.key, required this.logs});

  final List<RfidNotificationLogModel> logs;

  @override
  Widget build(BuildContext context) {
    final headerStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 998,
        constraints: const BoxConstraints(maxWidth: 998),
        decoration: BoxDecoration(
          color: RegistrarColors.card(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: RegistrarColors.cardBorder(context)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
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
                  InkWell(
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
                ],
              ),
            ),
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                color: RegistrarColors.navyBlue,
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text('Student Name', style: headerStyle)),
                    Expanded(flex: 2, child: Text('Student ID', style: headerStyle)),
                    Expanded(flex: 2, child: Text('Grade & Section', style: headerStyle)),
                    SizedBox(
                      width: 80,
                      child: Text('Status', style: headerStyle),
                    ),
                  ],
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: logs.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No notification logs yet',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: RegistrarColors.mutedText(context),
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: logs.length,
                      itemBuilder: (context, index) =>
                          _LogRow(log: logs[index]),
                    ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log});

  final RfidNotificationLogModel log;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      fontWeight: FontWeight.w500,
      color: RegistrarColors.rowText(context),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: RegistrarColors.cardBorder(context))),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(log.studentName, style: style)),
          Expanded(flex: 2, child: Text(log.studentId, style: style)),
          Expanded(flex: 2, child: Text(log.section, style: style)),
          SizedBox(
            width: 80,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            ),
          ),
        ],
      ),
    );
  }
}
