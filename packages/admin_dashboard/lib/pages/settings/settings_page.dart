import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Data models — swap the default*Settings constants with Supabase Auth /
// profile-table data later. fromJson/toJson keep each model round-trippable.
// ---------------------------------------------------------------------------

class UserProfileSettingsModel {
  const UserProfileSettingsModel({
    this.fullName = '',
    this.email = '',
    this.staffId = '',
    this.role = '',
    this.department = 'BSIT',
    this.phoneNumber = '',
  });

  final String fullName;
  final String email;
  final String staffId;
  final String role;
  final String department;
  final String phoneNumber;

  factory UserProfileSettingsModel.fromJson(Map<String, dynamic> json) {
    return UserProfileSettingsModel(
      fullName: json['fullName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      staffId: json['staffId'] as String? ?? '',
      role: json['role'] as String? ?? '',
      department: json['department'] as String? ?? 'BSIT',
      phoneNumber: json['phoneNumber'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'email': email,
        'staffId': staffId,
        'role': role,
        'department': department,
        'phoneNumber': phoneNumber,
      };

  UserProfileSettingsModel copyWith({
    String? fullName,
    String? email,
    String? staffId,
    String? role,
    String? department,
    String? phoneNumber,
  }) {
    return UserProfileSettingsModel(
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      staffId: staffId ?? this.staffId,
      role: role ?? this.role,
      department: department ?? this.department,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }
}

class SecuritySettingsModel {
  const SecuritySettingsModel({
    this.isTwoFactorEnabled = false,
    this.currentPassword = '',
    this.newPassword = '',
    this.confirmPassword = '',
  });

  final bool isTwoFactorEnabled;
  final String currentPassword;
  final String newPassword;
  final String confirmPassword;

  // Password fields are transient form state only — a real integration
  // sends them straight to a dedicated auth "change password" call and
  // never round-trips them through a stored settings payload, so they're
  // deliberately excluded from fromJson/toJson.
  factory SecuritySettingsModel.fromJson(Map<String, dynamic> json) {
    return SecuritySettingsModel(
      isTwoFactorEnabled: json['isTwoFactorEnabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'isTwoFactorEnabled': isTwoFactorEnabled,
      };

  SecuritySettingsModel copyWith({
    bool? isTwoFactorEnabled,
    String? currentPassword,
    String? newPassword,
    String? confirmPassword,
  }) {
    return SecuritySettingsModel(
      isTwoFactorEnabled: isTwoFactorEnabled ?? this.isTwoFactorEnabled,
      currentPassword: currentPassword ?? this.currentPassword,
      newPassword: newPassword ?? this.newPassword,
      confirmPassword: confirmPassword ?? this.confirmPassword,
    );
  }
}

class DisplayPreferencesModel {
  const DisplayPreferencesModel({
    this.themeMode = 'System',
    this.tableDensity = 'Comfortable',
    this.timeZone = 'Asia/Manila (GMT+8)',
    this.dateFormat = 'YYYY-MM-DD',
  });

  final String themeMode;
  final String tableDensity;
  final String timeZone;
  final String dateFormat;

  factory DisplayPreferencesModel.fromJson(Map<String, dynamic> json) {
    return DisplayPreferencesModel(
      themeMode: json['themeMode'] as String? ?? 'System',
      tableDensity: json['tableDensity'] as String? ?? 'Comfortable',
      timeZone: json['timeZone'] as String? ?? 'Asia/Manila (GMT+8)',
      dateFormat: json['dateFormat'] as String? ?? 'YYYY-MM-DD',
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode,
        'tableDensity': tableDensity,
        'timeZone': timeZone,
        'dateFormat': dateFormat,
      };

  DisplayPreferencesModel copyWith({
    String? themeMode,
    String? tableDensity,
    String? timeZone,
    String? dateFormat,
  }) {
    return DisplayPreferencesModel(
      themeMode: themeMode ?? this.themeMode,
      tableDensity: tableDensity ?? this.tableDensity,
      timeZone: timeZone ?? this.timeZone,
      dateFormat: dateFormat ?? this.dateFormat,
    );
  }
}

// ---------------------------------------------------------------------------
// Default (empty) state — replace with repository/API calls when backend
// is ready.
// ---------------------------------------------------------------------------

const defaultUserProfileSettings = UserProfileSettingsModel();
const defaultSecuritySettings = SecuritySettingsModel();
const defaultDisplayPreferences = DisplayPreferencesModel();

const _departmentOptions = ['BSIT', 'BSHM', 'BSBA', 'BSTM'];
const _themeModeOptions = ['Light', 'Dark', 'System'];
const _tableDensityOptions = ['Comfortable', 'Compact'];
const _timeZoneOptions = ['Asia/Manila (GMT+8)', 'UTC (GMT+0)'];
const _dateFormatOptions = ['YYYY-MM-DD', 'MM/DD/YYYY', 'DD/MM/YYYY'];

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _SettingsColors {
  static const background = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const cardBorder = Color(0xFFE2E8F0);
  static const fieldFill = Color(0xFFF1F5F9);
  static const primaryButton = Color(0xFF27426D);
  static const primaryButtonText = Color(0xFFFFFFFF);
  static const chipSelectedBg = Color(0xFFDBEAFE);
  static const chipSelectedBorder = Color(0xFF2563EB);
  static const chipSelectedText = Color(0xFF1D4ED8);
  static const avatarBg = Color(0xFFF1F5F9);
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.profile,
    required this.security,
    required this.preferences,
  });

  factory SettingsPage.empty({Key? key}) {
    return SettingsPage(
      key: key,
      profile: defaultUserProfileSettings,
      security: defaultSecuritySettings,
      preferences: defaultDisplayPreferences,
    );
  }

  final UserProfileSettingsModel profile;
  final SecuritySettingsModel security;
  final DisplayPreferencesModel preferences;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  late UserProfileSettingsModel _profile;
  late SecuritySettingsModel _security;
  late DisplayPreferencesModel _preferences;
  Uint8List? _avatarImageBytes;

  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _staffIdController = TextEditingController();
  final _phoneController = TextEditingController();

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    _profile = widget.profile;
    _security = widget.security;
    _preferences = widget.preferences;

    _fullNameController.text = _profile.fullName;
    _emailController.text = _profile.email;
    _staffIdController.text = _profile.staffId;
    _phoneController.text = _profile.phoneNumber;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _staffIdController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
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

  void _saveProfile() {
    setState(() {
      _profile = _profile.copyWith(
        fullName: _fullNameController.text,
        email: _emailController.text,
        staffId: _staffIdController.text,
        phoneNumber: _phoneController.text,
      );
    });
    _showActionSnackBar('Save Profile Changes tapped');
  }

  void _updatePassword() {
    setState(() {
      _security = _security.copyWith(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
        confirmPassword: _confirmPasswordController.text,
      );
    });
    _showActionSnackBar('Update Password tapped');
  }

  void _savePreferences() {
    _showActionSnackBar('Save Preferences tapped');
  }

  void _openPhotoUploadDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => _PhotoUploadDialog(onUpload: _onProfilePhotoUploaded),
    );
  }

  // Backend-ready hook — wire this to Supabase Storage once configured, e.g.
  //   final path = 'avatars/${_profile.staffId}.png';
  //   await supabase.storage.from('avatars').uploadBinary(path, imageBytes);
  //   final url = supabase.storage.from('avatars').getPublicUrl(path);
  void _onProfilePhotoUploaded(Uint8List imageBytes) {
    setState(() => _avatarImageBytes = imageBytes);
    _showActionSnackBar('Profile photo uploaded');
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _SettingsColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _SettingsColors.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Update your profile and application preferences.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: _SettingsColors.secondaryText,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: _SettingsColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _SettingsColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: _SettingsColors.cardBorder),
                          ),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          labelColor: _SettingsColors.primaryButton,
                          unselectedLabelColor: _SettingsColors.secondaryText,
                          indicatorColor: _SettingsColors.primaryButton,
                          indicatorSize: TabBarIndicatorSize.label,
                          labelStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          unselectedLabelStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          tabs: const [
                            Tab(
                              height: 48,
                              icon: Icon(Icons.person_outline_rounded, size: 18),
                              iconMargin: EdgeInsets.only(bottom: 4),
                              text: 'Account Profile',
                            ),
                            Tab(
                              height: 48,
                              icon: Icon(Icons.lock_outline_rounded, size: 18),
                              iconMargin: EdgeInsets.only(bottom: 4),
                              text: 'Security',
                            ),
                            Tab(
                              height: 48,
                              icon: Icon(Icons.palette_outlined, size: 18),
                              iconMargin: EdgeInsets.only(bottom: 4),
                              text: 'Display Preferences',
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _AccountProfileTab(
                              fullNameController: _fullNameController,
                              emailController: _emailController,
                              staffIdController: _staffIdController,
                              phoneController: _phoneController,
                              department: _profile.department,
                              avatarImageBytes: _avatarImageBytes,
                              onDepartmentChanged: (value) => setState(() =>
                                  _profile = _profile.copyWith(
                                      department: value ?? _profile.department)),
                              onUploadPhoto: _openPhotoUploadDialog,
                              onSaveProfile: _saveProfile,
                            ),
                            _SecurityTab(
                              currentPasswordController:
                                  _currentPasswordController,
                              newPasswordController: _newPasswordController,
                              confirmPasswordController:
                                  _confirmPasswordController,
                              isTwoFactorEnabled: _security.isTwoFactorEnabled,
                              onTwoFactorChanged: (value) => setState(() =>
                                  _security =
                                      _security.copyWith(isTwoFactorEnabled: value)),
                              onUpdatePassword: _updatePassword,
                            ),
                            _DisplayPreferencesTab(
                              preferences: _preferences,
                              onThemeModeChanged: (value) => setState(() =>
                                  _preferences =
                                      _preferences.copyWith(themeMode: value)),
                              onTableDensityChanged: (value) => setState(() =>
                                  _preferences =
                                      _preferences.copyWith(tableDensity: value)),
                              onTimeZoneChanged: (value) => setState(() =>
                                  _preferences = _preferences.copyWith(
                                      timeZone: value ?? _preferences.timeZone)),
                              onDateFormatChanged: (value) => setState(() =>
                                  _preferences = _preferences.copyWith(
                                      dateFormat: value ?? _preferences.dateFormat)),
                              onSavePreferences: _savePreferences,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
// Shared form widgets
// ---------------------------------------------------------------------------

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: _SettingsColors.primaryText,
      ),
    );
  }
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: _SettingsColors.primaryText,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.poppins(
              fontSize: 13,
              color: _SettingsColors.secondaryText,
            ),
            filled: true,
            fillColor: _SettingsColors.fieldFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SettingsColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SettingsColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SettingsColors.primaryButton),
            ),
          ),
        ),
      ],
    );
  }
}

