import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/admin_approval_repository.dart';
import '../../env.dart';
import '../../models/staff_profile_record.dart';
import 'staff_role_mapping.dart';

/// Wires the presentation-only [StaffAccountsPage] (from `admin_dashboard`)
/// to Supabase via [AdminApprovalRepository], following the same
/// repository-owns-the-data / package-takes-callbacks split used by
/// `lib/ui/dashboard_page.dart` for the RFID module.
class StaffAccountsConnectedPage extends StatefulWidget {
  const StaffAccountsConnectedPage({super.key});

  @override
  State<StaffAccountsConnectedPage> createState() => _StaffAccountsConnectedPageState();
}

class _StaffAccountsConnectedPageState extends State<StaffAccountsConnectedPage> {
  List<StaffProfileRecord> _pending = [];
  List<StaffProfileRecord> _roster = [];
  bool _busy = false;

  AdminApprovalRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return AdminApprovalRepository(Supabase.instance.client);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      final results = await Future.wait([
        repo.fetchPendingStaff(),
        repo.fetchApprovedStaffRoster(),
      ]);
      if (!mounted) return;
      setState(() {
        _pending = results[0];
        _roster = results[1];
      });
    } catch (e) {
      _toast('Could not load staff accounts: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    await _load();
  }

  Future<void> _batchApprovePending(Map<String, StaffRole> selections) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.batchApproveStaff([
      for (final entry in selections.entries)
        StaffApproval(userId: entry.key, role: staffRoleToAppRole(entry.value)),
    ]);
    await _load();
  }

  Future<void> _approveAllPending(StaffRole role) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.approveAllPendingStaff(role: staffRoleToAppRole(role));
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
      isBusy: _busy,
      onApprovePending: _approvePending,
      onBatchApprovePending: _batchApprovePending,
      onApproveAllPending: _approveAllPending,
      onToggleAccess: _toggleAccess,
    );
  }
}
