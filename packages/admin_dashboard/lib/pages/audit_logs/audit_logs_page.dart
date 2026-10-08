import 'package:dashboard_layout/dashboard_layout.dart';
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
  'Student Affairs & Services',
  'Guidance Counselor',
  'Security',
];

String _formatTimestamp(DateTime value) =>
    formatDateTime12h(value, seconds: true);

String _formatShortDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day/${value.year}';
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _AuditColors {
  static const primaryAccent = Color(0xFF345892);
  static Color background(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF191A1F) : const Color(0xFFFFFFFF);
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
  static Color cardBorder(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF22242B) : const Color(0x0DE2E8F0);
  static Color fieldFill(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);
  // Shared brand accent (the same blue every other dashboard's buttons use)
  // — stays constant across themes, like every other dashboard's own accent.
  static Color infoBadgeBg(BuildContext context) =>
      context.isDarkMode ? const Color(0x4D1D4ED8) : const Color(0xFFDBEAFE);
  static Color infoBadgeText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);
  static Color warnBadgeBg(BuildContext context) =>
      context.isDarkMode ? const Color(0x4DEA580C) : const Color(0xFFFFEDD5);
  static Color warnBadgeText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFDBA74) : const Color(0xFFEA580C);
  static Color criticalBadgeBg(BuildContext context) =>
      context.isDarkMode ? const Color(0x4DDC2626) : const Color(0xFFFEE2E2);
  static Color criticalBadgeText(BuildContext context) =>
      kDangerTextColor;
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

  int get _pageSize => context.cardPageSize;
  int _currentPage = 1;

  /// Applies a filter change and returns to page 1 — the old page number
  /// may not exist in the newly filtered list.
  void _refilter(VoidCallback change) => setState(() {
        change();
        _currentPage = 1;
      });

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
      final matchesRole =
          _selectedRole == null || log.userRole == _selectedRole;
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
    if (picked != null) _refilter(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) _refilter(() => _endDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _filteredLogs;
    final totalPages =
        filteredLogs.isEmpty ? 1 : (filteredLogs.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageLogs = filteredLogs
        .skip((currentPage - 1) * _pageSize)
        .take(_pageSize)
        .toList();

    return ColoredBox(
      color: _AuditColors.background(context),
      child: SafeArea(
        // The table fills whatever height is left under the title and
        // filters. On a phone the filters wrap into a tall block, which used
        // to leave the table a sliver — so the page scrolls instead once it
        // is shorter than this, giving the table at least ~440px.
        child: DashboardPageScrollView(
          fill: true,
          minHeight: context.isMobileWidth ? 900 : kDashboardMinFillHeight,
          // The standard 1440px-capped, centered frame, matching every other
          // admin page's inner content.
          child: DashboardPageWrapper(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Audit & Privacy Logs',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _AuditColors.primaryText(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Inspect audit trails and privacy-related events.',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 12 : 14,
                  fontWeight: FontWeight.w400,
                  color: _AuditColors.secondaryText(context),
                ),
              ),
              const SizedBox(height: 24),
              _FilterToolbar(
                searchController: _searchController,
                onSearchChanged: (value) =>
                    _refilter(() => _searchQuery = value),
                selectedSeverity: _selectedSeverity,
                onSeverityChanged: (value) =>
                    _refilter(() => _selectedSeverity = value),
                selectedRole: _selectedRole,
                onRoleChanged: (value) =>
                    _refilter(() => _selectedRole = value),
                startDate: _startDate,
                endDate: _endDate,
                onPickStartDate: _pickStartDate,
                onPickEndDate: _pickEndDate,
                entryCount: filteredLogs.length,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _AuditLogTableCard(
                  logs: pageLogs,
                  footer: filteredLogs.isEmpty
                      ? null
                      : CardPaginationFooter(
                          currentPage: currentPage,
                          totalPages: totalPages,
                          totalCount: filteredLogs.length,
                          textColor: _AuditColors.secondaryText(context),
                          accentColor: _AuditColors.primaryAccent,
                          mutedBackground: _AuditColors.fieldFill(context),
                          onPrevious: () =>
                              setState(() => _currentPage = currentPage - 1),
                          onNext: () =>
                              setState(() => _currentPage = currentPage + 1),
                        ),
                ),
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
    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: _AuditColors.card(context),
        borderColor: _AuditColors.cardBorder(context),
        padding: const EdgeInsets.all(16),
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
      expands: true,
      maxLines: null,
      minLines: null,
      textAlignVertical: TextAlignVertical.center,
      controller: controller,
      onChanged: onChanged,
      style: GoogleFonts.poppins(
        fontSize: 12,
        color: _AuditColors.primaryText(context),
      ),
      decoration: InputDecoration(
        isDense: true,
        constraints: const BoxConstraints.tightFor(height: kDashboardControlHeight),
        hintText: 'Search action, user, or record ID...',
        hintStyle: GoogleFonts.poppins(
          fontSize: 12,
          color: _AuditColors.secondaryText(context),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 16,
          color: _AuditColors.secondaryText(context),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 38),
        filled: true,
        fillColor: _AuditColors.fieldFill(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _AuditColors.cardBorder(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _AuditColors.cardBorder(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _AuditColors.primaryAccent),
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
    return DashboardDropdown<String?>(
      value: value,
      onChanged: onChanged,
      fillColor: _AuditColors.fieldFill(context),
      borderColor: _AuditColors.cardBorder(context),
      textStyle: GoogleFonts.poppins(
        fontSize: 12,
        color: _AuditColors.primaryText(context),
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
        height: kDashboardControlHeight,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _AuditColors.fieldFill(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _AuditColors.cardBorder(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null ? 'mm/dd/yyyy' : _formatShortDate(value!),
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: value == null
                      ? _AuditColors.secondaryText(context)
                      : _AuditColors.primaryText(context),
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_rounded,
              size: 15,
              color: _AuditColors.secondaryText(context),
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
      height: kDashboardControlHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _AuditColors.fieldFill(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _AuditColors.cardBorder(context)),
      ),
      child: Text(
        '$count records',
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 10 : 12,
          fontWeight: FontWeight.w600,
          color: _AuditColors.primaryText(context),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data table
// ---------------------------------------------------------------------------

class _AuditLogTableCard extends StatelessWidget {
  const _AuditLogTableCard({required this.logs, this.footer});

  final List<AuditLogModel> logs;

  /// Pagination row pinned to the bottom of the card, under the rows.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: _AuditColors.card(context),
        borderColor: _AuditColors.cardBorder(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DashboardTableSection(
              columns: _auditColumns,
              topBorder: false,
              expandBody: true,
              body: logs.isEmpty
                  ? const DashboardTableEmptyState(
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
            if (footer != null) DashboardTableFooter(child: footer!),
          ],
        ),
      ),
    );
  }
}

const _auditColumns = <DashboardTableColumn>[
  DashboardTableColumn('Timestamp', flex: 3, minWidth: 160),
  DashboardTableColumn('User / Role', flex: 4, minWidth: 190),
  DashboardTableColumn('Action Executed', flex: 5, minWidth: 240),
  DashboardTableColumn('IP Address', flex: 3, minWidth: 130),
  DashboardTableColumn('Record ID', flex: 3, minWidth: 130),
  DashboardTableColumn('Severity', flex: 2, compact: true, minWidth: 100),
];

class _AuditLogTableRow extends StatelessWidget {
  const _AuditLogTableRow({
    required this.log,
    required this.showDivider,
  });

  final AuditLogModel log;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return DashboardTableRow(
      columns: _auditColumns,
      showDivider: showDivider,
      cells: [
        Text(
          _formatTimestamp(log.timestamp),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableMetaStyle(context),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              log.userEmail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dashboardTablePrimaryStyle(context),
            ),
            Text(
              log.userRole,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dashboardTableSubStyle(context),
            ),
          ],
        ),
        Tooltip(
          message: log.actionExecuted,
          child: Text(
            log.actionExecuted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dashboardTableBodyStyle(context),
          ),
        ),
        Text(
          log.ipAddress,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableMetaStyle(context),
        ),
        Text(
          log.recordId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableIdStyle(context),
        ),
        _SeverityBadge(severity: log.severity),
      ],
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity});

  final String severity;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (severity) {
      'WARN' => (_AuditColors.warnBadgeBg(context), _AuditColors.warnBadgeText(context)),
      'CRITICAL' => (
          _AuditColors.criticalBadgeBg(context),
          _AuditColors.criticalBadgeText(context),
        ),
      _ => (_AuditColors.infoBadgeBg(context), _AuditColors.infoBadgeText(context)),
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
          fontSize: context.isMobileWidth ? 8 : 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: foreground,
        ),
      ),
    );
  }
}
