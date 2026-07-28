import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Data model — swap defaultAuditLogs with Supabase/API data later.
// fromJson/toJson keep this round-trippable with an `audit_logs` table.
// ---------------------------------------------------------------------------

class AuditLogModel {
  const AuditLogModel({
    required this.id,
    required this.timestamp,
    required this.userEmail,
    required this.userRole,
    required this.actionExecuted,
    required this.ipAddress,
    required this.recordId,
    required this.severity,
  });

  final String id;
  final DateTime timestamp;
  final String userEmail;
  final String userRole;
  final String actionExecuted;
  final String ipAddress;
  final String recordId;
  final String severity; // 'INFO', 'WARN', 'CRITICAL'

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    return AuditLogModel(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      userEmail: json['userEmail'] as String,
      userRole: json['userRole'] as String,
      actionExecuted: json['actionExecuted'] as String,
      ipAddress: json['ipAddress'] as String,
      recordId: json['recordId'] as String,
      severity: json['severity'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'userEmail': userEmail,
        'userRole': userRole,
        'actionExecuted': actionExecuted,
        'ipAddress': ipAddress,
        'recordId': recordId,
        'severity': severity,
      };
}

// ---------------------------------------------------------------------------
// Default (empty) dataset — replace with repository/API calls when backend
// is ready.
// ---------------------------------------------------------------------------

const defaultAuditLogs = <AuditLogModel>[];

const _severityOptions = ['INFO', 'WARN', 'CRITICAL'];
const _roleOptions = [
  'System Admin',
  'Discipline Officer',
  'Guidance Counselor',
  'Security',
];

String _formatTimestamp(DateTime value) {
  final year = value.year;
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}

String _formatShortDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day/${value.year}';
}

