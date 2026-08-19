import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// SMS Gateway / Email (SMTP) are under development (see _SmsGatewayCard /
// _SmtpEmailCard below) — no provider is configured yet, so there's
// deliberately no config model here to round-trip; both cards render
// disabled fields with no backing data.
// ---------------------------------------------------------------------------

/// One "Automated Trigger Rule" — a manual "send now" action rather than an
/// on/off setting (see [_NotificationTriggersCard]). [id] is passed back
/// through [NotificationsPage.onSendNotification] so the host app can map it
/// to a target role + persist it via the centralized `notifications` table
/// (see supabase/add_notifications_schema.sql) without this package needing
/// to know about `AppRole`.
class NotificationTriggerDef {
  const NotificationTriggerDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.targetDashboard,
  });

  final String id;
  final String title;
  final String subtitle;

  /// Display label for which dashboard receives this — e.g. "Discipline
  /// Officer", shown so the admin knows where the confirm prompt is sending.
  final String targetDashboard;
}

const notificationTriggers = <NotificationTriggerDef>[
  NotificationTriggerDef(
    id: 'earlyWarningFlag',
    title: 'Early Warning Flag (ML)',
    subtitle: 'Notify guidance counselor when a student is flagged',
    targetDashboard: 'Guidance Counselor',
  ),
  NotificationTriggerDef(
    id: 'absenceThresholdReached',
    title: 'Absence Threshold Reached',
    subtitle: 'Alert discipline officer when threshold is hit',
    targetDashboard: 'Discipline Officer',
  ),
  NotificationTriggerDef(
    id: 'violationCountExceeded',
    title: 'Violation Count Exceeded',
    subtitle: 'Send alert when violation limit is reached',
    targetDashboard: 'Discipline Officer',
  ),
  NotificationTriggerDef(
    id: 'newDisciplineCaseFiled',
    title: 'New Discipline Case Filed',
    subtitle: 'Notify admin when a new case is created',
    targetDashboard: 'Admin',
  ),
  NotificationTriggerDef(
    id: 'dailyAttendanceSummary',
    title: 'Daily Attendance Summary',
    subtitle: 'Send automated summary report every 5:00 PM',
    targetDashboard: 'Professor',
  ),
  NotificationTriggerDef(
    id: 'rfidGatewayOffline',
    title: 'RFID Gateway Offline',
    subtitle: 'Alert admin immediately when a reader goes offline',
    targetDashboard: 'Admin',
  ),
  NotificationTriggerDef(
    id: 'mlModelRetrained',
    title: 'ML Model Retrained',
    subtitle: 'Notify admin when retraining completes successfully',
    targetDashboard: 'Admin',
  ),
];

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _NotifColors {
  static const background = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const cardBorder = Color(0xFFE2E8F0);
  static const fieldFill = Color(0xFFF1F5F9);
  static const primaryButton = Color(0xFF27426D);
  static const primaryButtonText = Color(0xFFFFFFFF);
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    this.onSendNotification,
  });

  factory NotificationsPage.empty({Key? key}) {
    return NotificationsPage(key: key);
  }

  /// Sends the notification behind [NotificationTriggerDef.id] — the action
  /// behind each trigger button, called only after the confirm prompt. When
  /// omitted, every trigger button is disabled (demo behavior — there's
  /// nowhere for the notification to actually go).
  final Future<void> Function(String triggerId)? onSendNotification;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  void _showActionSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _NotifColors.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notifications',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _NotifColors.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage notification channels and delivery rules.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: _NotifColors.secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stackColumns = constraints.maxWidth < 900;

                  const gatewayColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SmsGatewayCard(),
                      SizedBox(height: 16),
                      _SmtpEmailCard(),
                    ],
                  );

                  final triggerRulesColumn = _NotificationTriggersCard(
                    onSend: widget.onSendNotification,
                    onResult: _showActionSnackBar,
                  );

                  if (stackColumns) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        gatewayColumn,
                        const SizedBox(height: 16),
                        triggerRulesColumn,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: gatewayColumn),
                      const SizedBox(width: 16),
                      Expanded(child: triggerRulesColumn),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared card chrome
// ---------------------------------------------------------------------------

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.badge,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _NotifColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _NotifColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _NotifColors.primaryText,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: _NotifColors.secondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (badge != null) badge!,
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

