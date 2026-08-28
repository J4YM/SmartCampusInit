import 'package:flutter/material.dart';

/// The school's logo mark, shown in every dashboard's main header (and
/// Admin's sidebar) in place of the old "STI" text-in-a-box / gradient-dot
/// placeholders. Always rendered with a 5px rounded corner.
class SchoolLogo extends StatelessWidget {
  const SchoolLogo({super.key, this.width = 60, this.height = 40});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Image.asset(
        'assets/images/sti_logo.png',
        package: 'dashboard_layout',
        width: width,
        height: height,
        fit: BoxFit.cover,
      ),
    );
  }
}
