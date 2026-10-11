import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/audit_logger.dart';
import '../data/professor_links_repository.dart';
import '../env.dart';
import '../auth/app_role.dart';

/// Host for [ProfessorLinksView]: loads the professor records and pending
/// sign-ins from Supabase and refreshes them after every override action.
/// Shared by the Admin's Staff Accounts page and the Registrar dashboard, so
/// both manage the same records the same way.
class ProfessorLinksPanel extends StatefulWidget {
  const ProfessorLinksPanel({
    super.key,
    required this.actorName,
    required this.actorRole,
    this.actorId,
  });

  final String actorName;
  final AppRole actorRole;

  /// `profiles.id` of the signed-in user, or null for a demo account.
  final String? actorId;

  @override
  State<ProfessorLinksPanel> createState() => _ProfessorLinksPanelState();
}

class _ProfessorLinksPanelState extends State<ProfessorLinksPanel> {
  List<ProfessorLinkRow> _professors = const [];
  List<PendingLoginRow> _pending = const [];
  bool _loading = false;
  String? _error;

  ProfessorLinksRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return ProfessorLinksRepository(Supabase.instance.client);
  }

  AuditLogger? get _audit {
    if (!AppEnv.supabaseConfigured) return null;
    return AuditLogger(
      Supabase.instance.client,
      actorId: widget.actorId,
      actorEmail: widget.actorName,
      actorRole: widget.actorRole,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await repo.fetch();
      if (!mounted) return;
      setState(() {
        _professors = result.professors;
        _pending = result.pending;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not load professor accounts '
            '(has add_professor_identity_override.sql been run?): $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        ProfessorLinksView(
          professors: _professors,
          pendingLogins: _pending,
          isLoading: _loading,
          onConnectEmail: repo == null
              ? null
              : (p, email) async {
                  final result = await repo.connectEmail(
                    p.id,
                    email,
                    actorName: widget.actorName,
                  );
                  await _audit?.log(
                    action: email.isEmpty
                        ? 'Cleared connected email of professor ${p.fullName}'
                        : 'Connected $email to professor ${p.fullName}',
                    recordId: p.id,
                  );
                  await _load();
                  return result;
                },
          onLinkLogin: repo == null
              ? null
              : (login, p) async {
                  await repo.linkLogin(login.id, p.id);
                  await _audit?.log(
                    action: 'Linked sign-in ${login.email} to professor ${p.fullName}',
                    recordId: p.id,
                  );
                  await _load();
                },
          onMergeDuplicates: repo == null
              ? null
              : ({required bool dryRun}) async {
                  final count = await repo.mergeDuplicates(dryRun: dryRun);
                  if (!dryRun) {
                    await _audit?.log(
                      action: 'Merged $count duplicate professor record(s)',
                      severity: 'WARN',
                    );
                    await _load();
                  }
                  return count;
                },
          onMerge: repo == null
              ? null
              : (keep, remove) async {
                  await repo.merge(keep.id, remove.id);
                  await _audit?.log(
                    action: 'Merged professor ${remove.fullName} into ${keep.fullName}',
                    recordId: keep.id,
                    severity: 'WARN',
                  );
                  await _load();
                },
        ),
      ],
    );
  }
}
