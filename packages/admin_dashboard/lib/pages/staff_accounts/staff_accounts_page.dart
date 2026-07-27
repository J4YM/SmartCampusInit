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
  registrar;

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
      case StaffRole.registrar:
        return 'Registrar';
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
      case StaffRole.registrar:
        return (const Color(0xFFFEF9C3), const Color(0xFF854D0E));
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
  'Discipline Officer',
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
  static const pendingBadgeBg = Color(0xFFFFEDD5);
  static const pendingBadgeText = Color(0xFFEA580C);
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
    return _staffList.where((staff) => staff.role.label == _selectedRole).toList();
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
    final listIndex = _staffList.indexWhere((item) => item.staffId == staff.staffId);
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
        _staffList[listIndex] = _staffList[listIndex].copyWith(isActive: !value);
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
        _showSnackBar('Choose a role for every selected account before approving.');
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
    if (onApproveAllPending == null || role == null || _pendingStaff.isEmpty) return;

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
                  onToggleAccess: (index, value) {
                    _toggleStaffAccess(index, value);
                  },
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
        color: _StaffColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _StaffColors.cardBorder),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _StaffColors.primaryText,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _StaffColors.pendingBadgeBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${pendingStaff.length} pending',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _StaffColors.pendingBadgeText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _StaffColors.cardBorder),
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
                  OutlinedButton(
                    onPressed: batchSelection.isEmpty ? null : onApproveSelected,
                    child: Text('Approve Selected (${batchSelection.length})'),
                  ),
                if (canApproveAll) ...[
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<StaffRole>(
                      initialValue: approveAllRole,
                      isExpanded: true,
                      hint: const Text('Approve all as...'),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      items: StaffRole.values
                          .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                          .toList(),
                      onChanged: onApproveAllRoleChanged,
                    ),
                  ),
                  FilledButton(
                    onPressed: (approveAllRole == null || approveAllBusy)
                        ? null
                        : onApproveAll,
                    child: approveAllBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Approve All'),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _StaffColors.primaryText,
                  ),
                ),
                Text(
                  staff.email ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: _StaffColors.secondaryText,
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
              style: GoogleFonts.poppins(fontSize: 12, color: _StaffColors.primaryText),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<StaffRole>(
              initialValue: selectedRole,
              isExpanded: true,
              hint: const Text('Assign role'),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
              items: StaffRole.values
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                  .toList(),
              onChanged: onRoleChanged,
            ),
          ),
          const SizedBox(width: 12),
          if (canApprove)
            FilledButton(
              onPressed: (selectedRole == null || busy) ? null : onApprove,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Approve'),
            ),
        ],
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