/// Small pill shown on a card's header when its backend isn't set up yet
/// (SMS Gateway, Email SMTP) — matches ML & Thresholds' "Under Development"
/// treatment for its own not-yet-real Retrain action.
class _UnderDevelopmentBadge extends StatelessWidget {
  const _UnderDevelopmentBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _NotifColors.fieldFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _NotifColors.cardBorder),
      ),
      child: Text(
        'Under Development',
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _NotifColors.secondaryText,
        ),
      ),
    );
  }
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.hintText,
    this.obscureText = false,
  });

  final String label;
  final String hintText;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _NotifColors.primaryText,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          enabled: false,
          obscureText: obscureText,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: _NotifColors.primaryText,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.poppins(
              fontSize: 13,
              color: _NotifColors.secondaryText,
            ),
            filled: true,
            fillColor: _NotifColors.fieldFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _NotifColors.cardBorder),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _NotifColors.cardBorder),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Left column — SMS Gateway (under development: no SMS provider is
// configured yet, so this card is disabled rather than pretending to save
// settings nothing actually reads).
// ---------------------------------------------------------------------------

class _SmsGatewayCard extends StatelessWidget {
  const _SmsGatewayCard();

  @override
  Widget build(BuildContext context) {
    return const _SettingsCard(
      title: 'SMS Gateway (PhilSMS)',
      badge: _UnderDevelopmentBadge(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LabeledTextField(
            label: 'API Key',
            hintText: 'Enter PhilSMS API Key',
            obscureText: true,
          ),
          SizedBox(height: 16),
          _LabeledTextField(
            label: 'Sender ID',
            hintText: 'e.g. STI-BALIUAG',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left column — Email (SMTP) (under development — same reasoning as SMS).
// ---------------------------------------------------------------------------

class _SmtpEmailCard extends StatelessWidget {
  const _SmtpEmailCard();

  @override
  Widget build(BuildContext context) {
    return const _SettingsCard(
      title: 'Email (SMTP)',
      badge: _UnderDevelopmentBadge(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LabeledTextField(label: 'SMTP Host', hintText: 'e.g. smtp.gmail.com'),
          SizedBox(height: 16),
          _LabeledTextField(label: 'Port', hintText: '587'),
          SizedBox(height: 16),
          _LabeledTextField(
            label: 'Username',
            hintText: 'e.g. noreply@domain.edu',
          ),
          SizedBox(height: 16),
          _LabeledTextField(
            label: 'Password',
            hintText: '••••••••',
            obscureText: true,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right column — Automated Trigger Rules. Each rule is a manual "send now"
// button rather than an on/off setting — pressing it confirms, then hands
// off to the centralized notification system (see NotificationsRepository
// in the host app).
// ---------------------------------------------------------------------------

class _NotificationTriggersCard extends StatefulWidget {
  const _NotificationTriggersCard({
    required this.onSend,
    required this.onResult,
  });

  final Future<void> Function(String triggerId)? onSend;
  final void Function(String message) onResult;

  @override
  State<_NotificationTriggersCard> createState() =>
      _NotificationTriggersCardState();
}

class _NotificationTriggersCardState
    extends State<_NotificationTriggersCard> {
  final _sendingIds = <String>{};

  Future<void> _confirmAndSend(NotificationTriggerDef trigger) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Send "${trigger.title}"?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This sends a notification to the ${trigger.targetDashboard} '
          'dashboard now: "${trigger.subtitle}"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sendingIds.add(trigger.id));
    try {
      await widget.onSend?.call(trigger.id);
      widget.onResult('Sent "${trigger.title}" to ${trigger.targetDashboard}.');
    } catch (e) {
      widget.onResult('Could not send "${trigger.title}": $e');
    } finally {
      if (mounted) setState(() => _sendingIds.remove(trigger.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Automated Trigger Rules',
      subtitle: 'Send a notification to the owning dashboard now',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < notificationTriggers.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: _NotifColors.cardBorder),
            _TriggerButtonRow(
              trigger: notificationTriggers[i],
              sending: _sendingIds.contains(notificationTriggers[i].id),
              onPressed: widget.onSend == null
                  ? null
                  : () => _confirmAndSend(notificationTriggers[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _TriggerButtonRow extends StatelessWidget {
  const _TriggerButtonRow({
    required this.trigger,
    required this.sending,
    required this.onPressed,
  });

  final NotificationTriggerDef trigger;
  final bool sending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trigger.title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _NotifColors.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  trigger.subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: _NotifColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '→ ${trigger.targetDashboard}',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: _NotifColors.primaryButton,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: sending ? null : onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: _NotifColors.primaryButton,
              foregroundColor: _NotifColors.primaryButtonText,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: sending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'Send',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
