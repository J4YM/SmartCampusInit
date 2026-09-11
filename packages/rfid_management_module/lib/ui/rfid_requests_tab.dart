import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

class RfidRequestRowModel {
  const RfidRequestRowModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.section,
    required this.requestedByLabel,
    required this.requestedAtLabel,
    required this.isFulfilled,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String section;
  final String requestedByLabel;
  final String requestedAtLabel;
  final bool isFulfilled;
}

/// Read-only queue of Registrar's "students need RFID" requests — no
/// filter, no dismiss action, no deep-link into Student Records (see
/// docs/superpowers/specs/2026-09-11-rfid-assignment-requests-design.md's
/// Non-goals). A request clears itself once IT Technician actually
/// assigns an RFID number to that student via Student Records.
class RfidRequestsTab extends StatelessWidget {
  const RfidRequestsTab({super.key, required this.requests});

  final List<RfidRequestRowModel> requests;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ItTechnicianColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ItTechnicianColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RFID Requests',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ItTechnicianColors.rowText(context),
            ),
          ),
          const SizedBox(height: 16),
          if (requests.isEmpty)
            Text(
              'No RFID requests yet.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: ItTechnicianColors.mutedText(context),
              ),
            )
          else
            for (final request in requests) _RfidRequestRow(request: request),
        ],
      ),
    );
  }
}

class _RfidRequestRow extends StatelessWidget {
  const _RfidRequestRow({required this.request});

  final RfidRequestRowModel request;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${request.studentName} — ${request.studentNumber}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ItTechnicianColors.rowText(context),
                  ),
                ),
                Text(
                  '${request.section} · Requested by ${request.requestedByLabel} on ${request.requestedAtLabel}',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: ItTechnicianColors.mutedText(context),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: request.isFulfilled
                  ? const Color(0x33137333)
                  : const Color(0x33CD4855),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              request.isFulfilled ? 'Fulfilled' : 'Pending',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: request.isFulfilled
                    ? ItTechnicianColors.successGreen
                    : ItTechnicianColors.dangerRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
