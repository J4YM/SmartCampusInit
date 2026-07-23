import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Data model — swap defaultStaffList with Supabase/API data later.
// ---------------------------------------------------------------------------

enum StaffRole {
  systemAdmin,
  disciplineOfficer,
  guidanceCounselor,
  security,
  teacher;

  String get label {
    switch (this) {
      case StaffRole.systemAdmin:
        return 'System Admin';
      case StaffRole.disciplineOfficer:
        return 'Discipline Officer';
      case StaffRole.guidanceCounselor:
        return 'Guidance Counselor';
      case StaffRole.security:
        return 'Security';
      case StaffRole.teacher:
        return 'Teacher';
    }
  }

  (Color background, Color foreground) get colors {
    switch (this) {
      case StaffRole.systemAdmin:
        return (const Color(0xFFF3E8FF), const Color(0xFF7E22CE));
      case StaffRole.disciplineOfficer:
        return (const Color(0xFFFEE2E2), const Color(0xFFDC2626));
      case StaffRole.guidanceCounselor:
        return (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8));
      case StaffRole.security:
        return (const Color(0xFFFFEDD5), const Color(0xFFC2410C));
      case StaffRole.teacher:
        return (const Color(0xFFE0F2FE), const Color(0xFF0369A1));
    }
  }
}

class StaffUserModel {
  const StaffUserModel({
    required this.staffId,
    required this.avatarInitials,
    required this.fullName,
    required this.email,
    required this.role,
    required this.department,
    required this.lastLogin,
    required this.isActive,
    required this.avatarColor,
  });

  final String staffId;
  final String avatarInitials;
  final String fullName;
  final String email;
  final StaffRole role;
  final String department;
  final DateTime lastLogin;
  final bool isActive;
  final Color avatarColor;

  StaffUserModel copyWith({bool? isActive}) {
    return StaffUserModel(
      staffId: staffId,
      avatarInitials: avatarInitials,
      fullName: fullName,
      email: email,
      role: role,
      department: department,
      lastLogin: lastLogin,
      isActive: isActive ?? this.isActive,
      avatarColor: avatarColor,
    );
  }
}

// ---------------------------------------------------------------------------
// Default dataset — replace with repository/API calls when backend is ready.
// ---------------------------------------------------------------------------

const defaultStaffList = <StaffUserModel>[];

const _roleFilters = [
  'All Roles',
  'System Admin',
  'Discipline Officer',
  'Guidance Counselor',
  'Security',
  'Teacher',
];

