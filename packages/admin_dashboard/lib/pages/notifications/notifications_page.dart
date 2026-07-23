import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Data models — swap the default*Config constants with Supabase/API-loaded
// settings later. fromJson/toJson keep each model round-trippable with a
// `notification_settings` table or similar.
// ---------------------------------------------------------------------------

class SmsGatewayConfigModel {
  const SmsGatewayConfigModel({
    this.apiKey = '',
    this.senderId = '',
  });

  final String apiKey;
  final String senderId;

  factory SmsGatewayConfigModel.fromJson(Map<String, dynamic> json) {
    return SmsGatewayConfigModel(
      apiKey: json['apiKey'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'senderId': senderId,
      };
}

class SmtpEmailConfigModel {
  const SmtpEmailConfigModel({
    this.smtpHost = '',
    this.port = 587,
    this.username = '',
    this.password = '',
  });

  final String smtpHost;
  final int port;
  final String username;
  final String password;

  factory SmtpEmailConfigModel.fromJson(Map<String, dynamic> json) {
    return SmtpEmailConfigModel(
      smtpHost: json['smtpHost'] as String? ?? '',
      port: json['port'] as int? ?? 587,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'smtpHost': smtpHost,
        'port': port,
        'username': username,
        'password': password,
      };
}

class AutomatedTriggerRulesModel {
  const AutomatedTriggerRulesModel({
    this.earlyWarningFlag = false,
    this.absenceThresholdReached = false,
    this.violationCountExceeded = false,
    this.newDisciplineCaseFiled = false,
    this.dailyAttendanceSummary = false,
    this.rfidGatewayOffline = false,
    this.mlModelRetrained = false,
  });

  final bool earlyWarningFlag;
  final bool absenceThresholdReached;
  final bool violationCountExceeded;
  final bool newDisciplineCaseFiled;
  final bool dailyAttendanceSummary;
  final bool rfidGatewayOffline;
  final bool mlModelRetrained;

  factory AutomatedTriggerRulesModel.fromJson(Map<String, dynamic> json) {
    return AutomatedTriggerRulesModel(
      earlyWarningFlag: json['earlyWarningFlag'] as bool? ?? false,
      absenceThresholdReached: json['absenceThresholdReached'] as bool? ?? false,
      violationCountExceeded: json['violationCountExceeded'] as bool? ?? false,
      newDisciplineCaseFiled: json['newDisciplineCaseFiled'] as bool? ?? false,
      dailyAttendanceSummary: json['dailyAttendanceSummary'] as bool? ?? false,
      rfidGatewayOffline: json['rfidGatewayOffline'] as bool? ?? false,
      mlModelRetrained: json['mlModelRetrained'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'earlyWarningFlag': earlyWarningFlag,
        'absenceThresholdReached': absenceThresholdReached,
        'violationCountExceeded': violationCountExceeded,
        'newDisciplineCaseFiled': newDisciplineCaseFiled,
        'dailyAttendanceSummary': dailyAttendanceSummary,
        'rfidGatewayOffline': rfidGatewayOffline,
        'mlModelRetrained': mlModelRetrained,
      };

  AutomatedTriggerRulesModel copyWith({
    bool? earlyWarningFlag,
    bool? absenceThresholdReached,
    bool? violationCountExceeded,
    bool? newDisciplineCaseFiled,
    bool? dailyAttendanceSummary,
    bool? rfidGatewayOffline,
    bool? mlModelRetrained,
  }) {
    return AutomatedTriggerRulesModel(
      earlyWarningFlag: earlyWarningFlag ?? this.earlyWarningFlag,
      absenceThresholdReached:
          absenceThresholdReached ?? this.absenceThresholdReached,
      violationCountExceeded:
          violationCountExceeded ?? this.violationCountExceeded,
      newDisciplineCaseFiled:
          newDisciplineCaseFiled ?? this.newDisciplineCaseFiled,
      dailyAttendanceSummary:
          dailyAttendanceSummary ?? this.dailyAttendanceSummary,
      rfidGatewayOffline: rfidGatewayOffline ?? this.rfidGatewayOffline,
      mlModelRetrained: mlModelRetrained ?? this.mlModelRetrained,
    );
  }
}

// ---------------------------------------------------------------------------
// Default (empty) state — replace with repository/API calls when backend
// is ready.
// ---------------------------------------------------------------------------

const defaultSmsGatewayConfig = SmsGatewayConfigModel();
const defaultSmtpEmailConfig = SmtpEmailConfigModel();
const defaultAutomatedTriggerRules = AutomatedTriggerRulesModel();

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
    required this.smsConfig,
    required this.emailConfig,
    required this.triggerRules,
  });

  factory NotificationsPage.empty({Key? key}) {
    return NotificationsPage(
      key: key,
      smsConfig: defaultSmsGatewayConfig,
      emailConfig: defaultSmtpEmailConfig,
      triggerRules: defaultAutomatedTriggerRules,
    );
  }

  final SmsGatewayConfigModel smsConfig;
  final SmtpEmailConfigModel emailConfig;
  final AutomatedTriggerRulesModel triggerRules;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _apiKeyController = TextEditingController();
  final _senderIdController = TextEditingController();
  final _smtpHostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  late AutomatedTriggerRulesModel _triggerRules;

  @override
  void initState() {
    super.initState();
    _apiKeyController.text = widget.smsConfig.apiKey;
    _senderIdController.text = widget.smsConfig.senderId;
    _smtpHostController.text = widget.emailConfig.smtpHost;
    // 587 is the model's own unset-default (see SmtpEmailConfigModel), so
    // leave the field empty and let the "587" hint guide the admin instead
    // of pre-filling text that looks like a saved value.
    _portController.text = widget.emailConfig.port == 587
        ? ''
        : '${widget.emailConfig.port}';
    _usernameController.text = widget.emailConfig.username;
    _passwordController.text = widget.emailConfig.password;
    _triggerRules = widget.triggerRules;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _senderIdController.dispose();
    _smtpHostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

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

                  final gatewayColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SmsGatewayCard(
                        apiKeyController: _apiKeyController,
                        senderIdController: _senderIdController,
                        onTestSms: () =>
                            _showActionSnackBar('Test SMS tapped'),
                        onSave: () =>
                            _showActionSnackBar('SMS Gateway settings saved'),
                      ),
                      const SizedBox(height: 16),
                      _SmtpEmailCard(
                        smtpHostController: _smtpHostController,
                        portController: _portController,
                        usernameController: _usernameController,
                        passwordController: _passwordController,
                        onTestEmail: () =>
                            _showActionSnackBar('Test Email tapped'),
                        onSave: () =>
                            _showActionSnackBar('Email (SMTP) settings saved'),
                      ),
                    ],
                  );

                  final triggerRulesColumn = _TriggerRulesCard(
                    rules: _triggerRules,
                    onChanged: (rules) => setState(() => _triggerRules = rules),
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
  });

