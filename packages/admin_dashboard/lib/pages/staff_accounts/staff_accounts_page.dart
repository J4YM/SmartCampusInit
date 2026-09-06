import 'package:dashboard_layout/dashboard_layout.dart';
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
  teacher,
  registrar,
  itTechnician;

  String get label {
    switch (this) {
      case StaffRole.systemAdmin:
        return 'System Admin';
      case StaffRole.disciplineOfficer:
        return 'Student Affairs & Services';
      case StaffRole.guidanceCounselor:
        return 'Guidance Counselor';
      case StaffRole.security:
        return 'Security';
      case StaffRole.teacher:
        return 'Teacher';
      case StaffRole.registrar:
        return 'Registrar';
      case StaffRole.itTechnician:
        return 'IT Technician';
    }
  }

  /// Light-mode pair — usable without a [BuildContext], e.g. by data-mapping
  /// code that assigns a static avatar tint once, outside the widget tree
  /// (see `staff_accounts_connected_page.dart`'s `_toStaffUserModel`).
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
      case StaffRole.registrar:
        return (const Color(0xFFFEF9C3), const Color(0xFF854D0E));
      case StaffRole.itTechnician:
        return (const Color(0xFFCCFBF1), const Color(0xFF0F766E));
    }
  }

  /// Dark-mode-aware pair for actual UI rendering (the role badge).
  (Color background, Color foreground) colorsFor(BuildContext context) {
    if (!context.isDarkMode) return colors;
    switch (this) {
      case StaffRole.systemAdmin:
        return (const Color(0x4D7E22CE), const Color(0xFFD8B4FE));
      case StaffRole.disciplineOfficer:
        return (const Color(0x4DDC2626), const Color(0xFFFCA5A5));
      case StaffRole.guidanceCounselor:
        return (const Color(0x4D1D4ED8), const Color(0xFF93C5FD));
      case StaffRole.security:
        return (const Color(0x4DC2410C), const Color(0xFFFDBA74));
      case StaffRole.teacher:
        return (const Color(0x4D0369A1), const Color(0xFF7DD3FC));
      case StaffRole.registrar:
        return (const Color(0x4D854D0E), const Color(0xFFFDE047));
      case StaffRole.itTechnician:
        return (const Color(0x4D0F766E), const Color(0xFF5EEAD4));
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

/// A staff sign-in awaiting admin approval — no role/access fields yet since
/// those are only assigned once an admin approves it (the specific role
/// can't be derived from an email address alone).
class PendingStaffModel {
  const PendingStaffModel({
    required this.userId,
    required this.avatarInitials,
    required this.fullName,
    required this.email,
    required this.department,
    required this.requestedAt,
  });

  final String userId;
  final String avatarInitials;
  final String fullName;
  final String? email;
  final String? department;
  final DateTime? requestedAt;
}

// ---------------------------------------------------------------------------
// Default dataset — replace with repository/API calls when backend is ready.
// ---------------------------------------------------------------------------

const defaultStaffList = <StaffUserModel>[];
const defaultPendingStaff = <PendingStaffModel>[];

const _roleFilters = [
  'All Roles',
  'System Admin',
  'Student Affairs & Services',
  'Guidance Counselor',
  'Security',
  'Teacher',
  'Registrar',
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
  // Shared brand accent (the same blue every other dashboard's buttons use)
  // — stays constant across themes, like every other dashboard's own accent.
  static const primaryButton = Color(0xFF345892);
  static const primaryButtonText = Color(0xFFFFFFFF);
  static Color rowHover(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF22242B) : const Color(0xFFF8FAFC);
  static Color headerText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
  static const switchActive = Color(0xFF345892);
  static Color pendingBadgeBg(BuildContext context) => context.isDarkMode
      ? const Color(0x4DEA580C)
      : const Color(0xFFFFEDD5);
  static Color pendingBadgeText(BuildContext context) => context.isDarkMode
      ? const Color(0xFFFDBA74)
      : const Color(0xFFEA580C);
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
    this.pendingStaff = const [],
    this.onApprovePending,
    this.onBatchApprovePending,
    this.onApproveAllPending,
    this.onToggleAccess,
    this.isBusy = false,
    this.isLoading = false,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount,
    this.onPreviousPage,
    this.onNextPage,
    this.onRoleFilterChanged,
  });

  factory StaffAccountsPage.empty({Key? key}) {
    return StaffAccountsPage(key: key, staffList: defaultStaffList);
  }

  final List<StaffUserModel> staffList;

  /// Staff sign-ins awaiting approval + role assignment.
  final List<PendingStaffModel> pendingStaff;

  /// Approves a single pending user with the chosen role. When omitted (the
  /// `.empty()` demo path), the pending-approvals section is inert.
  final Future<void> Function(String userId, StaffRole role)? onApprovePending;

  /// Approves several pending users at once, each with its own chosen role
  /// (userId -> role).
  final Future<void> Function(Map<String, StaffRole> selections)?
      onBatchApprovePending;

  /// Approves every currently pending user with one shared role. The caller
  /// is responsible for confirming this with the admin first.
  final Future<void> Function(StaffRole role)? onApproveAllPending;

  /// Persists an active/inactive toggle. When omitted, the toggle only
  /// updates local state (demo behavior).
  final Future<void> Function(String staffId, bool value)? onToggleAccess;

  /// True while a parent-level refresh/mutation is in flight.
  final bool isBusy;

  /// True while a parent-level page fetch is in flight — renders skeleton
  /// rows instead of freezing on an unchanged table.
  final bool isLoading;

  /// Pagination state for the approved-staff roster table, supplied by a
  /// connected page that fetches one page at a time. The footer only
  /// renders when [totalPages] > 1 or a page-change callback is supplied.
  final int currentPage;
  final int totalPages;
  final int? totalCount;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;

  /// Notified alongside the role filter dropdown's own local state, so a
  /// connected page can re-query the server for this filter (paginated
  /// results only cover one page at a time).
  final ValueChanged<String>? onRoleFilterChanged;

  @override
  State<StaffAccountsPage> createState() => _StaffAccountsPageState();
}

