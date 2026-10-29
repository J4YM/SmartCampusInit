import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_popup.dart';
import 'bento_card.dart';
import 'brightness_x.dart';
import 'card_pagination_footer.dart';
import 'card_title_style.dart';
import 'dashboard_table.dart';
import 'dashboard_table_rows.dart';
import 'filter_menu_button.dart';
import 'responsive_x.dart';
import 'searchable_picker_list.dart';
import 'secondary_pill_button.dart';
import 'titled_table_card.dart';

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

/// Where a professor record stands: no login tied to it, an email waiting for
/// its first sign-in, or a real login.
enum _LinkStatus { signedIn, waiting, none }

_LinkStatus _statusOf(ProfessorLinkRow p) => !p.isStub
    ? _LinkStatus.signedIn
    : p.claimedEmail != null
        ? _LinkStatus.waiting
        : _LinkStatus.none;

const _kActionColumnWidth = 72.0;
const _kSideCardWidth = 320.0;

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('Professor', flex: 4, minWidth: 220),
  DashboardTableColumn('Classes', flex: 1, minWidth: 90),
  DashboardTableColumn('Status', flex: 2, minWidth: 140),
  DashboardTableColumn('Login Email', flex: 4, minWidth: 240),
  DashboardTableColumn('', width: _kActionColumnWidth, sticky: true),
];

/// Professor accounts: one record per person, with the login email attached
/// by hand. Shows which professors have signed in, which have an email
/// waiting, which are possible duplicates, and which sign-ins are still
/// unlinked. Every action is a callback that throws on failure; the host
/// refreshes the lists afterwards.
///
/// Laid out like every dashboard's list: a table card (search, status
/// filter, sticky action icons, pagination) with the waiting sign-ins in a
/// side card — stacked below it on a narrow window.
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
  final Future<String> Function(ProfessorLinkRow professor, String email)?
      onConnectEmail;
  final Future<void> Function(PendingLoginRow login, ProfessorLinkRow professor)?
      onLinkLogin;
  final Future<void> Function(ProfessorLinkRow keep, ProfessorLinkRow remove)?
      onMerge;

  /// Folds every exact-duplicate record into one. With `dryRun: true` it only
  /// returns how many records would be merged.
  final Future<int> Function({required bool dryRun})? onMergeDuplicates;

  @override
  State<ProfessorLinksView> createState() => _ProfessorLinksViewState();
}

class _ProfessorLinksViewState extends State<ProfessorLinksView> {
  final _search = TextEditingController();
  String _query = '';

  /// `signedIn`, `waiting`, `none` or `duplicate`; null = every record.
  String? _statusFilter;
  int _page = 1;
  int _pendingPage = 1;

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

