import 'package:flutter/material.dart';

/// The school's logo mark, shown in every dashboard's main header (and
/// Admin's sidebar) in place of the old "STI" text-in-a-box / gradient-dot
/// placeholders. Always rendered with a 5px rounded corner.
///
/// Pass [onTap] to make it act as a "home" link — every dashboard wires this
/// to reset that dashboard back to its own default tab/route (and dismiss
/// any "View all notifications/email" override), the same way clicking a
/// site's logo returns to its homepage. Left null (the default) renders a
/// plain, non-interactive image — e.g. nowhere a "home" destination makes
/// sense to define.
class SchoolLogo extends StatelessWidget {
  const SchoolLogo({super.key, this.width = 40, this.height = 40, this.onTap});

  final double width;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Image.asset(
        'assets/images/STI_Baliuag_Logo.png',
        package: 'dashboard_layout',
        width: width,
        height: height,
        fit: BoxFit.contain,
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return image;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: image,
    );
  }
}
