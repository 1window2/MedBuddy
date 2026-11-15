import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/services/api_response_parser.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';

Map<String, dynamic> _data(String state) => {
  'patient_hash': 'patient-a',
  'patient_code': 'ABCD1234',
  'expires_at': '2100-01-01T00:00:00Z',
  'status': state,
  'link': state == 'linked'
      ? {
          'id': 7,
          'patient_hash': 'patient-a',
          'caregiver_hash': 'caregiver-a',
          'linked': true,
        }
      : null,
};

class _AbortClient extends http.BaseClient {
  bool aborted = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final response = Completer<http.StreamedResponse>();
    (request as http.Abortable).abortTrigger!.then((_) {
      aborted = true;
      response.completeError(http.RequestAbortedException(request.url));
    });
    return response.future;
  }
}

void main() {
  for (final state in PatientLinkCodeState.values) {
    test('authenticated exact-code status decodes ${state.name}', () async {
      final transport = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/link/code/status');
        expect(request.url.queryParameters, {
          'patient_code': 'ABCD1234',
          'user_hash': 'patient-a',
        });
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode({'success': true, 'data': _data(state.name)}),
          200,
        );
      });
      final client = AuthenticatedApiClient(
        inner: transport,
        trustedBaseUri: Uri.parse('http://localhost'),
        tokenProvider: () async => 'test-token',
        appCheckRequired: false,
      );
      final control = LinkPatientCaregiver(
        baseUrl: 'http://localhost',
        userHash: 'patient-a',
        client: client,
      );
      final result = await control.requestPatientCodeStatus(' abcd1234 ');
      expect(result.state, state);
      expect(
        result.link?.linkId,
        state == PatientLinkCodeState.linked ? 7 : null,
      );
      client.close();
    });
  }

  for (final change in [
    'code',
    'owner',
    'link-owner',
    'missing-link',
    'inactive-link',
    'unknown-state',
  ]) {
    test('rejects untrusted status: $change', () async {
      final data = _data('linked');
      switch (change) {
        case 'code':
          data['patient_code'] = 'OTHER123';
        case 'owner':
          data['patient_hash'] = 'patient-b';
        case 'link-owner':
          (data['link'] as Map)['patient_hash'] = 'patient-b';
        case 'missing-link':
          data['link'] = null;
        case 'inactive-link':
          (data['link'] as Map)['linked'] = false;
        case 'unknown-state':
          data['status'] = 'used';
      }
      final control = LinkPatientCaregiver(
        baseUrl: 'http://localhost',
        userHash: 'patient-a',
        client: MockClient(
          (_) async => http.Response(jsonEncode({'data': data}), 200),
        ),
      );
      await expectLater(
        control.requestPatientCodeStatus('ABCD1234'),
        throwsA(anything),
      );
    });
  }

  for (final status in [401, 403, 404, 429, 500]) {
    test('HTTP $status never becomes code success', () async {
      final control = LinkPatientCaregiver(
        userHash: 'patient-a',
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'data': _data('linked')}), status),
        ),
      );
      await expectLater(
        control.requestPatientCodeStatus('ABCD1234'),
        throwsA(isA<ApiRequestException>()),
      );
    });
  }

  testWidgets('status timeout aborts the underlying request', (tester) async {
    final client = _AbortClient();
    final control = LinkPatientCaregiver(userHash: 'patient-a', client: client);
    final assertion = expectLater(
      control.requestPatientCodeStatus('ABCD1234'),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 15));
    await assertion;
    expect(client.aborted, isTrue);
  });

  test('caller cancellation aborts status transport', () async {
    final client = _AbortClient();
    final control = LinkPatientCaregiver(userHash: 'patient-a', client: client);
    final abort = Completer<void>();
    final assertion = expectLater(
      control.requestPatientCodeStatus('ABCD1234', abortTrigger: abort.future),
      throwsA(isA<http.RequestAbortedException>()),
    );
    abort.complete();
    await assertion;
    expect(client.aborted, isTrue);
  });
}
