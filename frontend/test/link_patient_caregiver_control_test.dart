// 파일명: link_patient_caregiver_control_test.dart
// 역할: 프론트 환자-보호자 연동 control의 조회, 코드 생성, 등록, 해제 요청을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/entities/patient_hash_entity.dart';

void main() {
  test('requestLinkScreen scopes link lookup by user hash', () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/link/list');
      expect(request.url.queryParameters['user_hash'], 'caregiver-a');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': [
            {
              'id': 3,
              'patient_hash': 'patient-a',
              'caregiver_hash': 'caregiver-a',
              'linked': true,
              'created_at': '2026-06-17T00:00:00',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = LinkPatientCaregiver(
      baseUrl: 'http://localhost',
      userHash: 'caregiver-a',
      client: client,
    );

    final links = await control.requestLinkScreen();

    expect(links, hasLength(1));
    expect(links.first.linkId, 3);
    expect(links.first.patientHash, 'patient-a');
    expect(links.first.caregiverHash, 'caregiver-a');
    expect(links.first.linkStatus, isTrue);
  });

  test('generatePatientHash sends patient hash and returns code', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/link/code');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'patient_hash': 'patient-a',
            'patient_code': 'ABCD1234',
            'expires_at': '2026-06-17T00:15:00+00:00',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = LinkPatientCaregiver(
      baseUrl: 'http://localhost',
      userHash: 'patient-a',
      client: client,
    );

    final patientCode = await control.generatePatientHash();

    expect(requestBody['patient_hash'], 'patient-a');
    expect(patientCode.code, 'ABCD1234');
    expect(patientCode.patientHash, 'patient-a');
    expect(patientCode.expiresAt, DateTime.utc(2026, 6, 17, 0, 15));
    expect(
      patientCode.isExpired(DateTime.utc(2026, 6, 17, 0, 14, 59)),
      isFalse,
    );
    expect(
      patientCode.isExpired(DateTime.utc(2026, 6, 17, 0, 15)),
      isTrue,
    );
  });

  test('generatePatientHash preserves the diagram-level control name',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/link/code');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'patient_hash': 'patient-a',
            'patient_code': 'WXYZ5678',
            'expires_at': '2026-06-17T00:15:00+00:00',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = LinkPatientCaregiver(
      baseUrl: 'http://localhost',
      userHash: 'patient-a',
      client: client,
    );

    final patientCode = await control.generatePatientHash();

    expect(patientCode.code, 'WXYZ5678');
  });

  test('requestPatientCaregiverLink sends caregiver hash and patient code',
      () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/link/register');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'id': 7,
            'patient_hash': 'patient-a',
            'caregiver_hash': 'caregiver-a',
            'linked': true,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = LinkPatientCaregiver(
      baseUrl: 'http://localhost',
      userHash: 'caregiver-a',
      client: client,
    );

    final link = await control.requestPatientCaregiverLink('ABCD1234');

    expect(requestBody['caregiver_hash'], 'caregiver-a');
    expect(requestBody['patient_code'], 'ABCD1234');
    expect(link.linkId, 7);
    expect(link.linkStatus, isTrue);
  });

  test('requestUnlink scopes unlink request by user hash', () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/link/7');
      expect(request.url.queryParameters['user_hash'], 'caregiver-a');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'id': 7,
            'patient_hash': 'patient-a',
            'caregiver_hash': 'caregiver-a',
            'linked': false,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = LinkPatientCaregiver(
      baseUrl: 'http://localhost',
      userHash: 'caregiver-a',
      client: client,
    );

    final link = await control.requestUnlink(7);

    expect(link.linkId, 7);
    expect(link.linkStatus, isFalse);
  });

  test('requestUnlink preserves the diagram-level control name', () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/link/7');
      expect(request.url.queryParameters['user_hash'], 'caregiver-a');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'id': 7,
            'patient_hash': 'patient-a',
            'caregiver_hash': 'caregiver-a',
            'linked': false,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = LinkPatientCaregiver(
      baseUrl: 'http://localhost',
      userHash: 'caregiver-a',
      client: client,
    );

    final link = await control.requestUnlink(7);

    expect(link.linkId, 7);
    expect(link.linkStatus, isFalse);
  });

  test('PatientHash normalizes an empty local patient scope', () {
    expect(
        PatientHash.normalizePatientHash(' '), PatientHash.defaultPatientHash);
  });

  test('PatientCaregiverLink preserves diagram lifecycle methods', () {
    const link = PatientCaregiverLink(
      patientHash: 'patient-a',
      caregiverHash: 'caregiver-a',
    );

    final createdLink = link.savePatientCaregiverLink();
    final deletedLink = createdLink.removePatientCaregiverLink();

    expect(createdLink.linkStatus, isTrue);
    expect(deletedLink.linkStatus, isFalse);
  });
}
