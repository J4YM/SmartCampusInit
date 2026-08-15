import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'header_popover_card.dart';

/// "Dark Mode" settings dropdown anchored below a header's gear icon via
/// [showHeaderPopover]. Shared by every module so it stays visually
/// identical everywhere it appears.
class SettingsPopover extends StatelessWidget {
  const SettingsPopover({super.key, required this.themeModeController});

  final ValueNotifier<ThemeMode> themeModeController;

  @override
  Widget build(BuildContext context) {
    return HeaderPopoverCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PopoverHeaderBar(title: 'Settings'),
          const Divider(height: 1, color: popoverDividerColor),
          Padding(
            padding: const EdgeInsets.all(18),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModeController,
              builder: (context, themeMode, _) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Dark Mode',
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 12 : 14,
                          fontWeight: FontWeight.w500,
                          color: context.isDarkMode
                              ? const Color(0xFFF1F5F9)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    Switch(
                      value: themeMode == ThemeMode.dark,
                      onChanged: (isDark) {
                        themeModeController.value =
                            isDark ? ThemeMode.dark : ThemeMode.light;
                      },
                      activeColor: Colors.white,
                      activeTrackColor: const Color(0xFF15253F),
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
