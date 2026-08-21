import 'package:flutter/material.dart';

/// One row of `rfid_readers` — see
/// supabase/add_rfid_reader_network_schema.sql (host app owns the real
/// Supabase model; this is the package-local, presentation-only shape).
class RfidReaderRowModel {
  const RfidReaderRowModel({
    required this.id,
    required this.label,
    required this.usbSerial,
    required this.location,
    required this.isKioskReader,
    required this.isActive,
    required this.isOnline,
    required this.lastSeenLabel,
  });

  final String id;
  final String label;
  final String usbSerial;
  final String? location;
  final bool isKioskReader;
  final bool isActive;
  final bool isOnline;

  /// Pre-formatted by the host (e.g. "2 minutes ago" / "Never") — this
  /// package doesn't depend on `intl` for a single relative-time string.
  final String lastSeenLabel;
}

abstract final class _ReaderColors {
  static const background = Color(0xFFF8FAFC);
  static const card = Color(0xFFFFFFFF);
  static const header = Color(0xFF15253F);
  static const primaryText = Color(0xFF111827);
  static const secondaryText = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const primaryButton = Color(0xFF2563EB);
  static const onlineGreen = Color(0xFF16A34A);
  static const offlineRed = Color(0xFFDC2626);
  static const inactiveGrey = Color(0xFF9CA3AF);
}

/// Lets whoever manages the floor-reader network (Admin, Registrar, or
/// Security Personnel — see `lib/modules/module_access.dart`) register new
/// physical readers, edit their label/location/USB identity, and
/// deactivate ones that are decommissioned (never hard-deleted — see
/// add_rfid_readers_soft_delete.sql, which keeps a deactivated reader's tap
/// history intact).
class RfidReaderManagementPage extends StatelessWidget {
  const RfidReaderManagementPage({
    super.key,
    required this.readers,
    required this.isBusy,
    required this.onAddReader,
    required this.onUpdateReader,
    required this.onSetActive,
    this.onReturnToHub,
  });

  final List<RfidReaderRowModel> readers;
  final bool isBusy;
  final Future<void> Function({
    required String label,
    required String usbSerial,
    String? location,
  }) onAddReader;
  final Future<void> Function({
    required String id,
    required String label,
    required String usbSerial,
    String? location,
  }) onUpdateReader;
  final Future<void> Function(String id, bool isActive) onSetActive;
  final VoidCallback? onReturnToHub;

  Future<void> _openForm(BuildContext context, {RfidReaderRowModel? editing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => _ReaderFormDialog(
        editing: editing,
        onAddReader: onAddReader,
        onUpdateReader: onUpdateReader,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ReaderColors.background,
      appBar: AppBar(
        backgroundColor: _ReaderColors.header,
        foregroundColor: Colors.white,
        title: const Text('RFID Reader Devices'),
        leading: onReturnToHub == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onReturnToHub,
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Reader'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Every reader in the floor-attendance network, plus the '
                'main kiosk\'s own reader. Deactivating a reader stops it '
                'from recording new taps but keeps its history.',
                style: TextStyle(
                  fontSize: 13,
                  color: _ReaderColors.secondaryText,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: readers.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        itemCount: readers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final reader = readers[index];
                          return _ReaderCard(
                            reader: reader,
                            busy: isBusy,
                            onEdit: () =>
                                _openForm(context, editing: reader),
                            onToggleActive: () =>
                                onSetActive(reader.id, !reader.isActive),
                          );
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No readers registered yet. Tap "Add Reader" to register the first one.',
        style: TextStyle(color: _ReaderColors.secondaryText),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ReaderCard extends StatelessWidget {
  const _ReaderCard({
    required this.reader,
    required this.busy,
    required this.onEdit,
    required this.onToggleActive,
  });

  final RfidReaderRowModel reader;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final inactive = !reader.isActive;
    return Opacity(
      opacity: inactive ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _ReaderColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _ReaderColors.border),
        ),
        child: Row(
          children: [
            Icon(
              reader.isKioskReader ? Icons.point_of_sale : Icons.sensors,
              color: _ReaderColors.primaryText,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        reader.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _ReaderColors.primaryText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (reader.isKioskReader) const _Badge(label: 'KIOSK'),
                      if (inactive)
                        const _Badge(
                            label: 'INACTIVE', color: _ReaderColors.inactiveGrey),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${reader.usbSerial}'
                    '${reader.location != null ? ' · ${reader.location}' : ''}',
                    style: const TextStyle(
                        fontSize: 12, color: _ReaderColors.secondaryText),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: reader.isOnline
                            ? _ReaderColors.onlineGreen
                            : _ReaderColors.offlineRed,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        reader.isOnline
                            ? 'Online — last seen ${reader.lastSeenLabel}'
                            : 'Offline — last seen ${reader.lastSeenLabel}',
                        style: const TextStyle(
                            fontSize: 12, color: _ReaderColors.secondaryText),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit',
              onPressed: busy ? null : onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: inactive ? 'Reactivate' : 'Deactivate',
              onPressed: busy ? null : onToggleActive,
              icon: Icon(
                inactive ? Icons.power_settings_new : Icons.block,
                color: inactive
                    ? _ReaderColors.onlineGreen
                    : _ReaderColors.offlineRed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.color = _ReaderColors.primaryButton});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ReaderFormDialog extends StatefulWidget {
  const _ReaderFormDialog({
    required this.editing,
    required this.onAddReader,
    required this.onUpdateReader,
  });

  final RfidReaderRowModel? editing;
  final Future<void> Function({
    required String label,
    required String usbSerial,
    String? location,
  }) onAddReader;
  final Future<void> Function({
    required String id,
    required String label,
    required String usbSerial,
    String? location,
  }) onUpdateReader;

  @override
  State<_ReaderFormDialog> createState() => _ReaderFormDialogState();
}

class _ReaderFormDialogState extends State<_ReaderFormDialog> {
  late final _labelController =
      TextEditingController(text: widget.editing?.label ?? '');
  late final _usbSerialController =
      TextEditingController(text: widget.editing?.usbSerial ?? '');
  late final _locationController =
      TextEditingController(text: widget.editing?.location ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    _usbSerialController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _labelController.text.trim();
    final usbSerial = _usbSerialController.text.trim();
    if (label.isEmpty || usbSerial.isEmpty) {
      setState(() => _error = 'Label and USB serial are required.');
      return;
    }
    final location = _locationController.text.trim();

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final editing = widget.editing;
      if (editing == null) {
        await widget.onAddReader(
          label: label,
          usbSerial: usbSerial,
          location: location.isEmpty ? null : location,
        );
      } else {
        await widget.onUpdateReader(
          id: editing.id,
          label: label,
          usbSerial: usbSerial,
          location: location.isEmpty ? null : location,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing;
    return AlertDialog(
      title: Text(editing == null ? 'Add Reader' : 'Edit Reader'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: const TextStyle(color: _ReaderColors.offlineRed)),
              ),
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g. Floor 2 Reader',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usbSerialController,
              decoration: const InputDecoration(
                labelText: 'USB serial (stable hardware identity)',
                hintText: 'Must match config.json on the reader-service',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                hintText: 'e.g. Floor 2 — Main Hallway',
                border: OutlineInputBorder(),
              ),
            ),
            if (editing != null) ...[
              const SizedBox(height: 12),
              const Text(
                'Changing the USB serial breaks this reader until '
                'config.json on the central machine is updated to match.',
                style: TextStyle(
                    fontSize: 11, color: _ReaderColors.secondaryText),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
