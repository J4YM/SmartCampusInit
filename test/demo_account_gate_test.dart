import 'dart:convert';

import 'package:capstone_dashboard/auth/app_role.dart';
import 'package:capstone_dashboard/auth/app_user.dart';
import 'package:capstone_dashboard/auth/demo_account_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _registrar = AppUser(
  id: 'u_registrar',
  displayName: 'Registrar Staff',
  role: AppRole.registrar,
  username: 'registrar.demo',
);

/// A client whose `profiles` lookup answers with [rows] (or fails when
/// [status] isn't 200). [requested] collects the request URLs.
SupabaseClient _client(
  List<Map<String, dynamic>> rows, {
  int status = 200,
  List<Uri>? requested,
}) {
  return SupabaseClient(
    'https://example.supabase.co',
    'anon-key',
    httpClient: MockClient((request) async {
      requested?.add(request.url);
      // `request:` is required: postgrest reads response.request when parsing.
      return http.Response(
        jsonEncode(status == 200 ? rows : {'message': 'boom'}),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

void main() {
  test('a demo account whose seeded profile is switched off is deactivated',
      () async {
    final requested = <Uri>[];
    final client = _client([
      {'is_active': false},
    ], requested: requested);

    expect(await isDemoAccountDeactivated(_registrar, client: client), isTrue);
    // Looked up by the registrar's seeded profile id.
    expect(
      requested.single.toString(),
      contains('00000000-0000-4000-8000-000000000003'),
    );
  });

  test('an active profile, or no profile row, is not deactivated', () async {
    expect(
      await isDemoAccountDeactivated(
        _registrar,
        client: _client([
          {'is_active': true},
        ]),
      ),
      isFalse,
    );
    expect(
      await isDemoAccountDeactivated(_registrar, client: _client([])),
      isFalse,
    );
  });

  test('fails open when the lookup errors', () async {
    expect(
      await isDemoAccountDeactivated(
        _registrar,
        client: _client([], status: 500),
      ),
      isFalse,
    );
  });

  test('the demo admin and accounts with no seeded profile are never gated',
      () async {
    final requested = <Uri>[];
    final client = _client([
      {'is_active': false},
    ], requested: requested);
    const admin = AppUser(
      id: 'u_admin',
      displayName: 'Administrator',
      role: AppRole.administrator,
      username: 'admin',
    );
    const student = AppUser(
      id: 'u_student',
      displayName: 'Demo Student',
      role: AppRole.student,
      username: 'student.demo',
    );

    expect(await isDemoAccountDeactivated(admin, client: client), isFalse);
    expect(await isDemoAccountDeactivated(student, client: client), isFalse);
    expect(requested, isEmpty);
  });
}
