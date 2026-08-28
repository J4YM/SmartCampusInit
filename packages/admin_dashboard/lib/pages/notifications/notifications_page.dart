import 'package:dashboard_layout/dashboard_layout.dart';
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

/// One person the "Specific user" picker can target — supplied by the host
/// app from its own staff directory (this package has no Supabase access
/// and no knowledge of the `profiles` table).
class NotificationRecipient {
  const NotificationRecipient({
    required this.id,
    required this.name,
    required this.roleLabel,
  });

  final String id;
  final String name;

  /// Display label, e.g. "Discipline Officer" — also what gets sent back so
  /// the host can map it to its own role enum for the row's `target_role`.
  final String roleLabel;
}

/// What a compose dialog hands back to [NotificationsPage.onSend] — either
/// [targetUserId] is set (direct message) or it's null (role broadcast).
class NotificationSendRequest {
  const NotificationSendRequest({
    required this.title,
    required this.message,
    this.targetUserId,
    this.targetRoleLabel,
  });

  final String title;
  final String message;
  final String? targetUserId;

  /// The broadcast role label (e.g. "Discipline Officer") when
  /// [targetUserId] is null, or the picked recipient's own role label when
  /// it isn't — either way the host always has a role to set `target_role`
  /// to, per add_notifications_user_targeting.sql.
  final String? targetRoleLabel;
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
    targetDashboard: 'Student Affairs & Services',
  ),
  NotificationTriggerDef(
    id: 'violationCountExceeded',
    title: 'Violation Count Exceeded',
    subtitle: 'Send alert when violation limit is reached',
    targetDashboard: 'Student Affairs & Services',
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
  static Color background(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF111111) : const Color(0xFFF1F5F9);
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF16191D) : const Color(0xFFFFFFFF);
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  static Color cardBorder(BuildContext context) =>
      context.isDarkMode ? const Color(0x0D334155) : const Color(0x0DE2E8F0);
  static Color fieldFill(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF111111) : const Color(0xFFF1F5F9);
  // Shared brand accent (the same blue every other dashboard's buttons use)
  // — stays constant across themes, like every other dashboard's own accent.
  static const primaryButton = Color(0xFF345892);
  static const primaryButtonText = Color(0xFFFFFFFF);
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    this.onSend,
    this.staffDirectory = const [],
  });

  factory NotificationsPage.empty({Key? key}) {
    return NotificationsPage(key: key);
  }

  /// Sends a notification composed from [NotificationTriggerDef.id]'s
  /// starting point — called only after the compose dialog's "Send", with
  /// whatever message/recipient the admin actually chose (title and message
  /// may have been edited from the trigger's defaults). When omitted, every
  /// trigger button is disabled (demo behavior — there's nowhere for the
  /// notification to actually go).
  final Future<void> Function(
      String triggerId, NotificationSendRequest request)? onSend;

  /// Candidates for the compose dialog's "Specific user" picker — supplied
  /// by the host from its own staff directory.
  final List<NotificationRecipient> staffDirectory;

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
      color: _NotifColors.background(context),
      child: SafeArea(
        // The scroll view spans the full content pane (no width cap out
        // here) so its scrollbar sits at the pane's true edge; only the
        // inner content is capped at 1440px and centered.
        child: SingleChildScrollView(
          child: DashboardPageWrapper(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _NotifColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Manage notification channels and delivery rules.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: _NotifColors.secondaryText(context),
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
                      onSend: widget.onSend,
                      staffDirectory: widget.staffDirectory,
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
        color: _NotifColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _NotifColors.cardBorder(context)),
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
                        color: _NotifColors.primaryText(context),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: _NotifColors.secondaryText(context),
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
        color: _NotifColors.fieldFill(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _NotifColors.cardBorder(context)),
      ),
      child: Text(
        'Under Development',
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _NotifColors.secondaryText(context),
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
            color: _NotifColors.primaryText(context),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          enabled: false,
          obscureText: obscureText,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: _NotifColors.primaryText(context),
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.poppins(
              fontSize: 13,
              color: _NotifColors.secondaryText(context),
            ),
            filled: true,
            fillColor: _NotifColors.fieldFill(context),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _NotifColors.cardBorder(context)),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _NotifColors.cardBorder(context)),
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
          _LabeledTextField(
              label: 'SMTP Host', hintText: 'e.g. smtp.gmail.com'),
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
    required this.staffDirectory,
    required this.onResult,
  });

  final Future<void> Function(
      String triggerId, NotificationSendRequest request)? onSend;
  final List<NotificationRecipient> staffDirectory;
  final void Function(String message) onResult;

  @override
  State<_NotificationTriggersCard> createState() =>
      _NotificationTriggersCardState();
}

