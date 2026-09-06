import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';

class SidebarFooter extends StatelessWidget {
  const SidebarFooter({
    super.key,
    required this.name,
    required this.email,
    required this.onSettingsTap,
    required this.onLogoutTap,
    this.isCollapsed = false,
  });

  final String name;
  final String email;
  final VoidCallback onSettingsTap;
  final VoidCallback onLogoutTap;

  /// True when the sidebar is the icon-only rail — shows just the avatar and
  /// icon-only action buttons, with name/email/labels moved into tooltips.
  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.sidebarDivider),
      ),
      child: const Icon(
        Icons.person_outline_rounded,
        size: 20,
        color: AppColors.sidebarText,
      ),
    );

    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Tooltip(message: '$name\n$email', child: avatar),
            const SizedBox(height: 12),
            Tooltip(
              message: 'Settings',
              child: _FooterIconButton(
                icon: Icons.settings_outlined,
                onTap: onSettingsTap,
              ),
            ),
            const SizedBox(height: 8),
            Tooltip(
              message: 'Logout',
              child: _FooterIconButton(
                icon: Icons.logout_rounded,
                onTap: onLogoutTap,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 12 : 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 10 : 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.sidebarEmailText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _FooterActionButton(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: onSettingsTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FooterActionButton(
                  icon: Icons.logout_rounded,
                  label: 'Logout',
                  onTap: onLogoutTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterIconButton extends StatelessWidget {
  const _FooterIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        hoverColor: AppColors.sidebarActive,
        splashColor: AppColors.sidebarDivider,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: AppColors.sidebarText),
        ),
      ),
    );
  }
}

class _FooterActionButton extends StatelessWidget {
  const _FooterActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: AppColors.sidebarActive,
        splashColor: AppColors.sidebarDivider,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppColors.sidebarText),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.sidebarStandaloneText,
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
