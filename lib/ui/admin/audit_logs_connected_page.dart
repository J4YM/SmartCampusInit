import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/audit_logs_repository.dart';
import '../../env.dart';

/// Wires [AuditLogsPage] to real `audit_logs` rows via
/// [AuditLogsRepository]. Read-only — every row is written from across the
/// app by [AuditLogger].
class AuditLogsConnectedPage extends StatefulWidget {
  const AuditLogsConnectedPage({super.key});

  @override
  State<AuditLogsConnectedPage> createState() =>
      _AuditLogsConnectedPageState();
}

class _AuditLogsConnectedPageState extends State<AuditLogsConnectedPage> {
  bool _loading = true;
  List<AuditLogModel> _logs = const [];

  AuditLogsRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return AuditLogsRepository(Supabase.instance.client);
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final logs = await repo.fetchRecent();
      if (!mounted) return;
      setState(() => _logs = logs);
    } catch (e) {
      debugPrint('Could not load audit logs: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return AuditLogsPage(auditLogs: _logs);
  }
}
