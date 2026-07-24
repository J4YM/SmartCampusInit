import 'package:flutter/material.dart';

import '../../modules/system_module_id.dart';

/// Stub screen for modules not yet implemented. Keeps navigation consistent.
class ModulePlaceholderPage extends StatelessWidget {
  const ModulePlaceholderPage({
    super.key,
    required this.moduleId,
    this.bulletPoints = const [],
    this.onSignOut,
  });

  final SystemModuleId moduleId;
  final List<String> bulletPoints;

  /// Set when this page is a role's direct-login destination (no hub to
  /// fall back on); renders a "Sign out" action in the app bar.
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(moduleId.title),
        actions: onSignOut == null
            ? null
            : [
                TextButton(
                  onPressed: onSignOut,
                  child: const Text('Sign out'),
                ),
              ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            moduleId.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'This area is scaffolded for the capstone scope. '
            'Business logic, Supabase queries, and exports will plug in here.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF4B5563),
                ),
          ),
          if (bulletPoints.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Planned capabilities',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            ...bulletPoints.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(line)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
