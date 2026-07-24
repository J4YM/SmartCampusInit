import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/app_role.dart';
import '../../data/admin_approval_repository.dart';
import '../../env.dart';
import '../../models/staff_profile_record.dart';
import 'staff_role_mapping.dart';

/// Wires the presentation-only [RfidMappingPage] (from `admin_dashboard`) to
/// Supabase via [AdminApprovalRepository].
class RfidMappingConnectedPage extends StatefulWidget {
  const RfidMappingConnectedPage({super.key});

  @override
  State<RfidMappingConnectedPage> createState() => _RfidMappingConnectedPageState();
}

class _RfidMappingConnectedPageState extends State<RfidMappingConnectedPage> {
  List<StaffProfileRecord> _unclaimed = [];
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
      final list = await repo.fetchProfilesMissingRfidCard();
      if (mounted) setState(() => _unclaimed = list);
    } catch (e) {
      _toast('Could not load unclaimed profiles: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  UnclaimedProfileModel _toUnclaimedProfileModel(StaffProfileRecord r) {
    return UnclaimedProfileModel(
      id: r.id,
      fullName: r.fullName,
      email: r.email,
      roleLabel: r.isPending ? 'Pending' : (r.role?.displayName ?? 'Unknown'),
      isPending: r.isPending,
      requestedAt: r.createdAt,
    );
  }

  Future<void> _assignCard({
    required String profileId,
    required String cardUid,
    StaffRole? role,
  }) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.linkRfidCard(
      profileId: profileId,
      rfidCardId: cardUid,
      role: role == null ? null : staffRoleToAppRole(role),
    );
    await _load();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return RfidMappingPage(
      unclaimedProfiles: _unclaimed.map(_toUnclaimedProfileModel).toList(),
      isBusy: _busy,
      onAssignCard: _assignCard,
    );
  }
}
