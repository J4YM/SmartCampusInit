import 'dart:async';

import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/register_syncs_repository.dart';
import '../../env.dart';

/// Wires [RegisterSyncsPage] to `registration_sync_events` (see
/// supabase/add_registration_sync_log_schema.sql) — read-only, so unlike
/// most other connected pages there's nothing here to persist, only to load
/// and keep live.
class RegisterSyncsConnectedPage extends StatefulWidget {
  const RegisterSyncsConnectedPage({super.key});

  @override
  State<RegisterSyncsConnectedPage> createState() =>
      _RegisterSyncsConnectedPageState();
}

class _RegisterSyncsConnectedPageState
    extends State<RegisterSyncsConnectedPage> {
  bool _loading = true;
  List<RegisterSyncEventModel> _events = const [];

  RealtimeChannel? _channel;
  Timer? _reloadDebounce;

  RegisterSyncsRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return RegisterSyncsRepository(Supabase.instance.client);
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final events = await repo.fetchRecent();
      if (!mounted) return;
      setState(() => _events = events);
    } catch (e) {
      debugPrint('Could not load register syncs: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _subscribeToChanges();
  }

  /// Live-refreshes the feed when a new event is logged (staff approval,
  /// RFID linking, student self-registration/claim). Requires
  /// `registration_sync_events` to be in the `supabase_realtime`
  /// publication (see supabase/add_registration_sync_log_schema.sql).
  void _subscribeToChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _channel = Supabase.instance.client
        .channel('public:registration_sync_events')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'registration_sync_events',
          callback: (_) {
            _reloadDebounce?.cancel();
            _reloadDebounce =
                Timer(const Duration(milliseconds: 400), _load);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    final channel = _channel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RegisterSyncsPage(events: _events, isLoading: _loading);
  }
}
