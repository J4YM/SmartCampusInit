import 'package:capstone_dashboard/auth/staff_password_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

Map<String, dynamic> _session(String email) => {
      'access_token': 'aaa.bbb.ccc',
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'refresh',
      'user': {
        'id': '11111111-1111-4111-8111-111111111111',
        'aud': 'authenticated',
        'email': email,
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-10-21T00:00:00Z',
      },
    };

const _invalid = (
  400,
  {
    'error': 'invalid_grant',
    'error_code': 'invalid_credentials',
    'msg': 'Invalid login credentials',
    'error_description': 'Invalid login credentials',
  }
);

// Plain tests only: this talks to a real local socket.
void main() {
  late RecordingServer server;
  late SupabaseClient client;

  setUp(() async {
    server = RecordingServer();
    await server.start();
    client = SupabaseClient(
      server.url,
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDown(() async {
    await client.dispose();
    await server.stop();
  });

  Future<void> signedInAs(String email, String password) async {
    server.respond = (r) => (200, _session(email));
    await client.auth.signInWithPassword(email: email, password: password);
    server.requests.clear();
  }

  group('signInStaffWithPassword', () {
    test('a correct email and password signs in', () async {
      server.respond = (r) => (200, _session('demo.discipline@baliuag.sti.edu.ph'));
      final result = await signInStaffWithPassword(
          client, 'Demo.Discipline@baliuag.sti.edu.ph ', 'Right#Pass2026!');
      expect(result, StaffSignInResult.signedIn);
      final req = server.requestTo('/token');
      expect(req.uri.queryParameters['grant_type'], 'password');
      expect(req.json['email'], 'demo.discipline@baliuag.sti.edu.ph');
      expect(req.json['password'], 'Right#Pass2026!');
    });

    test('a wrong password is reported as invalid, not as an error', () async {
      server.respond = (r) => _invalid;
      expect(await signInStaffWithPassword(client, 'x@y.z', 'wrong'),
          StaffSignInResult.invalidCredentials);
    });

    test('an unreachable server is "unavailable", so the caller can fall back',
        () async {
      await server.stop();
      expect(await signInStaffWithPassword(client, 'x@y.z', 'pw'),
          StaffSignInResult.unavailable);
      server = RecordingServer();
      await server.start(); // so tearDown can stop it
    });
  });

  group('changeOwnPassword', () {
    const email = 'demo.discipline@baliuag.sti.edu.ph';
    const old = 'Old#Password2026!';
    const fresh = 'Brand#New2026Pass!';

    test('verifies the current password, then sets the new one', () async {
      await signedInAs(email, old);
      server.respond = (r) => r.method == 'PUT'
          ? (200, (_session(email)['user']))
          : (200, _session(email));

      final error =
          await changeOwnPassword(client, currentPassword: old, newPassword: fresh);

      expect(error, isNull);
      final reauth = server.requestTo('/token');
      expect(reauth.json['password'], old);
      final update = server.requests.lastWhere((r) => r.method == 'PUT');
      expect(update.path, endsWith('/user'));
      expect(update.json['password'], fresh);
    });

    test('a wrong current password stops before anything is changed', () async {
      await signedInAs(email, old);
      server.respond = (r) => _invalid;

      final error = await changeOwnPassword(client,
          currentPassword: 'not-it', newPassword: fresh);

      expect(error, 'Your current password is incorrect.');
      expect(server.requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    test('a weak new password is refused without contacting the server',
        () async {
      await signedInAs(email, old);
      final error = await changeOwnPassword(client,
          currentPassword: old, newPassword: 'weakpass');
      expect(error, 'Use at least 12 characters');
      expect(server.requests, isEmpty);
    });

    test('reusing the current password is refused', () async {
      await signedInAs(email, old);
      final error = await changeOwnPassword(client,
          currentPassword: old, newPassword: old);
      expect(error, 'Choose a password different from the current one');
      expect(server.requests, isEmpty);
    });

    test('the server\'s own refusal is shown', () async {
      await signedInAs(email, old);
      server.respond = (r) => r.method == 'PUT'
          ? (422, {
              'code': 422,
              'error_code': 'weak_password',
              'msg': 'Password is known to be weak and easy to guess.'
            })
          : (200, _session(email));
      final error = await changeOwnPassword(client,
          currentPassword: old, newPassword: fresh);
      expect(error, contains('weak'));
    });

    test('a Microsoft account has no password to change here', () async {
      server.respond = (r) {
        final s = _session(email);
        (s['user'] as Map<String, dynamic>)['app_metadata'] = {'provider': 'azure'};
        return (200, s);
      };
      await client.auth.signInWithPassword(email: email, password: old);
      server.requests.clear();

      final error = await changeOwnPassword(client,
          currentPassword: old, newPassword: fresh);

      expect(error, contains('Microsoft'));
      expect(server.requests, isEmpty);
    });

    test('with nobody signed in there is nothing to change', () async {
      final error = await changeOwnPassword(client,
          currentPassword: old, newPassword: fresh);
      expect(error, contains('Sign in'));
      expect(server.requests, isEmpty);
    });
  });
}
