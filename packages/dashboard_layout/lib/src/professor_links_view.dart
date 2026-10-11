import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A professor record (system-created from an upload, or a real login).
class ProfessorLinkRow {
  const ProfessorLinkRow({
    required this.id,
    required this.fullName,
    required this.isStub,
    this.employeeId,
    this.email,
    this.claimedEmail,
    this.nameKey = '',
    this.classCount = 0,
  });

  final String id;
  final String fullName;
  final String? employeeId;

  /// True while no real Microsoft login is tied to this record yet.
  final bool isStub;

  /// The real login email (null for a stub).
  final String? email;

  /// An email a Registrar/Admin connected that hasn't signed in yet.
  final String? claimedEmail;

  /// Order-insensitive name key (see `professor_name_key()` in SQL).
  final String nameKey;
  final int classCount;
}

/// A Microsoft sign-in waiting for approval that isn't tied to a professor.
class PendingLoginRow {
  const PendingLoginRow({
    required this.id,
    required this.email,
    this.fullName = '',
  });

  final String id;
  final String email;
  final String fullName;
}

/// Professor accounts: one record per person, with the login email attached
/// by hand. Shows which professors have signed in, which have an email
/// waiting, which are possible duplicates, and which sign-ins are still
/// unlinked. Every action is a callback that throws on failure; the host
/// refreshes the lists afterwards.
class ProfessorLinksView extends StatefulWidget {
  const ProfessorLinksView({
    super.key,
    required this.professors,
    required this.pendingLogins,
    this.onConnectEmail,
    this.onLinkLogin,
    this.onMerge,
    this.onMergeDuplicates,
    this.isLoading = false,
  });

  final List<ProfessorLinkRow> professors;
  final List<PendingLoginRow> pendingLogins;
  final bool isLoading;

  /// Returns a short result message ("linked" / "stored" / "cleared").
  final Future<String> Function(ProfessorLinkRow professor, String email)? onConnectEmail;
  final Future<void> Function(PendingLoginRow login, ProfessorLinkRow professor)? onLinkLogin;
  final Future<void> Function(ProfessorLinkRow keep, ProfessorLinkRow remove)? onMerge;

  /// Folds every exact-duplicate record into one. With `dryRun: true` it only
  /// returns how many records would be merged.
  final Future<int> Function({required bool dryRun})? onMergeDuplicates;

  @override
  State<ProfessorLinksView> createState() => _ProfessorLinksViewState();
}