  final String title;
  final String? subtitle;
  final Widget child;

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
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final TextInputType? keyboardType;

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
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
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
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _NotifColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _NotifColors.primaryButton),
            ),
          ),
        ),
      ],
    );
  }
}

class _CardActionsRow extends StatelessWidget {
  const _CardActionsRow({
    required this.testIcon,
    required this.testLabel,
    required this.onTest,
    required this.onSave,
  });

  final IconData testIcon;
  final String testLabel;
  final VoidCallback onTest;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: onTest,
          icon: Icon(testIcon, size: 16),
          label: Text(
            testLabel,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _NotifColors.primaryText,
            side: const BorderSide(color: _NotifColors.cardBorder),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: onSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: _NotifColors.primaryButton,
            foregroundColor: _NotifColors.primaryButtonText,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            'Save',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Left column — SMS Gateway
// ---------------------------------------------------------------------------

class _SmsGatewayCard extends StatelessWidget {
  const _SmsGatewayCard({
    required this.apiKeyController,
    required this.senderIdController,
    required this.onTestSms,
    required this.onSave,
  });

  final TextEditingController apiKeyController;
  final TextEditingController senderIdController;
  final VoidCallback onTestSms;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'SMS Gateway (PhilSMS)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LabeledTextField(
            label: 'API Key',
            controller: apiKeyController,
            hintText: 'Enter PhilSMS API Key',
            obscureText: true,
          ),
          const SizedBox(height: 16),
          _LabeledTextField(
            label: 'Sender ID',
            controller: senderIdController,
            hintText: 'e.g. STI-BALIUAG',
          ),
          const SizedBox(height: 20),
          _CardActionsRow(
            testIcon: Icons.send_rounded,
            testLabel: 'Test SMS',
            onTest: onTestSms,
            onSave: onSave,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left column — Email (SMTP)
// ---------------------------------------------------------------------------

class _SmtpEmailCard extends StatelessWidget {
  const _SmtpEmailCard({
    required this.smtpHostController,
    required this.portController,
    required this.usernameController,
    required this.passwordController,
    required this.onTestEmail,
    required this.onSave,
  });

  final TextEditingController smtpHostController;
  final TextEditingController portController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final VoidCallback onTestEmail;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Email (SMTP)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LabeledTextField(
            label: 'SMTP Host',
            controller: smtpHostController,
            hintText: 'e.g. smtp.gmail.com',
          ),
          const SizedBox(height: 16),
          _LabeledTextField(
            label: 'Port',
            controller: portController,
            hintText: '587',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          _LabeledTextField(
            label: 'Username',
            controller: usernameController,
            hintText: 'e.g. noreply@domain.edu',
          ),
          const SizedBox(height: 16),
          _LabeledTextField(
            label: 'Password',
            controller: passwordController,
            hintText: '••••••••',
            obscureText: true,
          ),
          const SizedBox(height: 20),
          _CardActionsRow(
            testIcon: Icons.mail_outline_rounded,
            testLabel: 'Test Email',
            onTest: onTestEmail,
            onSave: onSave,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right column — Automated Trigger Rules
// ---------------------------------------------------------------------------

class _TriggerRulesCard extends StatelessWidget {
  const _TriggerRulesCard({
    required this.rules,
    required this.onChanged,
  });

  final AutomatedTriggerRulesModel rules;
  final ValueChanged<AutomatedTriggerRulesModel> onChanged;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _TriggerRuleRow(
        title: 'Early Warning Flag (ML)',
        subtitle: 'Notify guidance counselor when a student is flagged',
        value: rules.earlyWarningFlag,
        onChanged: (value) =>
            onChanged(rules.copyWith(earlyWarningFlag: value)),
      ),
      _TriggerRuleRow(
        title: 'Absence Threshold Reached',
        subtitle: 'Alert discipline officer when threshold is hit',
        value: rules.absenceThresholdReached,
        onChanged: (value) =>
            onChanged(rules.copyWith(absenceThresholdReached: value)),
      ),
      _TriggerRuleRow(
        title: 'Violation Count Exceeded',
        subtitle: 'Send alert when violation limit is reached',
        value: rules.violationCountExceeded,
        onChanged: (value) =>
            onChanged(rules.copyWith(violationCountExceeded: value)),
      ),
      _TriggerRuleRow(
        title: 'New Discipline Case Filed',
        subtitle: 'Notify admin when a new case is created',
        value: rules.newDisciplineCaseFiled,
        onChanged: (value) =>
            onChanged(rules.copyWith(newDisciplineCaseFiled: value)),
      ),
      _TriggerRuleRow(
        title: 'Daily Attendance Summary',
        subtitle: 'Send automated summary report every 5:00 PM',
        value: rules.dailyAttendanceSummary,
        onChanged: (value) =>
            onChanged(rules.copyWith(dailyAttendanceSummary: value)),
      ),
      _TriggerRuleRow(
        title: 'RFID Gateway Offline',
        subtitle: 'Alert admin immediately when a reader goes offline',
        value: rules.rfidGatewayOffline,
        onChanged: (value) =>
            onChanged(rules.copyWith(rfidGatewayOffline: value)),
      ),
      _TriggerRuleRow(
        title: 'ML Model Retrained',
        subtitle: 'Notify admin when retraining completes successfully',
        value: rules.mlModelRetrained,
        onChanged: (value) =>
            onChanged(rules.copyWith(mlModelRetrained: value)),
      ),
    ];

    return _SettingsCard(
      title: 'Automated Trigger Rules',
      subtitle: 'Enable or disable notification events',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: _NotifColors.cardBorder),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _TriggerRuleRow extends StatelessWidget {
  const _TriggerRuleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

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
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _NotifColors.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: _NotifColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: _NotifColors.primaryButton,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFE2E8F0),
            trackOutlineColor: WidgetStateProperty.resolveWith(
              (states) => Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}
