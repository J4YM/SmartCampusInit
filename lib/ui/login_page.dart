import 'package:flutter/material.dart';

import '../../app/session_controller.dart';
import '../../auth/static_demo_accounts.dart';

/// Username/password gate with static credentials and simple lockout.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});

  final SessionController session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final session = widget.session;
    session.refreshLockoutState();
    if (session.isLockedOut) {
      final remaining = session.lockoutRemaining ?? Duration.zero;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Too many attempts. Try again in ${remaining.inSeconds.clamp(1, 999)}s.',
          ),
        ),
      );
      return;
    }

    final user = StaticDemoAccounts.trySignIn(
      _userController.text,
      _passwordController.text,
    );
    if (user != null) {
      session.signIn(user);
      return;
    }

    final locked = session.registerFailedAttempt(
      maxAttempts: StaticDemoAccounts.maxAttemptsBeforeLockout,
      lockout: StaticDemoAccounts.lockoutDuration,
    );
    if (locked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Three failed attempts. This demo locks briefly; production will log to Supabase audit.',
          ),
        ),
      );
    } else {
      final remaining =
          StaticDemoAccounts.maxAttemptsBeforeLockout - session.failedAttempts;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remaining > 0
                ? 'Invalid credentials. Attempts remaining before lockout: $remaining.'
                : 'Invalid credentials.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'STI College Baliuag',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Integrated attendance & discipline platform',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6B7280),
                        ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _userController,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListenableBuilder(
                    listenable: widget.session,
                    builder: (context, _) {
                      final locked = widget.session.isLockedOut;
                      return FilledButton(
                        onPressed: locked ? null : _submit,
                        child: Text(locked ? 'Locked — wait' : 'Sign in'),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    StaticDemoAccounts.demoAccountHelpText(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF9CA3AF),
                          height: 1.35,
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
