import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Data model — Supabase (`registration_sync_events`) ready. See
// supabase/add_registration_sync_log_schema.sql.
// ---------------------------------------------------------------------------

enum RegisterSyncEventType { accountRegistered, rfidAssigned, recordClaimed }

RegisterSyncEventType? registerSyncEventTypeFromDbValue(String? value) {
  switch (value) {
    case 'account_registered':
      return RegisterSyncEventType.accountRegistered;
    case 'rfid_assigned':
      return RegisterSyncEventType.rfidAssigned;
    case 'record_claimed':
      return RegisterSyncEventType.recordClaimed;
    default:
      return null;
  }
}

class RegisterSyncEventModel {
  const RegisterSyncEventModel({
    required this.id,
    required this.eventType,
    required this.detail,
    required this.occurredAt,
  });

  final String id;
  final RegisterSyncEventType eventType;
  final String detail;
  final DateTime occurredAt;
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _SyncColors {
  static const background = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const cardBorder = Color(0xFFE2E8F0);
  static const registeredTint = Color(0xFF2563EB);
  static const rfidTint = Color(0xFF7C3AED);
  static const claimedTint = Color(0xFF059669);
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class RegisterSyncsPage extends StatelessWidget {
  const RegisterSyncsPage({
    super.key,
    required this.events,
    this.isLoading = false,
  });

  factory RegisterSyncsPage.empty({Key? key}) {
    return RegisterSyncsPage(key: key, events: const []);
  }

  /// Newest-first. Supplied by the host app from `registration_sync_events`.
  final List<RegisterSyncEventModel> events;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _SyncColors.background,
      child: SafeArea(
        // A plain-width wrapper here (bounded by the ambient sidebar Row's
        // height, not a scroll view of its own) still gets the standard
        // 1440px-capped, centered frame, matching every other admin page's
        // inner content.
        child: DashboardPageWrapper(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Register Syncs',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _SyncColors.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Latest account registrations, RFID card assignments, and '
                'pre-registered record claims.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: _SyncColors.secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _SyncColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _SyncColors.cardBorder),
                  ),
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : events.isEmpty
                          ? Center(
                              child: Text(
                                'No registration activity yet.',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: _SyncColors.secondaryText,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: events.length,
                              separatorBuilder: (_, __) => const Divider(
                                  height: 1, color: _SyncColors.cardBorder),
                              itemBuilder: (context, index) =>
                                  _SyncEventRow(event: events[index]),
                            ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncEventRow extends StatelessWidget {
  const _SyncEventRow({required this.event});

  final RegisterSyncEventModel event;

  (IconData, Color, String) get _presentation {
    switch (event.eventType) {
      case RegisterSyncEventType.accountRegistered:
        return (
          Icons.person_add_alt_1_rounded,
          _SyncColors.registeredTint,
          'Registration'
        );
      case RegisterSyncEventType.rfidAssigned:
        return (
          Icons.credit_card_rounded,
          _SyncColors.rfidTint,
          'RFID Assignment'
        );
      case RegisterSyncEventType.recordClaimed:
        return (Icons.link_rounded, _SyncColors.claimedTint, 'Record Claim');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, tint, label) = _presentation;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.detail,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _SyncColors.primaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _timeAgoLabel(event.occurredAt),
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: _SyncColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

String _timeAgoLabel(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}
