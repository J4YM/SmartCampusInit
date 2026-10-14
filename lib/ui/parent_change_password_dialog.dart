import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/parent_credential_repository.dart';

/// Blocking "choose your own password" step for a guardian signed in with the
/// temporary password the registrar handed over at enrollment (see
/// supabase/add_parent_credentials.sql). Not dismissible: the only ways out
/// are a successful change or signing out.
class ParentChangePasswordDialog extends StatefulWidget {
  const ParentChangePasswordDialog({
    super.key,
    required this.repository,
    required this.parentId,
    this.onSignOut,
  });

  final ParentCredentialRepository repository;
  final String parentId;
  final VoidCallback? onSignOut;

  @override
  State<ParentChangePasswordDialog> createState() =>
      _ParentChangePasswordDialogState();
}

class _ParentChangePasswordDialogState
    extends State<ParentChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _current.text;
    final next = _next.text;
    if (current.isEmpty) {
      setState(() => _error = 'Enter the temporary password you were given.');
      return;
    }
    if (next.length < 8) {
      setState(() => _error = 'The new password must be at least 8 characters.');
      return;
    }
    if (next != _confirm.text) {
      setState(() => _error = 'The new passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ok = await widget.repository.changePassword(
        parentId: widget.parentId,
        oldPassword: current,
        newPassword: next,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _saving = false;
          _error = 'The temporary password is incorrect.';
        });
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not change the password: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Choose a new password'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You signed in with a temporary password. Set your own '
                  'password to continue.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _current,
                  obscureText: true,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Temporary password',
                  ),
                ),
                TextField(
                  controller: _next,
                  obscureText: true,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'New password (8+ characters)',
                  ),
                ),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    Navigator.of(context).pop(false);
                    widget.onSignOut?.call();
                  },
            child: const Text('Sign out'),
          ),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save password'),
          ),
        ],
      ),
    );
  }
}
