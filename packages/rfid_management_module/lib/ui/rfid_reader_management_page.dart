import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;
import 'shared_form_widgets.dart';

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

/// Reader-status semantic colors — specific to this file's online/offline/
/// inactive states, so kept local rather than folded into the shared
/// [ItTechnicianColors].
abstract final class _ReaderStatusColors {
  static const online = ItTechnicianColors.successGreen;
  static const offline = ItTechnicianColors.dangerRed;
  static const inactive = Color(0xFF9CA3AF);
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
    this.embedded = false,
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
  final bool embedded;

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
    // The same `body` is used standalone (Scaffold body — bounded height) and
    // embedded in the IT Technician dashboard, whose mobile branch lays its
    // tab content out inside a SingleChildScrollView (unbounded height). An
    // `Expanded`/scrollable ListView needs bounded height, so pick the layout
    // from the incoming constraints: fill-and-scroll when bounded, shrink-wrap
    // and let the ambient scroll view do the scrolling when not. Same class of
    // fix as professor_dashboard_page.dart's mobile tab content, without a
    // magic-number fixed height.
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = readers.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                shrinkWrap: !bounded,
                physics: bounded ? null : const NeverScrollableScrollPhysics(),
                itemCount: readers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final reader = readers[index];
                  return _ReaderCard(
                    reader: reader,
                    busy: isBusy,
                    onEdit: () => _openForm(context, editing: reader),
                    onToggleActive: () => onSetActive(reader.id, !reader.isActive),
                  );
                },
              );

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Every reader in the floor-attendance network, plus the '
                        'main kiosk\'s own reader. Deactivating a reader stops it '
                        'from recording new taps but keeps its history.',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: ItTechnicianColors.mutedText(context),
                        ),
                      ),
                    ),
                    if (embedded) ...[
                      const SizedBox(width: 12),
                      PillButton(
                        label: 'Add Reader',
                        icon: Icons.add_rounded,
                        onTap: () => _openForm(context),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                if (bounded) Expanded(child: list) else list,
              ],
            ),
          ),
        );
      },
    );

    if (embedded) {
      return ColoredBox(color: ItTechnicianColors.background(context), child: body);
    }

    return Scaffold(
      backgroundColor: ItTechnicianColors.background(context),
      appBar: AppBar(
        backgroundColor: ItTechnicianColors.navyBlue,
        foregroundColor: Colors.white,
        title: Text('RFID Reader Devices', style: GoogleFonts.poppins()),
        leading: onReturnToHub == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: onReturnToHub),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        backgroundColor: ItTechnicianColors.azureBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Add Reader',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: body,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No readers registered yet. Tap "Add Reader" to register the first one.',
        style: GoogleFonts.poppins(color: ItTechnicianColors.mutedText(context)),
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
          color: ItTechnicianColors.card(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ItTechnicianColors.cardBorder(context)),
        ),
        child: Row(
          children: [
            Icon(
              reader.isKioskReader ? Icons.point_of_sale : Icons.sensors,
              color: ItTechnicianColors.rowText(context),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Flexible + ellipsis: on a phone-width viewport the
                      // card's text column is only ~150px wide, so an
                      // intrinsically-sized label overflows this Row.
                      Flexible(
                        child: Text(
                          reader.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            color: ItTechnicianColors.rowText(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (reader.isKioskReader)
                        const _Badge(
                            label: 'KIOSK', color: ItTechnicianColors.azureBlue),
                      if (inactive)
                        const _Badge(
                            label: 'INACTIVE', color: _ReaderStatusColors.inactive),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${reader.usbSerial}'
                    '${reader.location != null ? ' · ${reader.location}' : ''}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: ItTechnicianColors.mutedText(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: reader.isOnline
                            ? _ReaderStatusColors.online
                            : _ReaderStatusColors.offline,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          reader.isOnline
                              ? 'Online — last seen ${reader.lastSeenLabel}'
                              : 'Offline — last seen ${reader.lastSeenLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: ItTechnicianColors.mutedText(context),
                          ),
                        ),
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
              color: ItTechnicianColors.azureBlue,
            ),
            IconButton(
              tooltip: inactive ? 'Reactivate' : 'Deactivate',
              onPressed: busy ? null : onToggleActive,
              icon: Icon(
                inactive ? Icons.power_settings_new : Icons.block,
                color: inactive
                    ? _ReaderStatusColors.online
                    : _ReaderStatusColors.offline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.color = ItTechnicianColors.azureBlue});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
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

    return DialogShell(
      title: editing == null ? 'Add Reader' : 'Edit Reader',
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: ItTechnicianColors.dangerRed,
              ),
            ),
            const SizedBox(height: 12),
          ],
          const FieldLabel('Label'),
          TextField(
            controller: _labelController,
            enabled: !_saving,
            style: fieldTextStyle(context),
            decoration: fieldDecoration(context, hintText: 'e.g. Floor 2 Reader'),
          ),
          const SizedBox(height: 14),
          const FieldLabel('USB serial (stable hardware identity)'),
          TextField(
            controller: _usbSerialController,
            enabled: !_saving,
            style: fieldTextStyle(context),
            decoration: fieldDecoration(context,
                hintText: 'Must match config.json on the reader-service'),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Location (optional)'),
          TextField(
            controller: _locationController,
            enabled: !_saving,
            style: fieldTextStyle(context),
            decoration:
                fieldDecoration(context, hintText: 'e.g. Floor 2 — Main Hallway'),
          ),
          if (editing != null) ...[
            const SizedBox(height: 12),
            Text(
              'Changing the USB serial breaks this reader until '
              'config.json on the central machine is updated to match.',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: ItTechnicianColors.mutedText(context),
              ),
            ),
          ],
        ],
      ),
      actions: [
        PaleButton(
          label: 'Cancel',
          onTap: _saving ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 10),
        _saving
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(ItTechnicianColors.azureBlue),
                  ),
                ),
              )
            : PillButton(label: 'Save', onTap: _save),
      ],
    );
  }
}
