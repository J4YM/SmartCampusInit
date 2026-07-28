import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../staff_accounts/staff_accounts_page.dart' show StaffRole;

// ---------------------------------------------------------------------------
// Data model — swap defaultUnclaimedProfiles with Supabase/API data later.
// ---------------------------------------------------------------------------

/// A `profiles` row with no RFID card linked yet — either a pending staff
/// sign-in (still needs a role assigned) or an already-approved account
/// (staff or student) that just hasn't had a card linked.
class UnclaimedProfileModel {
  const UnclaimedProfileModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.roleLabel,
    required this.isPending,
    required this.requestedAt,
  });

  final String id;
  final String fullName;
  final String? email;

  /// e.g. "Teacher", "Student", or "Pending" when [isPending] is true.
  final String roleLabel;
  final bool isPending;
  final DateTime? requestedAt;
}

// ---------------------------------------------------------------------------
// Default dataset — replace with repository/API calls when backend is ready.
// ---------------------------------------------------------------------------

const defaultUnclaimedProfiles = <UnclaimedProfileModel>[];

String _formatRequestedAt(DateTime value) {
  final year = value.year;
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _RfidColors {
  static const background = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const cardBorder = Color(0xFFE2E8F0);
  static const fieldFill = Color(0xFFFFFFFF);
  static const primaryButton = Color(0xFF2563EB);
  static const primaryButtonText = Color(0xFFFFFFFF);
  static const secondaryButtonBg = Color(0xFFF1F5F9);
  static const pendingBadgeBg = Color(0xFFFFEDD5);
  static const pendingBadgeText = Color(0xFFEA580C);
  static const assignBg = Color(0xFFDBEAFE);
  static const assignText = Color(0xFF1D4ED8);
  static const headerText = Color(0xFF94A3B8);
  static const emptyStateIcon = Color(0xFFCBD5E1);
}

abstract final class _RfidTableLayout {
  static const columnFlex = <int>[3, 2, 2, 2];
  static const horizontalPadding = 16.0;
  static const columnGap = 8.0;
  static const rowVerticalPadding = 14.0;
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class RfidMappingPage extends StatefulWidget {
  const RfidMappingPage({
    super.key,
    required this.unclaimedProfiles,
    this.onAssignCard,
    this.isBusy = false,
  });

  factory RfidMappingPage.empty({Key? key}) {
    return RfidMappingPage(key: key, unclaimedProfiles: defaultUnclaimedProfiles);
  }

  final List<UnclaimedProfileModel> unclaimedProfiles;

  /// Links a card to a profile. [role] is required when the target profile
  /// is pending (approves it in the same action); ignored otherwise. When
  /// omitted (the `.empty()` demo path), the form is inert.
  final Future<void> Function({
    required String profileId,
    required String cardUid,
    StaffRole? role,
  })? onAssignCard;

  /// True while a parent-level refresh/mutation is in flight.
  final bool isBusy;

  @override
  State<RfidMappingPage> createState() => _RfidMappingPageState();
}

class _RfidMappingPageState extends State<RfidMappingPage> {
  final _cardUidController = TextEditingController();
  String? _selectedProfileId;
  StaffRole? _selectedRole;
  bool _submitting = false;

  @override
  void dispose() {
    _cardUidController.dispose();
    super.dispose();
  }

  void _showActionSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleClear() {
    setState(() {
      _cardUidController.clear();
      _selectedProfileId = null;
      _selectedRole = null;
    });
  }

  UnclaimedProfileModel? get _selectedProfile {
    final id = _selectedProfileId;
    if (id == null) return null;
    for (final p in widget.unclaimedProfiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _selectProfile(String profileId) {
    setState(() {
      _selectedProfileId = profileId;
      _selectedRole = null;
    });
  }

  Future<void> _handleAssignCard() async {
    final cardUid = _cardUidController.text.trim();
    final profile = _selectedProfile;
    final onAssignCard = widget.onAssignCard;

    if (cardUid.isEmpty || profile == null || onAssignCard == null) {
      _showActionSnackBar('Enter a card UID and pick a profile first.');
      return;
    }
    if (profile.isPending && _selectedRole == null) {
      _showActionSnackBar('Choose a role to approve this pending profile.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await onAssignCard(
        profileId: profile.id,
        cardUid: cardUid,
        role: _selectedRole,
      );
      if (!mounted) return;
      _showActionSnackBar('Card $cardUid assigned to ${profile.fullName}.');
      _handleClear();
    } catch (e) {
      _showActionSnackBar('Could not assign card: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _RfidColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RFID Card Mapping',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _RfidColors.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Assign and review RFID card mappings for users.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: _RfidColors.secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              _FastAssignCard(
                cardUidController: _cardUidController,
                profiles: widget.unclaimedProfiles,
                selectedProfileId: _selectedProfileId,
                selectedRole: _selectedRole,
                submitting: _submitting,
                onProfileChanged: (id) {
                  if (id != null) _selectProfile(id);
                },
                onRoleChanged: (role) => setState(() => _selectedRole = role),
                onClear: _handleClear,
                onAssignCard: _handleAssignCard,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _UnclaimedProfilesSection(
                  profiles: widget.unclaimedProfiles,
                  onAssign: (profile) => _selectProfile(profile.id),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fast-assign form card
// ---------------------------------------------------------------------------

class _FastAssignCard extends StatelessWidget {
  const _FastAssignCard({
    required this.cardUidController,
    required this.profiles,
    required this.selectedProfileId,
    required this.selectedRole,
    required this.submitting,
    required this.onProfileChanged,
    required this.onRoleChanged,
    required this.onClear,
    required this.onAssignCard,
  });

  final TextEditingController cardUidController;
  final List<UnclaimedProfileModel> profiles;
  final String? selectedProfileId;
  final StaffRole? selectedRole;
  final bool submitting;
  final ValueChanged<String?> onProfileChanged;
  final ValueChanged<StaffRole?> onRoleChanged;
  final VoidCallback onClear;
  final VoidCallback onAssignCard;

  @override
  Widget build(BuildContext context) {
    final selectedProfile = profiles.where((p) => p.id == selectedProfileId).firstOrNull;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _RfidColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _RfidColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fast-Assign RFID Card',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _RfidColors.primaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Scan a card via hardware reader or type the card UID manually',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: _RfidColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _RfidColors.cardBorder),
          Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 720;

                final cardUidField = _LabeledField(
                  label: 'Card UID (from hardware scan)',
                  controller: cardUidController,
                  hintText: 'e.g. A4:F2:88:1C',
                );
                final profileField = _ProfilePickerField(
                  profiles: profiles,
                  selectedProfileId: selectedProfileId,
                  onChanged: onProfileChanged,
                );

                final fields = stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cardUidField,
                          const SizedBox(height: 16),
                          profileField,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: cardUidField),
                          const SizedBox(width: 24),
                          Expanded(child: profileField),
                        ],
                      );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    fields,
                    if (selectedProfile?.isPending == true) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: stacked ? double.infinity : 320,
                        child: _RolePickerField(
                          selectedRole: selectedRole,
                          onChanged: onRoleChanged,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _SecondaryButton(label: 'Clear', onPressed: onClear),
                        const SizedBox(width: 12),
                        _PrimaryButton(
                          icon: Icons.check_circle_outline_rounded,
                          label: submitting ? 'Assigning...' : 'Assign Card',
                          onPressed: submitting ? null : onAssignCard,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _ProfilePickerField extends StatelessWidget {
  const _ProfilePickerField({
    required this.profiles,
    required this.selectedProfileId,
    required this.onChanged,
  });

  final List<UnclaimedProfileModel> profiles;
  final String? selectedProfileId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assign to profile',
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _RfidColors.primaryText,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: profiles.any((p) => p.id == selectedProfileId) ? selectedProfileId : null,
          isExpanded: true,
          hint: Text(
            'Search profile name or email...',
            style: GoogleFonts.poppins(fontSize: 13, color: _RfidColors.secondaryText),
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: _RfidColors.fieldFill,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _RfidColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _RfidColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _RfidColors.primaryButton),
            ),
          ),
          items: profiles
              .map(
                (p) => DropdownMenuItem<String>(
                  value: p.id,
                  child: Text(
                    '${p.fullName} · ${p.roleLabel}',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 13, color: _RfidColors.primaryText),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RolePickerField extends StatelessWidget {
  const _RolePickerField({required this.selectedRole, required this.onChanged});

  final StaffRole? selectedRole;
  final ValueChanged<StaffRole?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Role (required to approve this pending profile)',
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _RfidColors.primaryText,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<StaffRole>(
          value: selectedRole,
          isExpanded: true,
          hint: const Text('Assign role'),
          decoration: InputDecoration(
            filled: true,
            fillColor: _RfidColors.fieldFill,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _RfidColors.cardBorder),
            ),
          ),
          items: StaffRole.values
              .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hintText,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _RfidColors.primaryText,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: _RfidColors.primaryText,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.poppins(
              fontSize: 13,
              color: _RfidColors.secondaryText,
            ),
            filled: true,
            fillColor: _RfidColors.fieldFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _RfidColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _RfidColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _RfidColors.primaryButton),
            ),
          ),
        ),
      ],
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: _RfidColors.secondaryButtonBg,
        foregroundColor: _RfidColors.primaryText,
        side: const BorderSide(color: _RfidColors.cardBorder),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF27426D),
        foregroundColor: _RfidColors.primaryButtonText,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Unclaimed profiles table
// ---------------------------------------------------------------------------

class _UnclaimedProfilesSection extends StatelessWidget {
  const _UnclaimedProfilesSection({
    required this.profiles,
    required this.onAssign,
  });

  final List<UnclaimedProfileModel> profiles;
  final ValueChanged<UnclaimedProfileModel> onAssign;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Unclaimed Profiles',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _RfidColors.primaryText,
              ),
            ),
            const SizedBox(width: 10),
            _CountPill(count: profiles.length),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _RfidColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _RfidColors.cardBorder),
            ),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _TableHeaderRow(),
                  const Divider(height: 1, color: _RfidColors.cardBorder),
                  Expanded(
                    child: profiles.isEmpty
                        ? const _EmptyTableState(
                            icon: Icons.credit_card_off_rounded,
                            message: 'No unclaimed profiles found',
                          )
                        : ListView.builder(
                            itemCount: profiles.length,
                            itemBuilder: (context, index) {
                              final profile = profiles[index];
                              return _TableRow(
                                profile: profile,
                                showDivider: index < profiles.length - 1,
                                onAssign: () => onAssign(profile),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _RfidColors.pendingBadgeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count unassigned',
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _RfidColors.pendingBadgeText,
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell({
    required this.flex,
    required this.child,
    required this.isLast,
    this.alignRight = false,
  });

  final int flex;
  final Widget child;
  final bool isLast;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.only(
          right: isLast ? 0 : _RfidTableLayout.columnGap,
        ),
        child: Align(
          alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }
}

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    const headers = ['NAME / EMAIL', 'ROLE / STATUS', 'REQUESTED', 'ACTIONS'];
    const flexValues = _RfidTableLayout.columnFlex;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _RfidTableLayout.horizontalPadding,
        vertical: _RfidTableLayout.rowVerticalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < headers.length; i++)
            _TableCell(
              flex: flexValues[i],
              isLast: i == headers.length - 1,
              alignRight: i == headers.length - 1,
              child: Text(
                headers[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: _RfidColors.headerText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.profile,
    required this.showDivider,
    required this.onAssign,
  });

  final UnclaimedProfileModel profile;
  final bool showDivider;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    const flexValues = _RfidTableLayout.columnFlex;

    return Container(
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                bottom: BorderSide(color: _RfidColors.cardBorder),
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _RfidTableLayout.horizontalPadding,
          vertical: _RfidTableLayout.rowVerticalPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _TableCell(
              flex: flexValues[0],
              isLast: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _RfidColors.primaryText,
                    ),
                  ),
                  Text(
                    profile.email ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: _RfidColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            _TableCell(
              flex: flexValues[1],
              isLast: false,
              child: profile.isPending
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _RfidColors.pendingBadgeBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Pending',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _RfidColors.pendingBadgeText,
                        ),
                      ),
                    )
                  : Text(
                      profile.roleLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _RfidColors.primaryText,
                      ),
                    ),
            ),
            _TableCell(
              flex: flexValues[2],
              isLast: false,
              child: Text(
                profile.requestedAt == null ? '—' : _formatRequestedAt(profile.requestedAt!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _RfidColors.secondaryText,
                ),
              ),
            ),
            _TableCell(
              flex: flexValues[3],
              isLast: true,
              alignRight: true,
              child: _RowActions(onAssign: onAssign),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({required this.onAssign});

  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onAssign,
      style: TextButton.styleFrom(
        backgroundColor: _RfidColors.assignBg,
        foregroundColor: _RfidColors.assignText,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        'Assign',
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyTableState extends StatelessWidget {
  const _EmptyTableState({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: _RfidColors.emptyStateIcon),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _RfidColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
