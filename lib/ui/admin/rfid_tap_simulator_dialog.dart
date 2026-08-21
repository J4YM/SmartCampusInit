import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/rfid_reader_repository.dart';
import '../../env.dart';

/// Dev-only tool: fires a simulated tap through the exact same
/// `record_rfid_tap` RPC the real central reader-service calls, so the
/// floor-attendance path (in/out toggling, reader heartbeat, student
/// resolution) is fully testable before any physical reader hardware
/// arrives. Reachable from the RFID Mapping page.
class RfidTapSimulatorDialog extends StatefulWidget {
  const RfidTapSimulatorDialog({super.key});

  @override
  State<RfidTapSimulatorDialog> createState() =>
      _RfidTapSimulatorDialogState();
}

class _SimulatedTapLogEntry {
  const _SimulatedTapLogEntry({
    required this.readerLabel,
    required this.rfidUid,
    required this.result,
  });

  final String readerLabel;
  final String rfidUid;
  final RfidTapResult? result;
}

class _RfidTapSimulatorDialogState extends State<RfidTapSimulatorDialog> {
  final _uidController = TextEditingController();
  List<RfidReaderRecord> _readers = const [];
  RfidReaderRecord? _selectedReader;
  bool _loadingReaders = true;
  bool _sending = false;
  String? _error;
  final _log = <_SimulatedTapLogEntry>[];

  RfidReaderRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return RfidReaderRepository(Supabase.instance.client);
  }

  @override
  void initState() {
    super.initState();
    _loadReaders();
  }

  @override
  void dispose() {
    _uidController.dispose();
    super.dispose();
  }

  Future<void> _loadReaders() async {
    final repo = _repo;
    if (repo == null) {
      setState(() => _loadingReaders = false);
      return;
    }
    try {
      final readers = await repo.fetchReaders();
      if (!mounted) return;
      setState(() {
        _readers = readers;
        // Keep whatever the user had selected (matched by id, since a
        // reload returns fresh record instances) — only fall back to the
        // first reader on the initial load, or if the previously selected
        // one is gone (e.g. deactivated elsewhere). Previously this always
        // reset to readers.first, which silently swapped the selection out
        // from under the user on every post-tap refresh.
        final previousId = _selectedReader?.id;
        _selectedReader = readers.isEmpty
            ? null
            : readers.firstWhere(
                (r) => r.id == previousId,
                orElse: () => readers.first,
              );
        _loadingReaders = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load readers: $e';
        _loadingReaders = false;
      });
    }
  }

  Future<void> _simulateTap() async {
    final repo = _repo;
    final reader = _selectedReader;
    final uid = _uidController.text.trim();
    if (repo == null || reader == null || uid.isEmpty) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await repo.recordTap(
        readerUsbSerial: reader.usbSerial,
        rfidUid: uid,
      );
      if (!mounted) return;
      setState(() {
        _log.insert(
          0,
          _SimulatedTapLogEntry(
            readerLabel: reader.label,
            rfidUid: uid,
            result: result,
          ),
        );
        _sending = false;
      });
      // Reflects the reader's fresh heartbeat in the picker's "online" state.
      unawaited(_loadReaders());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Tap failed: $e';
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Simulate Reader Tap'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!AppEnv.supabaseConfigured)
              const Text('Supabase is not configured.')
            else if (_loadingReaders)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red)),
                ),
              DropdownButtonFormField<RfidReaderRecord>(
                initialValue: _selectedReader,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Reader',
                  border: OutlineInputBorder(),
                ),
                items: _readers
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(
                          '${r.label}'
                          '${r.location != null ? ' — ${r.location}' : ''}'
                          '${r.isOnline ? ' (online)' : ' (offline)'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedReader = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _uidController,
                decoration: const InputDecoration(
                  labelText: 'RFID UID to simulate',
                  hintText:
                      'A real students.rfid_uid to see it resolve, or any '
                      'string to test an unregistered-card tap',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _simulateTap(),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: (_selectedReader == null || _sending)
                    ? null
                    : _simulateTap,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sensors),
                label: const Text('Simulate Tap'),
              ),
              const SizedBox(height: 16),
              if (_log.isNotEmpty) ...[
                const Divider(),
                const Text('Recent simulated taps',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _log.length,
                    itemBuilder: (context, index) {
                      final entry = _log[index];
                      final result = entry.result;
                      final resolved = result?.studentId != null;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          result == null
                              ? Icons.error_outline
                              : (result.tapDirection == 'in'
                                  ? Icons.login
                                  : Icons.logout),
                          color: result == null
                              ? Colors.red
                              : (result.tapDirection == 'in'
                                  ? Colors.green
                                  : Colors.orange),
                        ),
                        title: Text(
                          '${entry.readerLabel} · ${entry.rfidUid}',
                        ),
                        subtitle: Text(
                          result == null
                              ? 'Failed'
                              : '${result.tapDirection.toUpperCase()} at '
                                  '${result.tappedAt.toLocal()} · '
                                  '${resolved ? 'resolved to a student' : 'unregistered card'}',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
