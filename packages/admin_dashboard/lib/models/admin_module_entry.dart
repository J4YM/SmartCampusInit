import 'package:flutter/widgets.dart';

/// One role's dashboard, offered to the Admin from the sidebar's
/// "Role Modules" section. The host app supplies these (this package has no
/// knowledge of the other modules) and the shell opens [builder]'s page
/// full-screen with a "back to Admin" bar above it.
///
/// Entries sharing a [group] are listed together under one collapsible
/// heading, in the order the groups first appear.
class AdminModuleEntry {
  const AdminModuleEntry({
    required this.id,
    required this.group,
    required this.label,
    required this.icon,
    required this.builder,
  });

  final String id;
  final String group;
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}