class _LabeledDropdown extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          onChanged: onChanged,
          isExpanded: true,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: _SettingsColors.primaryText,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: _SettingsColors.fieldFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SettingsColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SettingsColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SettingsColors.primaryButton),
            ),
          ),
          items: [
            for (final option in options)
              DropdownMenuItem<String>(
                value: option,
                child: Text(option, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ],
    );
  }
}

class _TwoColumnFormGrid extends StatelessWidget {
  const _TwoColumnFormGrid({required this.fields});

  final List<Widget> fields;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < fields.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: fields[i]),
              const SizedBox(width: 16),
              Expanded(
                child: i + 1 < fields.length
                    ? fields[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

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
        backgroundColor: _SettingsColors.primaryButton,
        foregroundColor: _SettingsColors.primaryButtonText,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _SegmentButton(
              label: options[i],
              isSelected: selected == options[i],
              onTap: () => onChanged(options[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? _SettingsColors.chipSelectedBg
              : _SettingsColors.fieldFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? _SettingsColors.chipSelectedBorder
                : _SettingsColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? _SettingsColors.chipSelectedText
                : _SettingsColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — Account Profile
// ---------------------------------------------------------------------------

class _AccountProfileTab extends StatelessWidget {
  const _AccountProfileTab({
    required this.fullNameController,
    required this.emailController,
    required this.staffIdController,
    required this.phoneController,
    required this.department,
    required this.avatarImageBytes,
    required this.onDepartmentChanged,
    required this.onUploadPhoto,
    required this.onSaveProfile,
  });

  final TextEditingController fullNameController;
  final TextEditingController emailController;
  final TextEditingController staffIdController;
  final TextEditingController phoneController;
  final String department;
  final Uint8List? avatarImageBytes;
  final ValueChanged<String?> onDepartmentChanged;
  final VoidCallback onUploadPhoto;
  final VoidCallback onSaveProfile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _SettingsColors.avatarBg,
                  shape: BoxShape.circle,
                  image: avatarImageBytes == null
                      ? null
                      : DecorationImage(
                          image: MemoryImage(avatarImageBytes!),
                          fit: BoxFit.cover,
                        ),
                ),
                alignment: Alignment.center,
                child: avatarImageBytes == null
                    ? const Icon(
                        Icons.person_outline_rounded,
                        size: 30,
                        color: _SettingsColors.secondaryText,
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: onUploadPhoto,
                icon: const Icon(Icons.upload_outlined, size: 16),
                label: Text(
                  'Upload Photo',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _SettingsColors.primaryText,
                  side: const BorderSide(color: _SettingsColors.cardBorder),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _TwoColumnFormGrid(
            fields: [
              _LabeledTextField(
                label: 'Full Name',
                controller: fullNameController,
                hintText: 'Enter full name',
              ),
              _LabeledTextField(
                label: 'Work Email',
                controller: emailController,
                hintText: 'e.g. user@domain.edu',
                keyboardType: TextInputType.emailAddress,
              ),
              _LabeledTextField(
                label: 'Staff / Employee ID',
                controller: staffIdController,
                hintText: 'e.g. STF-2026-001',
              ),
              _LabeledDropdown(
                label: 'Department / Program',
                value: department,
                options: _departmentOptions,
                onChanged: onDepartmentChanged,
              ),
              _LabeledTextField(
                label: 'Phone Number',
                controller: phoneController,
                hintText: '+63 9XX XXX XXXX',
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: _PrimaryActionButton(
              icon: Icons.check_rounded,
              label: 'Save Profile Changes',
              onPressed: onSaveProfile,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — Security
// ---------------------------------------------------------------------------

class _SecurityTab extends StatelessWidget {
  const _SecurityTab({
    required this.currentPasswordController,
    required this.newPasswordController,
    required this.confirmPasswordController,
    required this.isTwoFactorEnabled,
    required this.onTwoFactorChanged,
    required this.onUpdatePassword,
  });

  final TextEditingController currentPasswordController;
  final TextEditingController newPasswordController;
  final TextEditingController confirmPasswordController;
  final bool isTwoFactorEnabled;
  final ValueChanged<bool> onTwoFactorChanged;
  final VoidCallback onUpdatePassword;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Change Password',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _SettingsColors.primaryText,
            ),
          ),
          const SizedBox(height: 16),
          _LabeledTextField(
            label: 'Current Password',
            controller: currentPasswordController,
            hintText: '••••••••',
            obscureText: true,
          ),
          const SizedBox(height: 16),
          _LabeledTextField(
            label: 'New Password',
            controller: newPasswordController,
            hintText: '••••••••',
            obscureText: true,
          ),
          const SizedBox(height: 16),
          _LabeledTextField(
            label: 'Confirm New Password',
            controller: confirmPasswordController,
            hintText: '••••••••',
            obscureText: true,
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: _PrimaryActionButton(
              icon: Icons.vpn_key_outlined,
              label: 'Update Password',
              onPressed: onUpdatePassword,
            ),
          ),
          const SizedBox(height: 28),
          const Divider(height: 1, color: _SettingsColors.cardBorder),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Two-Factor Authentication',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _SettingsColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Add an extra layer of security to your account',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: _SettingsColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: isTwoFactorEnabled,
                onChanged: onTwoFactorChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: _SettingsColors.primaryButton,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFE2E8F0),
                trackOutlineColor: WidgetStateProperty.resolveWith(
                  (states) => Colors.transparent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3 — Display Preferences
// ---------------------------------------------------------------------------

class _DisplayPreferencesTab extends StatelessWidget {
  const _DisplayPreferencesTab({
    required this.preferences,
    required this.onThemeModeChanged,
    required this.onTableDensityChanged,
    required this.onTimeZoneChanged,
    required this.onDateFormatChanged,
    required this.onSavePreferences,
  });

  final DisplayPreferencesModel preferences;
  final ValueChanged<String> onThemeModeChanged;
  final ValueChanged<String> onTableDensityChanged;
  final ValueChanged<String?> onTimeZoneChanged;
  final ValueChanged<String?> onDateFormatChanged;
  final VoidCallback onSavePreferences;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Theme Mode'),
          const SizedBox(height: 8),
          _SegmentedControl(
            options: _themeModeOptions,
            selected: preferences.themeMode,
            onChanged: onThemeModeChanged,
          ),
          const SizedBox(height: 20),
          const _FieldLabel('Table Density'),
          const SizedBox(height: 8),
          _SegmentedControl(
            options: _tableDensityOptions,
            selected: preferences.tableDensity,
            onChanged: onTableDensityChanged,
          ),
          const SizedBox(height: 20),
          _TwoColumnFormGrid(
            fields: [
              _LabeledDropdown(
                label: 'Time Zone',
                value: preferences.timeZone,
                options: _timeZoneOptions,
                onChanged: onTimeZoneChanged,
              ),
              _LabeledDropdown(
                label: 'Date Format',
                value: preferences.dateFormat,
                options: _dateFormatOptions,
                onChanged: onDateFormatChanged,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: _PrimaryActionButton(
              icon: Icons.check_rounded,
              label: 'Save Preferences',
              onPressed: onSavePreferences,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Photo upload modal — triggered from the "Upload Photo" button on the
// Account Profile tab.
// ---------------------------------------------------------------------------

class _PhotoUploadDialog extends StatefulWidget {
  const _PhotoUploadDialog({required this.onUpload});

  /// Backend-ready hook: swap the caller's implementation to push
  /// [imageBytes] to Supabase Storage (e.g. `supabase.storage
  /// .from('avatars').uploadBinary(path, imageBytes)`).
  final ValueChanged<Uint8List> onUpload;

  @override
  State<_PhotoUploadDialog> createState() => _PhotoUploadDialogState();
}

class _PhotoUploadDialogState extends State<_PhotoUploadDialog> {
  Uint8List? _imageBytes;
  bool _isPicking = false;

  Future<void> _browseForImage() async {
    setState(() => _isPicking = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      final bytes = result?.files.single.bytes;
      if (bytes != null && mounted) {
        setState(() => _imageBytes = bytes);
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _removePhoto() {
    setState(() => _imageBytes = null);
  }

  void _confirmUpload() {
    final bytes = _imageBytes;
    if (bytes == null) return;
    widget.onUpload(bytes);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canUpload = _imageBytes != null;

    return Dialog(
      backgroundColor: _SettingsColors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Upload Profile Picture',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _SettingsColors.primaryText,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: _SettingsColors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _imageBytes == null
                  ? _PhotoDropZone(
                      isBusy: _isPicking,
                      onTap: _isPicking ? null : _browseForImage,
                    )
                  : _PhotoPreview(
                      imageBytes: _imageBytes!,
                      onRemove: _removePhoto,
                    ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _SettingsColors.primaryText,
                      side: const BorderSide(color: _SettingsColors.cardBorder),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: canUpload ? _confirmUpload : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _SettingsColors.primaryButton,
                      foregroundColor: _SettingsColors.primaryButtonText,
                      disabledBackgroundColor: _SettingsColors.fieldFill,
                      disabledForegroundColor: _SettingsColors.secondaryText,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Upload & Save',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoDropZone extends StatelessWidget {
  const _PhotoDropZone({
    required this.isBusy,
    required this.onTap,
  });

  final bool isBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isBusy)
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _SettingsColors.primaryButton,
                ),
              )
            else
              const Icon(
                Icons.cloud_upload_outlined,
                size: 40,
                color: _SettingsColors.primaryButton,
              ),
            const SizedBox(height: 12),
            Text(
              'Drag and drop your image here, or browse',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _SettingsColors.primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Supports PNG, JPG, or WEBP (Max: 5MB)',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: _SettingsColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.imageBytes,
    required this.onRemove,
  });

  final Uint8List imageBytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 48,
            backgroundImage: MemoryImage(imageBytes),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: Text(
              'Remove Photo',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: BorderSide(color: Colors.grey.shade300),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
