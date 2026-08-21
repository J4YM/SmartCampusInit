import 'package:flutter/material.dart';
import 'package:rfid_management_module/rfid_management_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/rfid_reader_repository.dart';
import '../../env.dart';

/// Wires the presentation-only [RfidReaderManagementPage] (from
/// `rfid_management_module`) to Supabase via [RfidReaderRepository]. Reached
/// from the RFID Management module's "Reader Devices" button — see
/// `lib/ui/dashboard_page.dart`.
class RfidReaderManagementConnectedPage extends StatefulWidget {
  const RfidReaderManagementConnectedPage({super.key});

  @override
  State<RfidReaderManagementConnectedPage> createState() =>
      _RfidReaderManagementConnectedPageState();
}

class _RfidReaderManagementConnectedPageState
    extends State<RfidReaderManagementConnectedPage> {
  List<RfidReaderRecord> _readers = [];
  bool _busy = false;

  RfidReaderRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return RfidReaderRepository(Supabase.instance.client);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final readers = await repo.fetchReaders(includeInactive: true);
      if (mounted) setState(() => _readers = readers);
    } catch (e) {
      _toast('Could not load readers: $e');
    }
  }

  String _relativeTime(DateTime? time) {
    if (time == null) return 'never';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  RfidReaderRowModel _toRow(RfidReaderRecord r) {
    return RfidReaderRowModel(
      id: r.id,
      label: r.label,
      usbSerial: r.usbSerial,
      location: r.location,
      isKioskReader: r.isKioskReader,
      isActive: r.isActive,
      isOnline: r.isOnline,
      lastSeenLabel: _relativeTime(r.lastSeenAt),
    );
  }

  Future<void> _addReader({
    required String label,
    required String usbSerial,
    String? location,
  }) async {
    final repo = _repo;
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.addReader(label: label, usbSerial: usbSerial, location: location);
      await _load();
    } finally {
      // Not caught here: the form dialog's own try/catch shows the error
      // inline and keeps the dialog open on failure — swallowing it here
      // would make the dialog think the save succeeded and close itself.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateReader({
    required String id,
    required String label,
    required String usbSerial,
    String? location,
  }) async {
    final repo = _repo;
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.updateReader(
        id: id,
        label: label,
        usbSerial: usbSerial,
        location: location,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setReaderActive(String id, bool isActive) async {
    final repo = _repo;
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.setReaderActive(id, isActive);
      await _load();
    } catch (e) {
      _toast('Could not update reader: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return RfidReaderManagementPage(
      readers: _readers.map(_toRow).toList(),
      isBusy: _busy,
      onAddReader: _addReader,
      onUpdateReader: _updateReader,
      onSetActive: _setReaderActive,
      onReturnToHub: () => Navigator.of(context).maybePop(),
    );
  }
}