class _NotificationTriggersCardState extends State<_NotificationTriggersCard> {
  final _sendingIds = <String>{};

  Future<void> _composeAndSend(NotificationTriggerDef trigger) async {
    final request = await showDialog<NotificationSendRequest>(
      context: context,
      builder: (dialogContext) => _ComposeNotificationDialog(
        trigger: trigger,
        staffDirectory: widget.staffDirectory,
      ),
    );
    if (request == null || !mounted) return;

    setState(() => _sendingIds.add(trigger.id));
    try {
      await widget.onSend?.call(trigger.id, request);
      final destination = request.targetUserId != null
          ? widget.staffDirectory
                  .where((r) => r.id == request.targetUserId)
                  .map((r) => r.name)
                  .firstOrNull ??
              'the selected user'
          : trigger.targetDashboard;
      widget.onResult('Sent "${request.title}" to $destination.');
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
      subtitle: 'Compose and send a notification now',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < notificationTriggers.length; i++) ...[
            if (i > 0) Divider(height: 1, color: _NotifColors.cardBorder(context)),
            _TriggerButtonRow(
              trigger: notificationTriggers[i],
              sending: _sendingIds.contains(notificationTriggers[i].id),
              onPressed: widget.onSend == null
                  ? null
                  : () => _composeAndSend(notificationTriggers[i]),
            ),
          ],
        ],
      ),
    );
  }
}

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Lets the admin edit the message and choose who actually receives it
/// before sending — either the trigger's usual role broadcast, or one
/// specific person picked from [staffDirectory].
class _ComposeNotificationDialog extends StatefulWidget {
  const _ComposeNotificationDialog({
    required this.trigger,
    required this.staffDirectory,
  });

  final NotificationTriggerDef trigger;
  final List<NotificationRecipient> staffDirectory;

  @override
  State<_ComposeNotificationDialog> createState() =>
      _ComposeNotificationDialogState();
}

class _ComposeNotificationDialogState
    extends State<_ComposeNotificationDialog> {
  late final _messageController =
      TextEditingController(text: widget.trigger.subtitle);
  bool _sendToSpecificUser = false;
  NotificationRecipient? _selectedRecipient;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _send() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    if (_sendToSpecificUser && _selectedRecipient == null) return;

    Navigator.of(context).pop(
      NotificationSendRequest(
        title: widget.trigger.title,
        message: message,
        targetUserId: _sendToSpecificUser ? _selectedRecipient!.id : null,
        targetRoleLabel: _sendToSpecificUser
            ? _selectedRecipient!.roleLabel
            : widget.trigger.targetDashboard,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _messageController.text.trim().isNotEmpty &&
        (!_sendToSpecificUser || _selectedRecipient != null);

    return AlertDialog(
      title: Text(
        'Send "${widget.trigger.title}"',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send to',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _NotifColors.secondaryText(context),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text('Role: ${widget.trigger.targetDashboard}'),
                ),
                const ButtonSegment(
                  value: true,
                  label: Text('Specific user'),
                ),
              ],
              selected: {_sendToSpecificUser},
              onSelectionChanged: (selection) =>
                  setState(() => _sendToSpecificUser = selection.first),
            ),
            if (_sendToSpecificUser) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<NotificationRecipient>(
                value: _selectedRecipient,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Recipient',
                  border: OutlineInputBorder(),
                ),
                items: widget.staffDirectory
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(
                          '${r.name} — ${r.roleLabel}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _selectedRecipient = value),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSend ? _send : null,
          child: const Text('Send'),
        ),
      ],
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
                    color: _NotifColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  trigger.subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: _NotifColors.secondaryText(context),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
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