String _formatLastLogin(DateTime value) {
  final year = value.year;
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _StaffColors {
  static const background = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const cardBorder = Color(0xFFE2E8F0);
  static const primaryButton = Color(0xFF27426D);
  static const primaryButtonText = Color(0xFFFFFFFF);
  static const rowHover = Color(0xFFF8FAFC);
  static const headerText = Color(0xFF64748B);
  static const switchActive = Color(0xFF27426D);
}

abstract final class _StaffTableLayout {
  static const columnFlex = <int>[1, 4, 2, 2, 2, 2, 2];
  static const compactColumnIndexes = <int>{2, 5};
  static const horizontalPadding = 16.0;
  static const columnGap = 8.0;
  static const rowVerticalPadding = 12.0;
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class StaffAccountsPage extends StatefulWidget {
  const StaffAccountsPage({
    super.key,
    required this.staffList,
  });

  factory StaffAccountsPage.empty({Key? key}) {
    return StaffAccountsPage(key: key, staffList: defaultStaffList);
  }

  final List<StaffUserModel> staffList;

  @override
  State<StaffAccountsPage> createState() => _StaffAccountsPageState();
}

class _StaffAccountsPageState extends State<StaffAccountsPage> {
  late List<StaffUserModel> _staffList;
  String _selectedRole = _roleFilters.first;

  @override
  void initState() {
    super.initState();
    _staffList = List<StaffUserModel>.from(widget.staffList);
  }

  List<StaffUserModel> get _filteredStaff {
    if (_selectedRole == 'All Roles') return _staffList;
    return _staffList.where((staff) => staff.role.label == _selectedRole).toList();
  }

  void _toggleStaffAccess(int indexInFiltered, bool value) {
    final staff = _filteredStaff[indexInFiltered];
    final listIndex = _staffList.indexWhere((item) => item.staffId == staff.staffId);
    if (listIndex == -1) return;

    setState(() {
      _staffList[listIndex] = _staffList[listIndex].copyWith(isActive: value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredStaff = _filteredStaff;

    return ColoredBox(
      color: _StaffColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Staff & Faculty',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _StaffColors.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Configure staff roles, access, and account details',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: _StaffColors.secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              _StaffControlBar(
                selectedRole: _selectedRole,
                onRoleChanged: (value) =>
                    setState(() => _selectedRole = value ?? _roleFilters.first),
                onAddStaff: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Add Staff Account tapped',
                        style: GoogleFonts.poppins(color: Colors.white),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _StaffTableCard(
                  staffList: filteredStaff,
                  onToggleAccess: _toggleStaffAccess,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Control bar
// ---------------------------------------------------------------------------

class _StaffControlBar extends StatelessWidget {
  const _StaffControlBar({
    required this.selectedRole,
    required this.onRoleChanged,
    required this.onAddStaff,
  });

  final String selectedRole;
  final ValueChanged<String?> onRoleChanged;
  final VoidCallback onAddStaff;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            initialValue: selectedRole,
            onChanged: onRoleChanged,
            isExpanded: true,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: _StaffColors.primaryText,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: _StaffColors.card,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _StaffColors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _StaffColors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _StaffColors.primaryButton),
              ),
            ),
            items: _roleFilters
                .map(
                  (role) => DropdownMenuItem<String>(
                    value: role,
                    child: Text(role),
                  ),
                )
                .toList(),
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: onAddStaff,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(
            'Add Staff Account',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _StaffColors.primaryButton,
            foregroundColor: _StaffColors.primaryButtonText,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Data table
// ---------------------------------------------------------------------------

class _StaffTableCard extends StatelessWidget {
  const _StaffTableCard({
    required this.staffList,
    required this.onToggleAccess,
  });

  final List<StaffUserModel> staffList;
  final void Function(int index, bool value) onToggleAccess;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _StaffColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _StaffColors.cardBorder),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _StaffTableHeaderRow(),
            const Divider(height: 1, color: _StaffColors.cardBorder),
            Expanded(
              child: staffList.isEmpty
                  ? const _EmptyTableState(
                      icon: Icons.folder_open_rounded,
                      message: 'No records found',
                    )
                  : ListView.builder(
                      itemCount: staffList.length,
                      itemBuilder: (context, index) {
                        return _StaffTableRow(
                          staff: staffList[index],
                          showDivider: index < staffList.length - 1,
                          onToggleAccess: (value) =>
                              onToggleAccess(index, value),
                        );
                      },
                    ),
            ),
          ],
        ),
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
            Icon(icon, size: 40, color: const Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _StaffColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffTableCell extends StatelessWidget {
  const _StaffTableCell({
    required this.flex,
    required this.child,
    required this.isLast,
    this.compact = false,
    this.alignRight = false,
  });

  final int flex;
  final Widget child;
  final bool isLast;
  final bool compact;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final alignment =
        alignRight ? Alignment.centerRight : Alignment.centerLeft;

    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.only(
          right: isLast ? 0 : _StaffTableLayout.columnGap,
        ),
        child: compact
            ? Align(alignment: alignment, child: child)
            : Align(
                alignment: alignment,
                widthFactor: alignRight ? null : 1,
                child: child,
              ),
      ),
    );
  }
}

class _StaffTableHeaderRow extends StatelessWidget {
  const _StaffTableHeaderRow();

  @override
  Widget build(BuildContext context) {
    const headers = [
      'ID',
      'NAME',
      'ROLE',
      'DEPARTMENT',
      'LAST LOGIN',
      'STATUS',
      'ACCESS TOGGLE',
    ];
    const flexValues = _StaffTableLayout.columnFlex;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _StaffTableLayout.horizontalPadding,
        vertical: _StaffTableLayout.rowVerticalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < headers.length; i++)
            _StaffTableCell(
              flex: flexValues[i],
              isLast: i == headers.length - 1,
              compact: _StaffTableLayout.compactColumnIndexes.contains(i),
              alignRight: i == headers.length - 1,
              child: Text(
                headers[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: _StaffColors.headerText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StaffTableRow extends StatelessWidget {
  const _StaffTableRow({
    required this.staff,
    required this.showDivider,
    required this.onToggleAccess,
  });

  final StaffUserModel staff;
  final bool showDivider;
  final ValueChanged<bool> onToggleAccess;

  @override
  Widget build(BuildContext context) {
    const flexValues = _StaffTableLayout.columnFlex;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        hoverColor: _StaffColors.rowHover,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        mouseCursor: SystemMouseCursors.basic,
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            border: showDivider
                ? const Border(
                    bottom: BorderSide(color: _StaffColors.cardBorder),
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _StaffTableLayout.horizontalPadding,
              vertical: _StaffTableLayout.rowVerticalPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _StaffTableCell(
                  flex: flexValues[0],
                  isLast: false,
                  child: Text(
                    staff.staffId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _StaffColors.secondaryText,
                    ),
                  ),
                ),
                _StaffTableCell(
                  flex: flexValues[1],
                  isLast: false,
                  child: Row(
                    children: [
                      _StaffAvatar(
                        initials: staff.avatarInitials,
                        color: staff.avatarColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              staff.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _StaffColors.primaryText,
                              ),
                            ),
                            Text(
                              staff.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: _StaffColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _StaffTableCell(
                  flex: flexValues[2],
                  isLast: false,
                  compact: true,
                  child: _RoleBadge(role: staff.role),
                ),
                _StaffTableCell(
                  flex: flexValues[3],
                  isLast: false,
                  child: Text(
                    staff.department,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: _StaffColors.primaryText,
                    ),
                  ),
                ),
                _StaffTableCell(
                  flex: flexValues[4],
                  isLast: false,
                  child: Text(
                    _formatLastLogin(staff.lastLogin),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: _StaffColors.secondaryText,
                    ),
                  ),
                ),
                _StaffTableCell(
                  flex: flexValues[5],
                  isLast: false,
                  compact: true,
                  child: _StaffStatusBadge(isActive: staff.isActive),
                ),
                _StaffTableCell(
                  flex: flexValues[6],
                  isLast: true,
                  alignRight: true,
                  child: Switch(
                    value: staff.isActive,
                    onChanged: onToggleAccess,
                    activeThumbColor: Colors.white,
                    activeTrackColor: _StaffColors.switchActive,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFFE2E8F0),
                    trackOutlineColor: WidgetStateProperty.resolveWith(
                      (states) => Colors.transparent,
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

class _StaffAvatar extends StatelessWidget {
  const _StaffAvatar({
    required this.initials,
    required this.color,
  });

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final StaffRole role;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = role.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        role.label,
        softWrap: false,
        maxLines: 1,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

class _StaffStatusBadge extends StatelessWidget {
  const _StaffStatusBadge({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final background =
        isActive ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9);
    final foreground =
        isActive ? const Color(0xFF15803D) : const Color(0xFF64748B);
    final label = isActive ? 'Active' : 'Inactive';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        softWrap: false,
        maxLines: 1,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