class _StaffAccountsPageState extends State<StaffAccountsPage> {
  late List<StaffUserModel> _staffList;
  late List<PendingStaffModel> _pendingStaff;
  String _selectedRole = _roleFilters.first;

  final Map<String, StaffRole?> _pendingRoleChoice = {};
  final Set<String> _batchSelection = {};
  final Set<String> _rowBusy = {};
  StaffRole? _approveAllRole;
  bool _approveAllBusy = false;

  @override
  void initState() {
    super.initState();
    _staffList = List<StaffUserModel>.from(widget.staffList);
    _pendingStaff = List<PendingStaffModel>.from(widget.pendingStaff);
  }

  @override
  void didUpdateWidget(covariant StaffAccountsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.staffList, widget.staffList)) {
      _staffList = List<StaffUserModel>.from(widget.staffList);
    }
    if (!identical(oldWidget.pendingStaff, widget.pendingStaff)) {
      _pendingStaff = List<PendingStaffModel>.from(widget.pendingStaff);
      _batchSelection.removeWhere(
        (id) => !_pendingStaff.any((p) => p.userId == id),
      );
      _pendingRoleChoice.removeWhere(
        (id, _) => !_pendingStaff.any((p) => p.userId == id),
      );
    }
  }

  List<StaffUserModel> get _filteredStaff {
    if (_selectedRole == 'All Roles') return _staffList;
    return _staffList
        .where((staff) => staff.role.label == _selectedRole)
        .toList();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleStaffAccess(int indexInFiltered, bool value) async {
    final staff = _filteredStaff[indexInFiltered];
    final listIndex =
        _staffList.indexWhere((item) => item.staffId == staff.staffId);
    if (listIndex == -1) return;

    setState(() {
      _staffList[listIndex] = _staffList[listIndex].copyWith(isActive: value);
    });

    final onToggleAccess = widget.onToggleAccess;
    if (onToggleAccess == null) return;

    try {
      await onToggleAccess(staff.staffId, value);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _staffList[listIndex] =
            _staffList[listIndex].copyWith(isActive: !value);
      });
      _showSnackBar('Could not update access for ${staff.fullName}: $e');
    }
  }

  Future<void> _approveOne(String userId) async {
    final role = _pendingRoleChoice[userId];
    final onApprovePending = widget.onApprovePending;
    if (role == null || onApprovePending == null) return;

    setState(() => _rowBusy.add(userId));
    try {
      await onApprovePending(userId, role);
      if (!mounted) return;
      setState(() {
        _pendingStaff.removeWhere((p) => p.userId == userId);
        _pendingRoleChoice.remove(userId);
        _batchSelection.remove(userId);
      });
    } catch (e) {
      _showSnackBar('Could not approve account: $e');
    } finally {
      if (mounted) setState(() => _rowBusy.remove(userId));
    }
  }

  Future<void> _approveSelectedBatch() async {
    final onBatchApprovePending = widget.onBatchApprovePending;
    if (onBatchApprovePending == null || _batchSelection.isEmpty) return;

    final selections = <String, StaffRole>{};
    for (final id in _batchSelection) {
      final role = _pendingRoleChoice[id];
      if (role == null) {
        _showSnackBar(
            'Choose a role for every selected account before approving.');
        return;
      }
      selections[id] = role;
    }

    setState(() => _rowBusy.addAll(_batchSelection));
    try {
      await onBatchApprovePending(selections);
      if (!mounted) return;
      setState(() {
        _pendingStaff.removeWhere((p) => selections.containsKey(p.userId));
        for (final id in selections.keys) {
          _pendingRoleChoice.remove(id);
        }
        _batchSelection.clear();
      });
    } catch (e) {
      _showSnackBar('Could not approve selected accounts: $e');
    } finally {
      if (mounted) setState(() => _rowBusy.removeAll(selections.keys));
    }
  }

  Future<void> _approveAll() async {
    final onApproveAllPending = widget.onApproveAllPending;
    final role = _approveAllRole;
    if (onApproveAllPending == null || role == null || _pendingStaff.isEmpty)
      return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve all pending accounts?'),
        content: Text(
          'This assigns "${role.label}" to all ${_pendingStaff.length} pending '
          'accounts below. This cannot be undone from here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _approveAllBusy = true);
    try {
      await onApproveAllPending(role);
      if (!mounted) return;
      setState(() {
        _pendingStaff.clear();
        _pendingRoleChoice.clear();
        _batchSelection.clear();
      });
    } catch (e) {
      _showSnackBar('Could not approve all pending accounts: $e');
    } finally {
      if (mounted) setState(() => _approveAllBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredStaff = _filteredStaff;

    return ColoredBox(
      color: _StaffColors.background(context),
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
                  'Staff & Faculty',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _StaffColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Configure staff roles, access, and account details',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 12 : 14,
                    fontWeight: FontWeight.w400,
                    color: _StaffColors.secondaryText(context),
                  ),
                ),
                if (_pendingStaff.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _PendingApprovalsSection(
                    pendingStaff: _pendingStaff,
                    roleChoices: _pendingRoleChoice,
                    batchSelection: _batchSelection,
                    rowBusy: _rowBusy,
                    approveAllRole: _approveAllRole,
                    approveAllBusy: _approveAllBusy,
                    canApproveSingle: widget.onApprovePending != null,
                    canApproveBatch: widget.onBatchApprovePending != null,
                    canApproveAll: widget.onApproveAllPending != null,
                    onRoleChosen: (userId, role) =>
                        setState(() => _pendingRoleChoice[userId] = role),
                    onSelectionChanged: (userId, selected) => setState(() {
                      if (selected) {
                        _batchSelection.add(userId);
                      } else {
                        _batchSelection.remove(userId);
                      }
                    }),
                    onApproveOne: _approveOne,
                    onApproveSelected: _approveSelectedBatch,
                    onApproveAllRoleChanged: (role) =>
                        setState(() => _approveAllRole = role),
                    onApproveAll: _approveAll,
                  ),
                ],
                const SizedBox(height: 24),
                _StaffControlBar(
                  selectedRole: _selectedRole,
                  onRoleChanged: (value) {
                    final role = value ?? _roleFilters.first;
                    setState(() => _selectedRole = role);
                    widget.onRoleFilterChanged?.call(role);
                  },
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
                _StaffTableCard(
                  staffList: filteredStaff,
                  isLoading: widget.isLoading,
                  onToggleAccess: (index, value) {
                    _toggleStaffAccess(index, value);
                  },
                ),
                if (widget.totalPages > 1 ||
                    widget.onPreviousPage != null ||
                    widget.onNextPage != null) ...[
                  const SizedBox(height: 12),
                  _StaffPaginationFooter(
                    currentPage: widget.currentPage,
                    totalPages: widget.totalPages,
                    totalCount: widget.totalCount,
                    isLoading: widget.isLoading,
                    onPrevious: widget.onPreviousPage,
                    onNext: widget.onNextPage,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffPaginationFooter extends StatelessWidget {
  const _StaffPaginationFooter({
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.isLoading,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int totalPages;
  final int? totalCount;
  final bool isLoading;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          totalCount == null
              ? 'Page $currentPage of $totalPages'
              : 'Page $currentPage of $totalPages · $totalCount total',
          style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 10 : 12, color: _StaffColors.secondaryText(context)),
        ),
        Row(
          children: [
            PaginationPillButton(
              label: 'Previous',
              background: _StaffColors.background(context),
              foreground: _StaffColors.primaryButton,
              onTap: (isLoading || currentPage <= 1) ? null : onPrevious,
            ),
            const SizedBox(width: 8),
            PaginationPillButton(
              label: 'Next',
              background: _StaffColors.primaryButton,
              foreground: Colors.white,
              onTap:
                  (isLoading || currentPage >= totalPages) ? null : onNext,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pending approvals section
// ---------------------------------------------------------------------------

class _PendingApprovalsSection extends StatelessWidget {
  const _PendingApprovalsSection({
    required this.pendingStaff,
    required this.roleChoices,
    required this.batchSelection,
    required this.rowBusy,
    required this.approveAllRole,
    required this.approveAllBusy,
    required this.canApproveSingle,
    required this.canApproveBatch,
    required this.canApproveAll,
    required this.onRoleChosen,
    required this.onSelectionChanged,
    required this.onApproveOne,
    required this.onApproveSelected,
    required this.onApproveAllRoleChanged,
    required this.onApproveAll,
  });

  final List<PendingStaffModel> pendingStaff;
  final Map<String, StaffRole?> roleChoices;
  final Set<String> batchSelection;
  final Set<String> rowBusy;
  final StaffRole? approveAllRole;
  final bool approveAllBusy;
  final bool canApproveSingle;
  final bool canApproveBatch;
  final bool canApproveAll;
  final void Function(String userId, StaffRole role) onRoleChosen;
  final void Function(String userId, bool selected) onSelectionChanged;
  final void Function(String userId) onApproveOne;
  final VoidCallback onApproveSelected;
  final void Function(StaffRole? role) onApproveAllRoleChanged;
  final VoidCallback onApproveAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _StaffColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _StaffColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                Text(
                  'Pending Staff Approvals',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 14 : 16,
                    fontWeight: FontWeight.w700,
                    color: _StaffColors.primaryText(context),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _StaffColors.pendingBadgeBg(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${pendingStaff.length} pending',
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 10 : 12,
                      fontWeight: FontWeight.w600,
                      color: _StaffColors.pendingBadgeText(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _StaffColors.cardBorder(context)),
          ...pendingStaff.map(
            (staff) => _PendingStaffRow(
              staff: staff,
              selectedRole: roleChoices[staff.userId],
              selected: batchSelection.contains(staff.userId),
              busy: rowBusy.contains(staff.userId),
              canApprove: canApproveSingle,
              canSelect: canApproveBatch,
              onRoleChanged: (role) {
                if (role != null) onRoleChosen(staff.userId, role);
              },
              onSelectedChanged: (value) =>
                  onSelectionChanged(staff.userId, value ?? false),
              onApprove: () => onApproveOne(staff.userId),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                if (canApproveBatch)
                  _StaffPillButton(
                    label: 'Approve Selected (${batchSelection.length})',
                    background: _StaffColors.background(context),
                    foreground: _StaffColors.primaryButton,
                    onTap: batchSelection.isEmpty ? null : onApproveSelected,
                  ),
                if (canApproveAll) ...[
                  SizedBox(
                    width: 200,
                    child: _StaffRoleDropdown(
                      value: approveAllRole,
                      hintText: 'Approve all as...',
                      onChanged: onApproveAllRoleChanged,
                    ),
                  ),
                  _StaffPillButton(
                    label: 'Approve All',
                    background: _StaffColors.primaryButton,
                    foreground: Colors.white,
                    onTap: approveAllRole == null ? null : onApproveAll,
                    loading: approveAllBusy,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingStaffRow extends StatelessWidget {
  const _PendingStaffRow({
    required this.staff,
    required this.selectedRole,
    required this.selected,
    required this.busy,
    required this.canApprove,
    required this.canSelect,
    required this.onRoleChanged,
    required this.onSelectedChanged,
    required this.onApprove,
  });

  final PendingStaffModel staff;
  final StaffRole? selectedRole;
  final bool selected;
  final bool busy;
  final bool canApprove;
  final bool canSelect;
  final ValueChanged<StaffRole?> onRoleChanged;
  final ValueChanged<bool?> onSelectedChanged;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (canSelect)
            Checkbox(value: selected, onChanged: onSelectedChanged)
          else
            const SizedBox(width: 12),
          _StaffAvatar(
            initials: staff.avatarInitials,
            color: _StaffColors.primaryButton,
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  staff.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
                    fontWeight: FontWeight.w600,
                    color: _StaffColors.primaryText(context),
                  ),
                ),
                Text(
                  staff.email ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 9 : 11,
                    color: _StaffColors.secondaryText(context),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              staff.department ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12, color: _StaffColors.primaryText(context)),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: _StaffRoleDropdown(
              value: selectedRole,
              hintText: 'Assign role',
              onChanged: onRoleChanged,
            ),
          ),
          const SizedBox(width: 12),
          if (canApprove)
            _StaffPillButton(
              label: 'Approve',
              background: _StaffColors.primaryButton,
              foreground: Colors.white,
              onTap: selectedRole == null ? null : onApprove,
              loading: busy,
            ),
        ],
      ),
    );
  }
}

/// Pale, rounded role dropdown matching the shared design language used
/// across every dashboard's card-level controls (e.g. Registrar's
/// DropdownField) — a real functional dropdown restyled to drop the boxed
/// `OutlineInputBorder` look in favor of a borderless filled pill.
class _StaffRoleDropdown extends StatelessWidget {
  const _StaffRoleDropdown({
    required this.value,
    required this.hintText,
    required this.onChanged,
  });

  final StaffRole? value;
  final String hintText;
  final ValueChanged<StaffRole?> onChanged;

  @override
  Widget build(BuildContext context) {
    final borderless = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );
    return DropdownButtonFormField<StaffRole>(
      value: value,
      isExpanded: true,
      icon: Icon(Icons.keyboard_arrow_down_rounded,
          size: 20, color: _StaffColors.secondaryText(context)),
      hint: Text(
        hintText,
        style:
            GoogleFonts.poppins(fontSize: context.isMobileWidth ? 10 : 12, color: _StaffColors.secondaryText(context)),
      ),
      style: GoogleFonts.poppins(fontSize: context.isMobileWidth ? 10 : 12, color: _StaffColors.primaryText(context)),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: _StaffColors.background(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        border: borderless,
        enabledBorder: borderless,
        focusedBorder: borderless,
        disabledBorder: borderless,
      ),
      items: StaffRole.values
          .map((r) => DropdownMenuItem(
                value: r,
                child: Text(r.label, style: GoogleFonts.poppins(fontSize: context.isMobileWidth ? 10 : 12)),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}

/// Solid/pale pill button matching the shared design language's action
/// buttons (rounded 10, Poppins semibold) used across every dashboard.
class _StaffPillButton extends StatelessWidget {
  const _StaffPillButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null || loading;
    return Material(
      color: disabled ? background.withOpacity(0.5) : background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: foreground),
                )
              : Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
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
            value: selectedRole,
            onChanged: onRoleChanged,
            isExpanded: true,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 12 : 14,
              color: _StaffColors.primaryText(context),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: _StaffColors.card(context),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _StaffColors.cardBorder(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _StaffColors.cardBorder(context)),
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
              fontSize: context.isMobileWidth ? 12 : 14,
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
    this.isLoading = false,
  });

  final List<StaffUserModel> staffList;
  final void Function(int index, bool value) onToggleAccess;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _StaffColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _StaffColors.cardBorder(context)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _StaffTableHeaderRow(),
            Divider(height: 1, color: _StaffColors.cardBorder(context)),
            // Bounded by pagination (a fixed page size), so a shrink-wrapped,
            // non-scrolling list here is safe — the page's own outer scroll
            // handles reaching the rest of the page instead of this card
            // trapping its own scrollbar.
            isLoading && staffList.isEmpty
                ? const _StaffSkeletonTableBody(rowCount: 8)
                : staffList.isEmpty
                    ? const _EmptyTableState(
                        icon: Icons.folder_open_rounded,
                        message: 'No records found',
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
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
          ],
        ),
      ),
    );
  }
}

class _StaffSkeletonTableBody extends StatefulWidget {
  const _StaffSkeletonTableBody({required this.rowCount});

  final int rowCount;

  @override
  State<_StaffSkeletonTableBody> createState() =>
      _StaffSkeletonTableBodyState();
}

class _StaffSkeletonTableBodyState extends State<_StaffSkeletonTableBody>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  late final _opacity = Tween<double>(begin: 0.4, end: 0.9).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) {
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.rowCount,
          itemBuilder: (context, index) =>
              _StaffSkeletonRow(opacity: _opacity.value),
        );
      },
    );
  }
}

class _StaffSkeletonRow extends StatelessWidget {
  const _StaffSkeletonRow({required this.opacity});

  final double opacity;

  static const _flexValues = _StaffTableLayout.columnFlex;

  Widget _bar({double widthFactor = 0.7}) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0).withOpacity(opacity),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _StaffColors.cardBorder(context))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _StaffTableLayout.horizontalPadding,
          vertical: 16,
        ),
        child: Row(
          children: [
            for (var i = 0; i < _flexValues.length; i++)
              Expanded(
                flex: _flexValues[i],
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == _flexValues.length - 1
                        ? 0
                        : _StaffTableLayout.columnGap,
                  ),
                  child: _bar(widthFactor: i == 1 ? 0.9 : 0.6),
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
                fontSize: context.isMobileWidth ? 12 : 14,
                fontWeight: FontWeight.w500,
                color: _StaffColors.secondaryText(context),
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
    final alignment = alignRight ? Alignment.centerRight : Alignment.centerLeft;

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
                  fontSize: context.isMobileWidth ? 9 : 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: _StaffColors.headerText(context),
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
        hoverColor: _StaffColors.rowHover(context),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        mouseCursor: SystemMouseCursors.basic,
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            border: showDivider
                ? Border(
                    bottom: BorderSide(color: _StaffColors.cardBorder(context)),
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
                      fontSize: context.isMobileWidth ? 10 : 12,
                      fontWeight: FontWeight.w500,
                      color: _StaffColors.secondaryText(context),
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
                                fontSize: context.isMobileWidth ? 11 : 13,
                                fontWeight: FontWeight.w600,
                                color: _StaffColors.primaryText(context),
                              ),
                            ),
                            Text(
                              staff.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: context.isMobileWidth ? 9 : 11,
                                fontWeight: FontWeight.w400,
                                color: _StaffColors.secondaryText(context),
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
                      fontSize: context.isMobileWidth ? 10 : 12,
                      color: _StaffColors.primaryText(context),
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
                      fontSize: context.isMobileWidth ? 9 : 11,
                      color: _StaffColors.secondaryText(context),
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
                    activeColor: Colors.white,
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
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 9 : 11,
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
    final (background, foreground) = role.colorsFor(context);

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
          fontSize: context.isMobileWidth ? 9 : 11,
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
          fontSize: context.isMobileWidth ? 9 : 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
