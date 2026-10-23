import 'package:capstone_dashboard/data/parent_portal_repository.dart';
import 'package:capstone_dashboard/data/student_portal_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

const _form = {'last_name': 'Cruz', 'first_name': 'Ana', 'section': 'BSIT 3-A'};

void main() {
  late RecordingServer server;
  late SupabaseClient client;

  setUp(() async {
    server = RecordingServer();
    await server.start();
    client = SupabaseClient(server.url, 'anon-key');
  });

  tearDown(() async {
    await client.dispose();
    await server.stop();
  });

  for (final who in ['student', 'parent']) {
    group('$who portal', () {
      test('submit stores the slip field by field next to the remarks', () async {
        if (who == 'student') {
          await StudentPortalRepository(client).submitGoodMoralRequest(
            studentId: 's1',
            documentType: 'Certificate of Good Moral',
            purpose: 'Employment',
            requestedBy: 'Ana Cruz',
            remarks: 'Name: Cruz, Ana',
            formData: _form,
          );
        } else {
          await ParentPortalRepository(client).submitGoodMoralRequest(
            studentId: 's1',
            documentType: 'Certificate of Good Moral',
            purpose: 'Employment',
            requestedBy: 'Parent',
            remarks: 'Name: Cruz, Ana',
            formData: _form,
          );
        }
        final body = server.requests
            .lastWhere((r) =>
                r.method == 'POST' &&
                r.path.endsWith('/rest/v1/good_moral_requests'))
            .json;
        expect(body['form_data'], _form);
        expect(body['remarks'], 'Name: Cruz, Ana');
      });

      test('the list carries the officer\'s note and the submitted slip',
          () async {
        server.respond = (r) => r.path.endsWith('/rest/v1/good_moral_requests')
            ? (200, [
                {
                  'id': 'r1',
                  'document_type': 'Certificate of Good Moral',
                  'purpose': 'Employment',
                  'status': 'Returned',
                  'request_date': '2026-10-01T00:00:00Z',
                  'flag_note': 'Section does not match.',
                  'form_data': _form,
                }
              ])
            : null;
        final dynamic list = who == 'student'
            ? await StudentPortalRepository(client).fetchMyGoodMoralRequests('s1')
            : await ParentPortalRepository(client).fetchMyGoodMoralRequests('s1');

        expect(list.single.isReturned, isTrue);
        expect(list.single.flagNote, 'Section does not match.');
        expect(list.single.formData, _form);
      });

      test('resubmit calls the RPC with the new slip', () async {
        if (who == 'student') {
          await StudentPortalRepository(client).resubmitGoodMoralRequest(
              requestId: 'r1',
              purpose: 'Employment',
              remarks: 'Name: Cruz, Ana',
              formData: _form);
        } else {
          await ParentPortalRepository(client).resubmitGoodMoralRequest(
              requestId: 'r1',
              purpose: 'Employment',
              remarks: 'Name: Cruz, Ana',
              formData: _form);
        }
        expect(server.requestTo('/rpc/resubmit_good_moral_request').json, {
          'p_request_id': 'r1',
          'p_purpose': 'Employment',
          'p_remarks': 'Name: Cruz, Ana',
          'p_form_data': _form,
        });
      });
    });
  }

  test('the student\'s record fills the slip', () async {
    server.respond = (r) => r.path.endsWith('/rest/v1/students')
        ? (200, {
            'student_number': '2024-0001',
            'enrollment_year': 2024,
            'sections': {'name': 'BSIT 3-A'},
            'profiles': {
              'first_name': 'Ana',
              'last_name': 'Cruz',
              'phone_number': '0917 123 4567',
            },
          })
        : null;

    final form = await StudentPortalRepository(client).fetchGoodMoralPrefill('s1');

    expect(form!.lastName, 'Cruz');
    expect(form.firstName, 'Ana');
    expect(form.studentNumber, '2024-0001');
    expect(form.section, 'BSIT 3-A');
    expect(form.contactNumber, '0917 123 4567');
    expect(form.ayStarted, '2024');
    expect(form.schoolStatus, 'Enrolled');
    expect(form.address, isEmpty, reason: 'the school has no address on record');
  });

  test('no record means no prefill', () async {
    final form = await StudentPortalRepository(client).fetchGoodMoralPrefill('s1');
    expect(form, isNull);
  });
}