class _ProfessorLinksViewState extends State<ProfessorLinksView> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Set<String> get _duplicateKeys {
    final counts = <String, int>{};
    for (final p in widget.professors) {
      if (p.nameKey.isEmpty) continue;
      counts[p.nameKey] = (counts[p.nameKey] ?? 0) + 1;
    }
    return {for (final e in counts.entries) if (e.value > 1) e.key};
  }

  Future<void> _connect(ProfessorLinkRow p) async {
    final connect = widget.onConnectEmail;
    if (connect == null) return;
    final controller = TextEditingController(
        text: p.isStub ? (p.claimedEmail ?? '') : (p.email ?? ''));
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.isStub
            ? 'Connect login email — ${p.fullName}'
            : 'Change login email — ${p.fullName}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.isStub
                    ? 'Enter the exact Microsoft address this professor signs '
                        'in with. If they have already signed in they are '
                        'linked now; otherwise they are linked on their first '
                        'sign-in. Leave blank to clear.'
                    : 'Currently signed in as ${p.email ?? 'an account'}. '
                        'Changing it moves all of this professor\'s classes to '
                        'the new address; the old account goes back to waiting '
                        'for approval. Leave blank to unlink without '
                        'replacing.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'firstname.lastname@baliuag.sti.edu.ph',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null) return;
    try {
      final result = await connect(p, email);
      _toast(switch (result) {
        'linked' => '${p.fullName} is linked to their existing sign-in.',
        'cleared' => 'Connected email cleared.',
        'unlinked' => '${p.fullName} is unlinked from their old sign-in.',
        'unchanged' => 'That is already the connected email.',
        _ => 'Email saved. ${p.fullName} will be linked on first sign-in.',
      });
    } catch (e) {
      _toast('Could not connect the email: $e');
    }
  }

  Future<ProfessorLinkRow?> _pickProfessor({
    required String title,
    required List<ProfessorLinkRow> options,
    String? suggestedKey,
  }) {
    return showDialog<ProfessorLinkRow>(
      context: context,
      builder: (ctx) {
        var filter = '';
        return StatefulBuilder(
          builder: (ctx, setState) {
            final shown = options
                .where((o) =>
                    filter.isEmpty ||
                    o.fullName.toLowerCase().contains(filter) ||
                    (o.employeeId ?? '').toLowerCase().contains(filter))
                .toList()
              ..sort((a, b) {
                final sa = suggestedKey != null && a.nameKey == suggestedKey ? 0 : 1;
                final sb = suggestedKey != null && b.nameKey == suggestedKey ? 0 : 1;
                return sa != sb ? sa - sb : a.fullName.compareTo(b.fullName);
              });
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 440,
                height: 380,
                child: Column(
                  children: [
                    TextField(
                      onChanged: (v) => setState(() => filter = v.trim().toLowerCase()),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search professors',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final o in shown)
                            ListTile(
                              dense: true,
                              title: Text(o.fullName),
                              subtitle: Text([
                                if (o.employeeId != null) 'ID ${o.employeeId}',
                                '${o.classCount} class(es)',
                              ].join(' · ')),
                              trailing: suggestedKey != null && o.nameKey == suggestedKey
                                  ? const Chip(label: Text('Likely match'))
                                  : null,
                              onTap: () => Navigator.pop(ctx, o),
                            ),
                          if (shown.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No matching professor records.'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ],
            );
          },
        );
      },
    );
  }

  /// "paulino.karel@baliuag…" -> the same sorted-words key the SQL builds
  /// from a name, so a login can be matched to a record regardless of order.
  String _keyFromEmail(String email) {
    final local = email.split('@').first;
    final words = local
        .split(RegExp(r'[._-]'))
        .map((w) => w.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((w) => w.length > 1)
        .toList()
      ..sort();
    return words.join(' ');
  }

  Future<void> _link(PendingLoginRow login) async {
    final link = widget.onLinkLogin;
    if (link == null) return;
    final stubs = widget.professors.where((p) => p.isStub).toList();
    final picked = await _pickProfessor(
      title: 'Link ${login.email} to a professor',
      options: stubs,
      suggestedKey: _keyFromEmail(login.email),
    );
    if (picked == null) return;
    try {
      await link(login, picked);
      _toast('${login.email} linked to ${picked.fullName} and approved as Teacher.');
    } catch (e) {
      _toast('Could not link the sign-in: $e');
    }
  }

  Future<void> _mergeDuplicates() async {
    final merge = widget.onMergeDuplicates;
    if (merge == null) return;
    try {
      final count = await merge(dryRun: true);
      if (count == 0) {
        _toast('No exact duplicates without a login were found.');
        return;
      }
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Merge duplicate professors?'),
          content: Text(
            '$count duplicate record(s) with the same name (ignoring '
            'Mr./Ms., capitals and name order) will be merged into one record '
            'per professor. Their classes move to the kept record. Two '
            'records that already have a login are never merged.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Merge')),
          ],
        ),
      );
      if (ok != true) return;
      final merged = await merge(dryRun: false);
      _toast('Merged $merged duplicate record(s).');
    } catch (e) {
      _toast('Could not merge duplicates: $e');
    }
  }

  Future<void> _merge(ProfessorLinkRow remove) async {
    final merge = widget.onMerge;
    if (merge == null) return;
    final picked = await _pickProfessor(
      title: 'Merge “${remove.fullName}” into…',
      options: widget.professors.where((p) => p.id != remove.id).toList(),
      suggestedKey: remove.nameKey,
    );
    if (picked == null) return;
    try {
      await merge(picked, remove);
      _toast('Merged into ${picked.fullName}.');
    } catch (e) {
      _toast('Could not merge: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    final dupes = _duplicateKeys;
    final professors = widget.professors
        .where((p) =>
            _query.isEmpty ||
            p.fullName.toLowerCase().contains(_query) ||
            (p.email ?? '').toLowerCase().contains(_query) ||
            (p.claimedEmail ?? '').toLowerCase().contains(_query) ||
            (p.employeeId ?? '').toLowerCase().contains(_query))
        .toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

    Widget statusChip(ProfessorLinkRow p) {
      final (label, color) = !p.isStub
          ? ('Signed in · ${p.email ?? ''}', const Color(0xFF15803D))
          : p.claimedEmail != null
              ? ('Waiting for ${p.claimedEmail}', const Color(0xFFD97706))
              : ('No login email', const Color(0xFF64748B));
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.13),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Professor Accounts',
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'One record per professor, created from the course/professor '
          'upload. Their Microsoft email is never guessed from the uploaded '
          'name: connect it here, or link a sign-in that is waiting.',
          style: GoogleFonts.poppins(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 14),
        if (widget.pendingLogins.isNotEmpty) ...[
          Text('Sign-ins waiting for a professor record',
              style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final login in widget.pendingLogins)
            Card(
              child: ListTile(
                title: Text(login.email),
                subtitle: login.fullName.isEmpty ? null : Text(login.fullName),
                trailing: widget.onLinkLogin == null
                    ? null
                    : FilledButton(
                        onPressed: () => _link(login),
                        child: const Text('Link to professor'),
                      ),
              ),
            ),
          const SizedBox(height: 14),
        ],
        if (dupes.isNotEmpty && widget.onMergeDuplicates != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _mergeDuplicates,
                icon: const Icon(Icons.merge_type, size: 18),
                label: const Text('Merge exact duplicates'),
              ),
            ),
          ),
        TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search by name, employee ID or email',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        if (widget.isLoading && widget.professors.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ))
        else if (professors.isEmpty)
          Text('No professor records found.',
              style: GoogleFonts.poppins(fontSize: 12.5, color: muted))
        else
          for (final p in professors)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(p.fullName,
                              style: GoogleFonts.poppins(
                                  fontSize: 13.5, fontWeight: FontWeight.w600)),
                        ),
                        if (dupes.contains(p.nameKey))
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text('Possible duplicate'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        statusChip(p),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (p.employeeId != null) 'ID ${p.employeeId}',
                        '${p.classCount} class(es)',
                      ].join(' · '),
                      style: GoogleFonts.poppins(fontSize: 11.5, color: muted),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (widget.onConnectEmail != null)
                          OutlinedButton.icon(
                            onPressed: () => _connect(p),
                            icon: const Icon(Icons.alternate_email, size: 16),
                            label: Text(!p.isStub
                                ? 'Change login email'
                                : p.claimedEmail == null
                                    ? 'Connect email'
                                    : 'Change email'),
                          ),
                        if (p.isStub && widget.onMerge != null)
                          TextButton.icon(
                            onPressed: () => _merge(p),
                            icon: const Icon(Icons.merge_type, size: 16),
                            label: const Text('Merge into…'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
