import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/app_role.dart';
import '../../auth/app_user.dart';
import '../../data/admin_approval_repository.dart';
import '../../data/audit_logger.dart';
import '../../env.dart';
import '../../models/staff_profile_record.dart';
import 'staff_role_mapping.dart';

/// Wires the presentation-only [StaffAccountsPage] (from `admin_dashboard`)
/// to Supabase via [AdminApprovalRepository], following the same
/// repository-owns-the-data / package-takes-callbacks split used by
/// `lib/ui/dashboard_page.dart` for the RFID module.
///
/// The approved-staff roster is fetched one page at a time (see
/// `AdminApprovalRepository.fetchApprovedStaffPage`) instead of loading
/// every staff account at once; the (typically much smaller) pending queue
/// is still fetched in full.
class StaffAccountsConnectedPage extends StatefulWidget {
  const StaffAccountsConnectedPage({super.key, this.currentUser});

  /// The signed-in Admin — used to attribute audit log entries (see
  /// [AuditLogger]) to whoever actually performed the action.
  final AppUser? currentUser;

  @override
  State<StaffAccountsConnectedPage> createState() => _StaffAccountsConnectedPageState();
}

class _StaffAccountsConnectedPageState extends State<StaffAccountsConnectedPage> {
  List<StaffProfileRecord> _pending = [];
  List<StaffProfileRecord> _roster = [];
  int _page = 1;
  int _totalCount = 0;
  String? _roleFilter;
  bool _loading = false;

  /// The page size the roster was last fetched with — compared against the
  /// live [_pageSize] in [didChangeDependencies] so a resize/rotation that
  /// crosses [kPaginationMobileBreakpoint] re-fetches page 1 at the new
  /// density instead of leaving stale rows (fetched at the old page size)
  /// on screen under a now-mismatched page indicator.
  int? _fetchedPageSize;

  /// 5 rows on a narrow phone, 10 at tablet width and up (see
  /// [ResponsiveX.cardPageSize]).
  int get _pageSize => context.cardPageSize;

  AdminApprovalRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return AdminApprovalRepository(Supabase.instance.client);
  }

  AuditLogger? get _auditLogger {
    final user = widget.currentUser;
    if (!AppEnv.supabaseConfigured || user == null) return null;
    return AuditLogger(
      Supabase.instance.client,
      actorId: user.id.startsWith('u_') ? null : user.id,
      actorEmail: user.username,
      actorRole: user.role,
    );
  }

  int get _totalPages =>
      _totalCount == 0 ? 1 : ((_totalCount + _pageSize - 1) ~/ _pageSize);

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    final pageSize = _pageSize;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        repo.fetchPendingStaff(),
        repo.fetchApprovedStaffPage(page: _page, pageSize: pageSize, role: _roleFilter),
      ]);
      if (!mounted) return;
      final page = results[1] as ({List<StaffProfileRecord> items, int totalCount});
      setState(() {
        _pending = results[0] as List<StaffProfileRecord>;
        _roster = page.items;
        _totalCount = page.totalCount;
        _fetchedPageSize = pageSize;
      });
    } catch (e) {
      _toast('Could not load staff accounts: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fires whenever an inherited dependency this widget reads — including
  /// `MediaQuery`, via [_pageSize] — changes, e.g. a window resize or
  /// device rotation. Re-fetches page 1 at the new density whenever that
  /// actually crosses the mobile/desktop [_pageSize] bucket, so the roster
  /// on screen never silently mismatches the page indicator/count.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fetchedPageSize != null && _fetchedPageSize != _pageSize) {
      _page = 1;
      _load();
    }
  }

  void _goToPage(int page) {
    if (page == _page) return;
    setState(() => _page = page);
    _load();
  }

  void _onRoleFilterChanged(String label) {
    String? role;
    if (label != 'All Roles') {
      final staffRole = StaffRole.values.where((r) => r.label == label).firstOrNull;
      if (staffRole != null) role = appRoleToDbValue(staffRoleToAppRole(staffRole));
    }
    if (role == _roleFilter) return;
    setState(() {
      _roleFilter = role;
      _page = 1;
    });
    _load();
  }

  StaffUserModel _toStaffUserModel(StaffProfileRecord r) {
    final staffRole = appRoleToStaffRole(r.role) ?? StaffRole.teacher;
    return StaffUserModel(
      staffId: r.id,
      avatarInitials: avatarInitialsFor(r.fullName),
      fullName: r.fullName,
      email: r.email ?? '',
      role: staffRole,
      department: r.department ?? '',
      lastLogin: r.lastLoginAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      isActive: r.isActive,
      avatarColor: staffRole.colors.$2,
    );
  }

  PendingStaffModel _toPendingStaffModel(StaffProfileRecord r) {
    return PendingStaffModel(
      userId: r.id,
      avatarInitials: avatarInitialsFor(r.fullName),
      fullName: r.fullName,
      email: r.email,
      department: r.department,
      requestedAt: r.createdAt,
    );
  }

  Future<void> _approvePending(String userId, StaffRole role) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.approveStaffMember(userId: userId, role: staffRoleToAppRole(role));
    await _auditLogger?.log(
      action: 'Approved staff account as ${role.label}',
      recordId: userId,
    );
    await _load();
  }

  Future<void> _batchApprovePending(Map<String, StaffRole> selections) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.batchApproveStaff([
      for (final entry in selections.entries)
        StaffApproval(userId: entry.key, role: staffRoleToAppRole(entry.value)),
    ]);
    await _auditLogger?.log(
      action: 'Batch-approved ${selections.length} staff account(s)',
    );
    await _load();
  }

  Future<void> _approveAllPending(StaffRole role) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.approveAllPendingStaff(role: staffRoleToAppRole(role));
    await _auditLogger?.log(
      action: 'Approved all pending ${role.label} accounts',
    );
    await _load();
  }

  Future<void> _toggleAccess(String staffId, bool value) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.setStaffActive(userId: staffId, isActive: value);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return StaffAccountsPage(
      staffList: _roster.map(_toStaffUserModel).toList(),
      pendingStaff: _pending.map(_toPendingStaffModel).toList(),
      isBusy: _loading,
      isLoading: _loading,
      currentPage: _page,
      totalPages: _totalPages,
      totalCount: _totalCount,
      onPreviousPage: () => _goToPage(_page - 1),
      onNextPage: () => _goToPage(_page + 1),
      onRoleFilterChanged: _onRoleFilterChanged,
      onApprovePending: _approvePending,
      onBatchApprovePending: _batchApprovePending,
      onApproveAllPending: _approveAllPending,
      onToggleAccess: _toggleAccess,
    );
  }
}

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
