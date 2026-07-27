import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Data model — Supabase Auth / `profiles` table ready.
// fromJson()/toJson() map onto snake_case columns so a profile row can be
// loaded in and edits can be pushed back via an update RPC/query.
// ---------------------------------------------------------------------------

// Every Discipline Officer Module account is, by definition, a discipline
// officer — so this is the hardcoded default/fallback role rather than an
// empty placeholder like the other fields.
const _defaultRoleTitle = 'Discipline Officer';

class UserAccountInfoModel {
  const UserAccountInfoModel({
    this.prefix = '',
    this.fullName = '',
    this.roleTitle = _defaultRoleTitle,
    this.emailAddress = '',
    this.phoneNumber = '',
    this.profileImageUrl,
  });

  final String prefix;
  final String fullName;
  final String roleTitle;
  final String emailAddress;
  final String phoneNumber;
  final String? profileImageUrl;

  factory UserAccountInfoModel.fromJson(Map<String, dynamic> json) {
    final fetchedRole = json['role_title'] as String?;
    return UserAccountInfoModel(
      prefix: json['prefix'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      // TODO(supabase): if `fetchedRole` was null/blank, this also needs to
      // be written back via an update to the `profiles` table so the row
      // itself carries the default instead of only this client falling
      // back to it on every load.
      roleTitle: (fetchedRole == null || fetchedRole.isEmpty)
          ? _defaultRoleTitle
          : fetchedRole,
      emailAddress: json['email_address'] as String? ?? '',
      phoneNumber: json['phone_number'] as String? ?? '',
      profileImageUrl: json['profile_image_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'prefix': prefix,
      'full_name': fullName,
      'role_title': roleTitle,
      'email_address': emailAddress,
      'phone_number': phoneNumber,
      'profile_image_url': profileImageUrl,
    };
  }

  UserAccountInfoModel copyWith({
    String? prefix,
    String? fullName,
    String? roleTitle,
    String? emailAddress,
    String? phoneNumber,
    String? profileImageUrl,
  }) {
    return UserAccountInfoModel(
      prefix: prefix ?? this.prefix,
      fullName: fullName ?? this.fullName,
      roleTitle: roleTitle ?? this.roleTitle,
      emailAddress: emailAddress ?? this.emailAddress,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    );
  }
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _ProfileColors {
  static const headerBackground = Color(0xFF15253F);
  static const headerBorder = Color(0x1AFFFFFF);
  static const headerIconBg = Color(0x14FFFFFF);
  static const surfaceBackground = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE2E8F0);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const placeholderText = Color(0xFF94A3B8);
  static const accentBlue = Color(0xFF2563EB);
  static const primaryButton = Color(0xFF345892);
}

// ---------------------------------------------------------------------------
// Account Information screen — profile avatar + editable account details.
// Backend-ready: `accountInfo` is the single source of truth, initialized
// empty; a real load would replace it with a Supabase-fetched row.
// ---------------------------------------------------------------------------

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserAccountInfoModel accountInfo = const UserAccountInfoModel();

  // Tracks whether a password has been configured, without ever holding the
  // real password value in widget state. The edit modal always starts blank.
  bool hasPasswordSet = false;

  void _openEditAccountDetailsModal() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _EditAccountDetailsDialog(
          initialAccountInfo: accountInfo,
          onSave: (updatedData) {
            setState(() => accountInfo = updatedData);

            // TODO(supabase): push `updatedData.toJson()` (name/email/phone)
            // to the `profiles` table / auth user metadata.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Account details updated',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
    );
  }

  void _openUpdatePasswordModal() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _UpdatePasswordDialog(
          onUpdatePassword: ({
            required String currentPassword,
            required String newPassword,
          }) async {
            // TODO(supabase): verify `currentPassword` (e.g. via a
            // reauthentication call) then call
            // supabase.auth.updateUser(UserAttributes(password: newPassword)).
            setState(() => hasPasswordSet = true);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Password updated',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
    );
  }

  void _showUploadPhotoDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _UploadProfilePictureDialog(
          onUpload: (imageBytes) {
            // TODO(supabase): upload `imageBytes` via
            // supabase.storage.from('avatars').upload(...) and patch
            // `accountInfo.profileImageUrl` with the returned public URL.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Profile picture uploaded',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ProfileColors.surfaceBackground,
      body: Column(
        children: [
          const _ProfileTopBar(title: 'Account Information'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProfileHeaderCard(
                        accountInfo: accountInfo,
                        onChangePhoto: _showUploadPhotoDialog,
                      ),
                      const SizedBox(height: 20),
                      _ReadOnlyAccountDetailsCard(
                        accountInfo: accountInfo,
                        onEdit: _openEditAccountDetailsModal,
                      ),
                      const SizedBox(height: 20),
                      _AccountSecurityCard(
                        hasPasswordSet: hasPasswordSet,
                        onUpdatePassword: _openUpdatePasswordModal,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top navy bar
// ---------------------------------------------------------------------------

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _ProfileColors.headerBackground,
      padding: const EdgeInsets.fromLTRB(20, 16, 24, 16),
      child: Row(
        children: [
          Material(
            color: _ProfileColors.headerIconBg,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(10),
              hoverColor: Colors.white.withOpacity(0.08),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _ProfileColors.headerBorder),
                ),
                child: const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared card shell
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _ProfileColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ProfileColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _ProfileColors.primaryText,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card 1 — Profile
// ---------------------------------------------------------------------------

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.accountInfo,
    required this.onChangePhoto,
  });

  final UserAccountInfoModel accountInfo;
  final VoidCallback onChangePhoto;

  @override
  Widget build(BuildContext context) {
    final hasName = accountInfo.fullName.isNotEmpty;
    final displayName = hasName
        ? (accountInfo.prefix.isEmpty
            ? accountInfo.fullName
            : '${accountInfo.prefix} ${accountInfo.fullName}')
        : 'Add your name';
    final hasRole = accountInfo.roleTitle.isNotEmpty;

    return _SectionCard(
      title: 'Profile',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _ProfileColors.surfaceBackground,
                  shape: BoxShape.circle,
                  image: accountInfo.profileImageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(accountInfo.profileImageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: accountInfo.profileImageUrl == null
                    ? const Icon(
                        Icons.person_outline,
                        size: 36,
                        color: _ProfileColors.secondaryText,
                      )
                    : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Material(
                  color: _ProfileColors.accentBlue,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: onChangePhoto,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontStyle: hasName ? FontStyle.normal : FontStyle.italic,
                    color: hasName
                        ? _ProfileColors.primaryText
                        : _ProfileColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasRole ? accountInfo.roleTitle : _defaultRoleTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: onChangePhoto,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    alignment: Alignment.centerLeft,
                  ),
                  child: Text(
                    'Change photo',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _ProfileColors.accentBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Upload Profile Picture modal
// ---------------------------------------------------------------------------

class _UploadProfilePictureDialog extends StatefulWidget {
  const _UploadProfilePictureDialog({required this.onUpload});

  /// Called with the picked image's raw bytes once "Upload & Save" is
  /// pressed. The caller is responsible for the actual Storage upload.
  final ValueChanged<Uint8List> onUpload;

  @override
  State<_UploadProfilePictureDialog> createState() =>
      _UploadProfilePictureDialogState();
}

class _UploadProfilePictureDialogState
    extends State<_UploadProfilePictureDialog> {
  Uint8List? _selectedImageBytes;
  String? _selectedFileName;

  Future<void> _browseForImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    final picked = result?.files.single;
    if (picked?.bytes == null) return;

    setState(() {
      _selectedImageBytes = picked!.bytes;
      _selectedFileName = picked.name;
    });
  }

  void _handleUploadAndSave() {
    final bytes = _selectedImageBytes;
    if (bytes == null) return;
    widget.onUpload(bytes);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _selectedImageBytes != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        fontWeight: FontWeight.w700,
                        color: _ProfileColors.primaryText,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(999),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: _ProfileColors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              InkWell(
                onTap: _browseForImage,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 32,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _ProfileColors.cardBorder),
                  ),
                  child: hasImage
                      ? _SelectedImagePreview(
                          imageBytes: _selectedImageBytes!,
                          fileName: _selectedFileName,
                        )
                      : const _DropZonePrompt(),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _ProfileColors.cardBorder),
                      foregroundColor: _ProfileColors.primaryText,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
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
                    onPressed: hasImage ? _handleUploadAndSave : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ProfileColors.headerBackground,
                      disabledBackgroundColor: _ProfileColors.surfaceBackground,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: _ProfileColors.placeholderText,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
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

class _DropZonePrompt extends StatelessWidget {
  const _DropZonePrompt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.cloud_upload_outlined,
          size: 42,
          color: _ProfileColors.headerBackground,
        ),
        const SizedBox(height: 12),
        Text(
          'Drag and drop your image here, or browse',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _ProfileColors.primaryText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Supports PNG, JPG, or WEBP (Max: 5MB)',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: _ProfileColors.secondaryText,
          ),
        ),
      ],
    );
  }
}

class _SelectedImagePreview extends StatelessWidget {
  const _SelectedImagePreview({required this.imageBytes, this.fileName});

  final Uint8List imageBytes;
  final String? fileName;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            imageBytes,
            height: 96,
            width: 96,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          fileName ?? 'Selected image',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _ProfileColors.primaryText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to choose a different image',
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: _ProfileColors.secondaryText,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Card 2 — Account Details (read-only)
// ---------------------------------------------------------------------------

class _ReadOnlyAccountDetailsCard extends StatelessWidget {
  const _ReadOnlyAccountDetailsCard({
    required this.accountInfo,
    required this.onEdit,
  });

  final UserAccountInfoModel accountInfo;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Account Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReadOnlyDetailField(
            label: 'Full Name',
            value: accountInfo.fullName,
            hintText: 'Add your name',
          ),
          const SizedBox(height: 18),
          _ReadOnlyDetailField(
            label: 'Email Address',
            value: accountInfo.emailAddress,
            hintText: 'Enter your email address',
          ),
          const SizedBox(height: 18),
          _ReadOnlyDetailField(
            label: 'Phone Number',
            value: accountInfo.phoneNumber,
            hintText: 'Enter your phone number',
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onEdit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _ProfileColors.primaryButton,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                'Edit account details',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card 3 — Account Security (read-only)
// ---------------------------------------------------------------------------

class _AccountSecurityCard extends StatelessWidget {
  const _AccountSecurityCard({
    required this.hasPasswordSet,
    required this.onUpdatePassword,
  });

  final bool hasPasswordSet;
  final VoidCallback onUpdatePassword;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Account Security',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReadOnlyDetailField(
            label: 'Password',
            value: hasPasswordSet ? '••••••••••••' : '',
            hintText: 'Not set',
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onUpdatePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: _ProfileColors.primaryButton,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                'Update password',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyDetailField extends StatelessWidget {
  const _ReadOnlyDetailField({
    required this.label,
    required this.value,
    required this.hintText,
  });

  final String label;
  final String value;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final hasValue = value.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _ProfileColors.secondaryText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hasValue ? value : hintText,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
            fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
            color: hasValue
                ? _ProfileColors.primaryText
                : _ProfileColors.placeholderText,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Edit Account Details modal
// ---------------------------------------------------------------------------

typedef _EditAccountDetailsSaveCallback = void Function(
  UserAccountInfoModel updatedData,
);

class _EditAccountDetailsDialog extends StatefulWidget {
  const _EditAccountDetailsDialog({
    required this.initialAccountInfo,
    required this.onSave,
  });

  final UserAccountInfoModel initialAccountInfo;
  final _EditAccountDetailsSaveCallback onSave;

  @override
  State<_EditAccountDetailsDialog> createState() =>
      _EditAccountDetailsDialogState();
}

class _EditAccountDetailsDialogState extends State<_EditAccountDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _fullNameController =
      TextEditingController(text: widget.initialAccountInfo.fullName);
  late final _emailController =
      TextEditingController(text: widget.initialAccountInfo.emailAddress);
  late final _phoneController =
      TextEditingController(text: widget.initialAccountInfo.phoneNumber);

  static final _phoneFormat = RegExp(r'^[0-9+\-\s()]+$');

  @override
  void initState() {
    super.initState();
    // Re-evaluate the Save button's enabled state as the user types, since
    // it only depends on whether every editable field is blank. Email is
    // administratively managed and read-only, so it's excluded here.
    _fullNameController.addListener(_handleFieldsChanged);
    _phoneController.addListener(_handleFieldsChanged);
  }

  @override
  void dispose() {
    _fullNameController.removeListener(_handleFieldsChanged);
    _phoneController.removeListener(_handleFieldsChanged);
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _handleFieldsChanged() => setState(() {});

  bool get _allFieldsBlank =>
      _fullNameController.text.trim().isEmpty &&
      _phoneController.text.trim().isEmpty;

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return null;
    return _phoneFormat.hasMatch(phone) ? null : 'Enter a valid phone number';
  }

  void _handleSave() {
    if (_allFieldsBlank) return;
    if (!_formKey.currentState!.validate()) return;

    final fullName = _fullNameController.text.trim();
    final phone = _phoneController.text.trim();

    // A blank field means "leave this unchanged" — only the fields the
    // user actually filled in overwrite the existing account info. Email
    // is administratively managed here and is always carried over as-is.
    widget.onSave(
      widget.initialAccountInfo.copyWith(
        fullName:
            fullName.isEmpty ? widget.initialAccountInfo.fullName : fullName,
        emailAddress: widget.initialAccountInfo.emailAddress,
        phoneNumber:
            phone.isEmpty ? widget.initialAccountInfo.phoneNumber : phone,
      ),
    );
    Navigator.of(context).pop();
  }

  void _handleCancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Details',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _ProfileColors.primaryText,
                  ),
                ),
                const SizedBox(height: 20),
                _EditModalField(
                  label: 'Full Name',
                  controller: _fullNameController,
                  hintText: 'Enter your full name',
                ),
                const SizedBox(height: 16),
                _EditModalField(
                  label: 'Email Address',
                  controller: _emailController,
                  hintText: 'Enter your email address',
                  keyboardType: TextInputType.emailAddress,
                  enabled: false,
                  helperText:
                      'Email address is managed by the administrator and '
                      'cannot be changed.',
                ),
                const SizedBox(height: 16),
                _EditModalField(
                  label: 'Phone Number',
                  controller: _phoneController,
                  hintText: 'Enter your phone number',
                  keyboardType: TextInputType.phone,
                  validator: _validatePhone,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _allFieldsBlank ? null : _handleSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _ProfileColors.primaryButton,
                          disabledBackgroundColor:
                              _ProfileColors.surfaceBackground,
                          foregroundColor: Colors.white,
                          disabledForegroundColor:
                              _ProfileColors.placeholderText,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Save changes',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _handleCancel,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE2E8F0),
                          foregroundColor: const Color(0xFF475569),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Update Password modal
// ---------------------------------------------------------------------------

typedef _UpdatePasswordCallback = Future<void> Function({
  required String currentPassword,
  required String newPassword,
});

class _UpdatePasswordDialog extends StatefulWidget {
  const _UpdatePasswordDialog({required this.onUpdatePassword});

  /// Backend-ready stub — the caller wires this to
  /// `supabase.auth.updateUser(UserAttributes(password: newPassword))`
  /// after verifying `currentPassword` via reauthentication.
  final _UpdatePasswordCallback onUpdatePassword;

  @override
  State<_UpdatePasswordDialog> createState() => _UpdatePasswordDialogState();
}

class _UpdatePasswordDialogState extends State<_UpdatePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Re-evaluate the Save button's enabled state on every keystroke.
    _currentPasswordController.addListener(_handleFieldsChanged);
    _newPasswordController.addListener(_handleFieldsChanged);
    _confirmPasswordController.addListener(_handleFieldsChanged);
  }

  @override
  void dispose() {
    _currentPasswordController.removeListener(_handleFieldsChanged);
    _newPasswordController.removeListener(_handleFieldsChanged);
    _confirmPasswordController.removeListener(_handleFieldsChanged);
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleFieldsChanged() => setState(() {});

  bool get _isFormValid =>
      _currentPasswordController.text.trim().isNotEmpty &&
      _newPasswordController.text.trim().isNotEmpty &&
      _confirmPasswordController.text.trim().isNotEmpty &&
      _newPasswordController.text == _confirmPasswordController.text;

  void _resetFields() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
  }

  void _handleCancel() {
    _resetFields();
    Navigator.of(context).pop();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    await widget.onUpdatePassword(
      currentPassword: _currentPasswordController.text,
      newPassword: _newPasswordController.text,
    );
    if (!mounted) return;

    _resetFields();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Password',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _ProfileColors.primaryText,
                  ),
                ),
                const SizedBox(height: 20),
                _EditModalField(
                  label: 'Current password',
                  controller: _currentPasswordController,
                  hintText: 'Enter your current password',
                  obscureText: true,
                  validator: (value) => (value == null || value.isEmpty)
                      ? 'Current password is required'
                      : null,
                ),
                const SizedBox(height: 16),
                _EditModalField(
                  label: 'New password',
                  controller: _newPasswordController,
                  hintText: 'Enter a new password',
                  obscureText: _obscureNew,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: _ProfileColors.placeholderText,
                    ),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                  validator: (value) {
                    final password = value ?? '';
                    if (password.isEmpty) return 'New password is required';
                    if (password.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _EditModalField(
                  label: 'Confirm password',
                  controller: _confirmPasswordController,
                  hintText: 'Re-enter your new password',
                  obscureText: _obscureConfirm,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: _ProfileColors.placeholderText,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (value) {
                    if (value != _newPasswordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed:
                            (_isSaving || !_isFormValid) ? null : _handleSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _ProfileColors.primaryButton,
                          disabledBackgroundColor:
                              _ProfileColors.surfaceBackground,
                          foregroundColor: Colors.white,
                          disabledForegroundColor:
                              _ProfileColors.placeholderText,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Save changes',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _handleCancel,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE2E8F0),
                          foregroundColor: const Color(0xFF475569),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditModalField extends StatelessWidget {
  const _EditModalField({
    required this.label,
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.enabled = true,
    this.helperText,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          validator: validator,
          enabled: enabled,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: enabled
                ? _ProfileColors.primaryText
                : _ProfileColors.secondaryText,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hintText,
            hintStyle: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: _ProfileColors.placeholderText,
            ),
            filled: true,
            fillColor: enabled
                ? _ProfileColors.surfaceBackground
                : const Color(0xFFE2E8F0),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: _ProfileColors.accentBlue,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: Color(0xFFDC2626), width: 1.5),
            ),
            errorStyle: GoogleFonts.poppins(fontSize: 11),
            suffixIcon: suffixIcon,
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            helperText!,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: _ProfileColors.secondaryText,
            ),
          ),
        ],
      ],
    );
  }
}