  List<ProfessorLinkRow> _filtered(Set<String> dupes) {
    final q = _query;
    return widget.professors.where((p) {
      if (_statusFilter != null) {
        final ok = switch (_statusFilter) {
          'signedIn' => _statusOf(p) == _LinkStatus.signedIn,
          'waiting' => _statusOf(p) == _LinkStatus.waiting,
          'none' => _statusOf(p) == _LinkStatus.none,
          'duplicate' => dupes.contains(p.nameKey),
          _ => true,
        };
        if (!ok) return false;
      }
      if (q.isEmpty) return true;
      return p.fullName.toLowerCase().contains(q) ||
          (p.email ?? '').toLowerCase().contains(q) ||
          (p.claimedEmail ?? '').toLowerCase().contains(q) ||
          (p.employeeId ?? '').toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) =>
          a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
  }

  // ---- actions --------------------------------------------------------

  Future<void> _connect(ProfessorLinkRow p) async {
    final connect = widget.onConnectEmail;
    if (connect == null) return;
    final email = await showAppPopup<String>(
      context: context,
      builder: (_) => _ConnectEmailDialog(professor: p),
    );
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
    final picked = await showAppPopup<ProfessorLinkRow>(
      context: context,
      builder: (_) => _ProfessorPickerDialog(
        title: 'Link to a professor',
        subtitle: login.email,
        options: stubs,
        suggestedKey: _keyFromEmail(login.email),
      ),
    );
    if (picked == null) return;
    try {
      await link(login, picked);
      _toast(
          '${login.email} linked to ${picked.fullName} and approved as Teacher.');
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
      final ok = await showAppPopup<bool>(
        context: context,
        builder: (_) => _ConfirmMergeDialog(count: count),
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
    final picked = await showAppPopup<ProfessorLinkRow>(
      context: context,
      builder: (_) => _ProfessorPickerDialog(
        title: 'Merge into another record',
        subtitle: remove.fullName,
        options: widget.professors.where((p) => p.id != remove.id).toList(),
        suggestedKey: remove.nameKey,
      ),
    );
    if (picked == null) return;
    try {
      await merge(picked, remove);
      _toast('Merged into ${picked.fullName}.');
    } catch (e) {
      _toast('Could not merge: $e');
    }
  }

  // ---- layout ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dupes = _duplicateKeys;
    final professors = _filtered(dupes);

    final table = _ProfessorsCard(
      all: widget.professors,
      shown: professors,
      duplicates: dupes,
      isLoading: widget.isLoading,
      searchController: _search,
      statusFilter: _statusFilter,
      page: _page,
      canMergeDuplicates:
          dupes.isNotEmpty && widget.onMergeDuplicates != null,
      canConnect: widget.onConnectEmail != null,
      canMerge: widget.onMerge != null,
      onQuery: (value) => setState(() {
        _query = value.trim().toLowerCase();
        _page = 1;
      }),
      onStatusFilter: (value) => setState(() {
        _statusFilter = value;
        _page = 1;
      }),
      onPage: (value) => setState(() => _page = value),
      onConnect: _connect,
      onMerge: _merge,
      onMergeDuplicates: _mergeDuplicates,
    );

    final side = _PendingLoginsCard(
      logins: widget.pendingLogins,
      page: _pendingPage,
      onPage: (value) => setState(() => _pendingPage = value),
      onLink: widget.onLinkLogin == null ? null : _link,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (context.isMobileWidth ||
            constraints.maxWidth < kMasterDetailStackBreakpoint) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [table, const SizedBox(height: 16), side],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: table),
            const SizedBox(width: 18),
            SizedBox(width: _kSideCardWidth, child: side),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Professors table card
// ---------------------------------------------------------------------------

class _ProfessorsCard extends StatelessWidget {
  const _ProfessorsCard({
    required this.all,
    required this.shown,
    required this.duplicates,
    required this.isLoading,
    required this.searchController,
    required this.statusFilter,
    required this.page,
    required this.canMergeDuplicates,
    required this.canConnect,
    required this.canMerge,
    required this.onQuery,
    required this.onStatusFilter,
    required this.onPage,
    required this.onConnect,
    required this.onMerge,
    required this.onMergeDuplicates,
  });

  final List<ProfessorLinkRow> all;
  final List<ProfessorLinkRow> shown;
  final Set<String> duplicates;
  final bool isLoading;
  final TextEditingController searchController;
  final String? statusFilter;
  final int page;
  final bool canMergeDuplicates;
  final bool canConnect;
  final bool canMerge;
  final ValueChanged<String> onQuery;
  final ValueChanged<String?> onStatusFilter;
  final ValueChanged<int> onPage;
  final ValueChanged<ProfessorLinkRow> onConnect;
  final ValueChanged<ProfessorLinkRow> onMerge;
  final VoidCallback onMergeDuplicates;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    final pageSize = context.cardPageSize;
    final totalPages = shown.isEmpty ? 1 : (shown.length / pageSize).ceil();
    final current = page.clamp(1, totalPages);
    final pageItems =
        shown.skip((current - 1) * pageSize).take(pageSize).toList();

    final signedIn = all.where((p) => _statusOf(p) == _LinkStatus.signedIn).length;
    final waiting = all.where((p) => _statusOf(p) == _LinkStatus.waiting).length;

    final search = DashboardSearchField(
      key: const Key('professor-search'),
      controller: searchController,
      hint: 'Search by name, employee ID or email',
      onChanged: onQuery,
    );
    final filter = FilterMenuButton(
      compact: true,
      backgroundColor: DashboardSearchField.defaultFill(context),
      menuColor: DashboardTableColors.card(context),
      borderColor: DashboardTableColors.border(context),
      iconColor: dark ? const Color(0xFF71717A) : const Color(0xFF94A3B8),
      textColor: DashboardTableColors.primaryText(context),
      mutedTextColor: DashboardTableColors.secondaryText(context),
      accentColor: const Color(0xFF345892),
      sections: [
        FilterMenuSection(
          title: 'Status',
          options: const [
            FilterMenuOption(label: 'Signed in', value: 'signedIn'),
            FilterMenuOption(label: 'Waiting for sign-in', value: 'waiting'),
            FilterMenuOption(label: 'No login email', value: 'none'),
            FilterMenuOption(label: 'Possible duplicate', value: 'duplicate'),
          ],
          selectedValue: statusFilter,
          onChanged: onStatusFilter,
        ),
      ],
    );
    final mergeButton = canMergeDuplicates
        ? SecondaryPillButton(
            key: const Key('merge-duplicates'),
            label: 'Merge duplicates',
            icon: Icons.merge_type_rounded,
            onTap: onMergeDuplicates,
          )
        : null;

    final Widget toolbar = context.isMobileWidth
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: search),
                const SizedBox(width: 10),
                filter,
              ]),
              if (mergeButton != null) ...[
                const SizedBox(height: 10),
                mergeButton,
              ],
            ],
          )
        : Row(children: [
            Expanded(child: search),
            const SizedBox(width: 10),
            if (mergeButton != null) ...[
              mergeButton,
              const SizedBox(width: 10),
            ],
            filter,
          ]);

    final Widget empty = isLoading && all.isEmpty
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          )
        : DashboardTableEmptyState(
            icon: Icons.badge_outlined,
            message: all.isEmpty
                ? 'No professor records found'
                : 'No professors match your search',
          );

    return TitledTableCard(
      title: 'Professor Accounts',
      subtitle: Text(
        '${all.length} ${all.length == 1 ? 'professor' : 'professors'}'
        ' | $signedIn signed in | $waiting waiting',
        style: TitledTableCard.subtitleStyle(context),
      ),
      toolbar: toolbar,
      columns: _columns,
      empty: empty,
      rows: [
        for (var i = 0; i < pageItems.length; i++)
          _ProfessorRow(
            key: ValueKey('prof-${pageItems[i].id}'),
            professor: pageItems[i],
            isDuplicate: duplicates.contains(pageItems[i].nameKey),
            showDivider: i < pageItems.length - 1,
            onConnect: canConnect ? () => onConnect(pageItems[i]) : null,
            onMerge: canMerge && pageItems[i].isStub
                ? () => onMerge(pageItems[i])
                : null,
          ),
      ],
      footer: shown.isEmpty
          ? null
          : CardPaginationFooter(
              currentPage: current,
              totalPages: totalPages,
              totalCount: shown.length,
              textColor: DashboardTableColors.secondaryText(context),
              accentColor: const Color(0xFF345892),
              mutedBackground: DashboardSearchField.defaultFill(context),
              onPrevious: () => onPage(current - 1),
              onNext: () => onPage(current + 1),
            ),
    );
  }
}