TextStyle _monoTableStyle({Color? color, FontWeight? weight}) {
  return GoogleFonts.poppins(
    fontSize: 12,
    fontWeight: weight ?? FontWeight.w500,
    letterSpacing: 0.2,
    color: color ?? _AuditColors.secondaryText,
  );
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _AuditColors {
  static const background = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const cardBorder = Color(0xFFE2E8F0);
  static const fieldFill = Color(0xFFF1F5F9);
  static const primaryAccent = Color(0xFF27426D);
  static const headerText = Color(0xFF64748B);
  static const emptyStateIcon = Color(0xFFCBD5E1);
  static const infoBadgeBg = Color(0xFFDBEAFE);
  static const infoBadgeText = Color(0xFF1D4ED8);
  static const warnBadgeBg = Color(0xFFFFEDD5);
  static const warnBadgeText = Color(0xFFEA580C);
  static const criticalBadgeBg = Color(0xFFFEE2E2);
  static const criticalBadgeText = Color(0xFFDC2626);
}

abstract final class _AuditTableLayout {
  // TIMESTAMP, USER/ROLE, ACTION EXECUTED, IP ADDRESS, RECORD ID, SEVERITY
  static const columnFlex = <int>[3, 4, 5, 3, 3, 2];
  static const compactColumnIndexes = <int>{5};
  static const horizontalPadding = 16.0;
  static const columnGap = 8.0;
  static const headerHeight = 48.0;
  static const rowMinHeight = 60.0;
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class AuditLogsPage extends StatefulWidget {
  const AuditLogsPage({
    super.key,
    required this.auditLogs,
  });

  factory AuditLogsPage.empty({Key? key}) {
    return AuditLogsPage(key: key, auditLogs: defaultAuditLogs);
  }

  final List<AuditLogModel> auditLogs;

  @override
  State<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<AuditLogsPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedSeverity;
  String? _selectedRole;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AuditLogModel> get _filteredLogs {
    final query = _searchQuery.trim().toLowerCase();
    return widget.auditLogs.where((log) {
      final matchesSearch = query.isEmpty ||
          log.actionExecuted.toLowerCase().contains(query) ||
          log.userEmail.toLowerCase().contains(query) ||
          log.recordId.toLowerCase().contains(query);
      final matchesSeverity =
          _selectedSeverity == null || log.severity == _selectedSeverity;
      final matchesRole = _selectedRole == null || log.userRole == _selectedRole;
      final matchesStart =
          _startDate == null || !log.timestamp.isBefore(_startDate!);
      final matchesEnd = _endDate == null ||
          log.timestamp.isBefore(_endDate!.add(const Duration(days: 1)));
      return matchesSearch &&
          matchesSeverity &&
          matchesRole &&
          matchesStart &&
          matchesEnd;
    }).toList();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _filteredLogs;

    return ColoredBox(
      color: _AuditColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Audit & Privacy Logs',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _AuditColors.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Inspect audit trails and privacy-related events.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: _AuditColors.secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              _FilterToolbar(
                searchController: _searchController,
                onSearchChanged: (value) =>
                    setState(() => _searchQuery = value),
                selectedSeverity: _selectedSeverity,
                onSeverityChanged: (value) =>
                    setState(() => _selectedSeverity = value),
                selectedRole: _selectedRole,
                onRoleChanged: (value) => setState(() => _selectedRole = value),
                startDate: _startDate,
                endDate: _endDate,
                onPickStartDate: _pickStartDate,
                onPickEndDate: _pickEndDate,
                entryCount: filteredLogs.length,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _AuditLogTableCard(logs: filteredLogs),
              ),
              const SizedBox(height: 12),
              _TableFooterBar(
                showingCount: filteredLogs.length,
                totalCount: widget.auditLogs.length,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter toolbar
// ---------------------------------------------------------------------------

class _FilterToolbar extends StatelessWidget {
  const _FilterToolbar({
    required this.searchController,
    required this.onSearchChanged,
    required this.selectedSeverity,
    required this.onSeverityChanged,
    required this.selectedRole,
    required this.onRoleChanged,
    required this.startDate,
    required this.endDate,
    required this.onPickStartDate,
    required this.onPickEndDate,
    required this.entryCount,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String? selectedSeverity;
  final ValueChanged<String?> onSeverityChanged;
  final String? selectedRole;
  final ValueChanged<String?> onRoleChanged;
  final DateTime? startDate;
  final DateTime? endDate;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickEndDate;
  final int entryCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _AuditColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _AuditColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchField(
            controller: searchController,
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 170,
                      child: _FilterDropdown(
                        hintLabel: 'All Severities',
                        value: selectedSeverity,
                        options: _severityOptions,
                        onChanged: onSeverityChanged,
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: _FilterDropdown(
                        hintLabel: 'All Roles',
                        value: selectedRole,
                        options: _roleOptions,
                        onChanged: onRoleChanged,
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: _DateField(
                        value: startDate,
                        onTap: onPickStartDate,
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: _DateField(
                        value: endDate,
                        onTap: onPickEndDate,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _EntryCountBadge(count: entryCount),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: GoogleFonts.poppins(
        fontSize: 14,
        color: _AuditColors.primaryText,
      ),
      decoration: InputDecoration(
        hintText: 'Search action, user, or record ID...',
        hintStyle: GoogleFonts.poppins(
          fontSize: 14,
          color: _AuditColors.secondaryText,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 20,
          color: _AuditColors.secondaryText,
        ),
        filled: true,
        fillColor: _AuditColors.fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _AuditColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _AuditColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _AuditColors.primaryAccent),
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.hintLabel,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String hintLabel;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      value: value,
      onChanged: onChanged,
      isExpanded: true,
      style: GoogleFonts.poppins(
        fontSize: 13,
        color: _AuditColors.primaryText,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: _AuditColors.fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _AuditColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _AuditColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _AuditColors.primaryAccent),
        ),
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(hintLabel, overflow: TextOverflow.ellipsis),
        ),
        for (final option in options)
          DropdownMenuItem<String?>(
            value: option,
            child: Text(option, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.onTap,
  });

  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _AuditColors.fieldFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _AuditColors.cardBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null ? 'mm/dd/yyyy' : _formatShortDate(value!),
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: value == null
                      ? _AuditColors.secondaryText
                      : _AuditColors.primaryText,
                ),
              ),
            ),
            const Icon(
              Icons.calendar_today_rounded,
              size: 15,
              color: _AuditColors.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCountBadge extends StatelessWidget {
  const _EntryCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _AuditColors.fieldFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _AuditColors.cardBorder),
      ),
      child: Text(
        '$count records',
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _AuditColors.primaryText,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data table
// ---------------------------------------------------------------------------

class _AuditLogTableCard extends StatelessWidget {
  const _AuditLogTableCard({required this.logs});

  final List<AuditLogModel> logs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _AuditColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _AuditColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TableHeaderRow(),
          Expanded(
            child: logs.isEmpty
                ? const _EmptyTableState(
                    icon: Icons.history_toggle_off_rounded,
                    message: 'No log records found',
                  )
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      return _AuditLogTableRow(
                        log: logs[index],
                        showDivider: index < logs.length - 1,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTableState extends StatelessWidget {
  const _EmptyTableState({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: _AuditColors.emptyStateIcon),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _AuditColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell({
    required this.flex,
    required this.child,
    required this.isLast,
    this.compact = false,
  });

  final int flex;
  final Widget child;
  final bool isLast;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.only(
          right: isLast ? 0 : _AuditTableLayout.columnGap,
        ),
        child: compact
            ? Align(alignment: Alignment.centerLeft, child: child)
            : Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: child,
              ),
      ),
    );
  }
}

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    const headers = [
      'TIMESTAMP',
      'USER / ROLE',
      'ACTION EXECUTED',
      'IP ADDRESS',
      'RECORD ID',
      'SEVERITY',
    ];

    return Container(
      width: double.infinity,
      height: _AuditTableLayout.headerHeight,
      padding:
          const EdgeInsets.symmetric(horizontal: _AuditTableLayout.horizontalPadding),
      decoration: const BoxDecoration(
        color: _AuditColors.card,
        border: Border(
          bottom: BorderSide(color: _AuditColors.cardBorder),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < headers.length; i++)
            _TableCell(
              flex: _AuditTableLayout.columnFlex[i],
              isLast: i == headers.length - 1,
              compact: _AuditTableLayout.compactColumnIndexes.contains(i),
              child: Text(
                headers[i],
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: _AuditColors.headerText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AuditLogTableRow extends StatelessWidget {
  const _AuditLogTableRow({
    required this.log,
    required this.showDivider,
  });

  final AuditLogModel log;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    const flexValues = _AuditTableLayout.columnFlex;

    return Container(
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                bottom: BorderSide(color: _AuditColors.cardBorder),
              )
            : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: _AuditTableLayout.rowMinHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _AuditTableLayout.horizontalPadding,
            vertical: 10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _TableCell(
                flex: flexValues[0],
                isLast: false,
                child: Text(
                  _formatTimestamp(log.timestamp),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _monoTableStyle(),
                ),
              ),
              _TableCell(
                flex: flexValues[1],
                isLast: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      log.userEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _monoTableStyle(
                        color: _AuditColors.primaryText,
                        weight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      log.userRole,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: _AuditColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              _TableCell(
                flex: flexValues[2],
                isLast: false,
                child: Text(
                  log.actionExecuted,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: _AuditColors.primaryText,
                  ),
                ),
              ),
              _TableCell(
                flex: flexValues[3],
                isLast: false,
                child: Text(
                  log.ipAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _monoTableStyle(),
                ),
              ),
              _TableCell(
                flex: flexValues[4],
                isLast: false,
                child: Text(
                  log.recordId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _monoTableStyle(),
                ),
              ),
              _TableCell(
                flex: flexValues[5],
                isLast: true,
                compact: true,
                child: _SeverityBadge(severity: log.severity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity});

  final String severity;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (severity) {
      'WARN' => (_AuditColors.warnBadgeBg, _AuditColors.warnBadgeText),
      'CRITICAL' => (
          _AuditColors.criticalBadgeBg,
          _AuditColors.criticalBadgeText,
        ),
      _ => (_AuditColors.infoBadgeBg, _AuditColors.infoBadgeText),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        severity,
        softWrap: false,
        maxLines: 1,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: foreground,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer bar
// ---------------------------------------------------------------------------

class _TableFooterBar extends StatelessWidget {
  const _TableFooterBar({
    required this.showingCount,
    required this.totalCount,
  });

  final int showingCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Showing $showingCount of $totalCount entries',
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _AuditColors.secondaryText,
          ),
        ),
        const Spacer(),
        const _PaginationButton(label: 'Previous', onPressed: null),
        const SizedBox(width: 8),
        const _PaginationButton(label: 'Next', onPressed: null),
      ],
    );
  }
}

class _PaginationButton extends StatelessWidget {
  const _PaginationButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _AuditColors.secondaryText,
        disabledForegroundColor: _AuditColors.secondaryText.withOpacity(0.5),
        side: const BorderSide(color: _AuditColors.cardBorder),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
