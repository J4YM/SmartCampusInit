import 'package:flutter/material.dart';

import '../app/session_controller.dart';

/// Shown after a staff-pattern Microsoft sign-in when `profiles.status` is
/// `pending` — the account exists but an admin still needs to approve it
/// and assign a specific role (see `handle_new_auth_user` in
/// supabase/add_oauth_role_approval_schema.sql).
class AwaitingApprovalPage extends StatefulWidget {
  const AwaitingApprovalPage({super.key, required this.session});

  final SessionController session;

  @override
  State<AwaitingApprovalPage> createState() => _AwaitingApprovalPageState();
}

class _AwaitingApprovalPageState extends State<AwaitingApprovalPage> {
  bool _checking = false;

  Future<void> _refresh() async {
    setState(() => _checking = true);
    try {
      await widget.session.recheckApprovalStatus();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.session.pendingApprovalEmail;
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  size: 48,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(height: 16),
                Text(
                  'Awaiting admin approval',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  (email == null || email.isEmpty)
                      ? 'Your account has signed in successfully but is '
                          'still pending admin approval.'
                      : 'The account $email has signed in successfully but '
                          'is still pending admin approval.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: const Color(0xFF4B5563)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'An administrator needs to assign your role before you '
                  'can continue. This page updates once that happens.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFF6B7280)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _checking ? null : _refresh,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh status'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.session.signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