class _ProfessorRow extends StatelessWidget {
  const _ProfessorRow({
    super.key,
    required this.professor,
    required this.isDuplicate,
    required this.showDivider,
    required this.onConnect,
    required this.onMerge,
  });

  final ProfessorLinkRow professor;
  final bool isDuplicate;
  final bool showDivider;
  final VoidCallback? onConnect;
  final VoidCallback? onMerge;

  @override
  Widget build(BuildContext context) {
    final p = professor;
    final status = _statusOf(p);
    final dark = context.isDarkMode;
    final (label, tone) = switch (status) {
      _LinkStatus.signedIn => (
          'Signed in',
          dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D)
        ),
      _LinkStatus.waiting => (
          'Waiting',
          dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706)
        ),
      _LinkStatus.none => (
          'No email',
          dark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B)
        ),
    };
    final email = switch (status) {
      _LinkStatus.signedIn => p.email ?? '',
      _LinkStatus.waiting => p.claimedEmail ?? '',
      _LinkStatus.none => '',
    };
    final connectTooltip = !p.isStub
        ? 'Change login email'
        : p.claimedEmail == null
            ? 'Connect email'
            : 'Change email';

    return DashboardTableRow(
      columns: _columns,
      showDivider: showDivider,
      cells: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dashboardTablePrimaryStyle(context),
                  ),
                  Text(
                    p.employeeId == null ? '—' : 'ID ${p.employeeId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dashboardTableSubStyle(context),
                  ),
                ],
              ),
            ),
            if (isDuplicate)
              Tooltip(
                message: 'Possible duplicate',
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color:
                        dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                    semanticLabel: 'Possible duplicate',
                  ),
                ),
              ),
          ],
        ),
        Text('${p.classCount}', style: dashboardTableBodyStyle(context)),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tone.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 9 : 11,
                fontWeight: FontWeight.w600,
                color: tone,
              ),
            ),
          ),
        ),
        Text(
          email.isEmpty ? '—' : email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onConnect != null)
                DashboardRowIconButton(
                  key: ValueKey('connect-${p.id}'),
                  icon: Icons.alternate_email_rounded,
                  tooltip: connectTooltip,
                  onPressed: onConnect,
                ),
              if (onMerge != null)
                DashboardRowIconButton(
                  key: ValueKey('merge-${p.id}'),
                  icon: Icons.merge_type_rounded,
                  tooltip: 'Merge into another record',
                  onPressed: onMerge,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Waiting sign-ins (side card)
// ---------------------------------------------------------------------------

class _PendingLoginsCard extends StatelessWidget {
  const _PendingLoginsCard({
    required this.logins,
    required this.page,
    required this.onPage,
    required this.onLink,
  });

  final List<PendingLoginRow> logins;
  final int page;
  final ValueChanged<int> onPage;

  /// Null hides the Link buttons.
  final ValueChanged<PendingLoginRow>? onLink;

  @override
  Widget build(BuildContext context) {
    final pageSize = context.cardPageSize;
    final total = logins.length;
    final totalPages = total == 0 ? 1 : (total / pageSize).ceil();
    final current = page.clamp(1, totalPages);
    final pageItems =
        logins.skip((current - 1) * pageSize).take(pageSize).toList();
    final wellColor = DashboardSearchField.defaultFill(context);

    return BentoCard(
      backgroundColor: DashboardTableColors.card(context),
      borderColor: DashboardTableColors.border(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(29, 24, 29, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting Sign-ins',
                  style: dashboardCardTitleStyle(context,
                      color: DashboardTableColors.primaryText(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  '$total ${total == 1 ? 'sign-in' : 'sign-ins'} waiting',
                  style: TitledTableCard.subtitleStyle(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(29, 16, 29, 14),
            child: Text(
              'Microsoft sign-ins that are not tied to a professor record '
              'yet. Link each one to its record to approve it as a teacher.',
              style: dashboardTableSubStyle(context),
            ),
          ),
          DashboardTableRows(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            empty: Padding(
              padding: const EdgeInsets.fromLTRB(29, 8, 29, 24),
              child: Text(
                'No sign-ins are waiting.',
                style: dashboardTableBodyStyle(context),
              ),
            ),
            rows: [
              for (final login in pageItems)
                Container(
                  key: ValueKey('login-${login.id}'),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: wellColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        login.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: dashboardTablePrimaryStyle(context),
                      ),
                      if (login.fullName.isNotEmpty)
                        Text(
                          login.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: dashboardTableSubStyle(context),
                        ),
                      if (onLink != null) ...[
                        const SizedBox(height: 10),
                        SecondaryPillButton(
                          key: ValueKey('link-${login.id}'),
                          label: 'Link to professor',
                          icon: Icons.link_rounded,
                          expand: true,
                          onTap: () => onLink!(login),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          if (logins.length > pageSize)
            DashboardTableFooter(
              child: CardPaginationFooter(
                currentPage: current,
                totalPages: totalPages,
                totalCount: total,
                textColor: DashboardTableColors.secondaryText(context),
                accentColor: const Color(0xFF345892),
                mutedBackground: wellColor,
                onPrevious: () => onPage(current - 1),
                onNext: () => onPage(current + 1),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Popups
// ---------------------------------------------------------------------------

class _ConnectEmailDialog extends StatefulWidget {
  const _ConnectEmailDialog({required this.professor});

  final ProfessorLinkRow professor;

  @override
  State<_ConnectEmailDialog> createState() => _ConnectEmailDialogState();
}

class _ConnectEmailDialogState extends State<_ConnectEmailDialog> {
  late final _controller = TextEditingController(
    text: widget.professor.isStub
        ? (widget.professor.claimedEmail ?? '')
        : (widget.professor.email ?? ''),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.professor;
    final c = AppPopupColors.of(context);
    return AppPopup(
      title: p.isStub ? 'Connect login email' : 'Change login email',
      subtitle: p.fullName,
      width: 480,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('connect-save'),
          label: 'Save',
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            p.isStub
                ? 'Enter the exact Microsoft address this professor signs in '
                    'with. If they have already signed in they are linked '
                    'now; otherwise they are linked on their first sign-in. '
                    'Leave blank to clear.'
                : 'Currently signed in as ${p.email ?? 'an account'}. '
                    'Changing it moves all of this professor\'s classes to '
                    'the new address; the old account goes back to waiting '
                    'for approval. Leave blank to unlink without replacing.',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 11 : 12.5,
              height: 1.5,
              color: c.muted,
            ),
          ),
          kAppPopupFieldGap,
          AppPopupTextField(
            label: 'Microsoft email',
            hint: 'firstname.lastname@baliuag.sti.edu.ph',
            controller: _controller,
            keyboardType: TextInputType.emailAddress,
          ),
        ],
      ),
    );
  }
}

/// Picks one professor record from [options], the likely match (same name
/// key) first and tagged.
class _ProfessorPickerDialog extends StatelessWidget {
  const _ProfessorPickerDialog({
    required this.title,
    required this.subtitle,
    required this.options,
    this.suggestedKey,
  });

  final String title;
  final String subtitle;
  final List<ProfessorLinkRow> options;
  final String? suggestedKey;

  bool _isLikely(ProfessorLinkRow o) =>
      suggestedKey != null && suggestedKey!.isNotEmpty && o.nameKey == suggestedKey;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final entries = [
      for (final o in options)
        PickerEntry(
          id: o.id,
          title: o.fullName,
          subtitle: [
            if (o.employeeId != null) 'ID ${o.employeeId}',
            '${o.classCount} class${o.classCount == 1 ? '' : 'es'}',
          ].join(' · '),
          // The list sorts by year then name; year 0 puts the likely match
          // ahead of everything else.
          year: _isLikely(o) ? 0 : 1,
          badge: _isLikely(o) ? 'Likely match' : null,
        ),
    ];
    return AppPopup(
      title: title,
      subtitle: subtitle,
      width: 520,
      // The picker scrolls its own list, so it gets a bounded height.
      scrollBody: false,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SearchablePickerList(
              searchHint: 'Search professors',
              emptyMessage: 'No matching professor records.',
              groupNoun: 'professor',
              palette: PickerPalette(
                surface: c.card,
                field: c.fieldFill,
                border: c.border,
                text: c.text,
                muted: c.muted,
                placeholder: c.muted,
                accent: AppPopupColors.accent,
              ),
              entries: entries,
              onSelected: (id) {
                for (final o in options) {
                  if (o.id == id) {
                    Navigator.of(context).pop(o);
                    return;
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmMergeDialog extends StatelessWidget {
  const _ConfirmMergeDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    return AppPopup(
      title: 'Merge duplicate professors?',
      width: 460,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppPopupPrimaryButton(
          key: const Key('merge-confirm'),
          label: 'Merge',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      body: Text(
        '$count duplicate record(s) with the same name (ignoring Mr./Ms., '
        'capitals and name order) will be merged into one record per '
        'professor. Their classes move to the kept record. Two records that '
        'already have a login are never merged.',
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          height: 1.5,
          color: c.text,
        ),
      ),
    );
  }
}
