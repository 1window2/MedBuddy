// File Name: link_patient_caregiver_control_test.dart
// Role: Regression coverage for patient-caregiver link scope, invitation codes, aliases, and lifecycle
//   models.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/entities/patient_hash_entity.dart';

// 함수이름: main
// 함수역할:
// - 환자·보호자 연결 범위, 초대 코드, 별칭과 연결 모델 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // Function Name: test callback
  // Description:
  // - Expected behavior: requestLinkScreen scopes link lookup by user hash.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('requestLinkScreen scopes link lookup by user hash', () async {
    // Function Name: MockClient callback
    // Description:
    // - Assert user-scoped link lookup and provide one active patient-caregiver relationship.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 containing the active link fixture.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 환자 식별자를 코드 발급 요청에 전달하고 받은 초대 코드를 반환하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('generatePatientHash sends patient hash and returns code', () async {
    late Map<String, dynamic> requestBody;
    // Function Name: MockClient callback
    // Description:
    // - Capture patient-code issuance parameters and return a code with an expiry time.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 containing ABCD1234 and its expiry.
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
    expect(patientCode.isExpired(DateTime.utc(2026, 6, 17, 0, 15)), isTrue);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - UML에 정의된 환자 코드 발급 메서드가 동일한 요청 계약을 유지하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'generatePatientHash preserves the diagram-level control name',
    () async {
      // Function Name: MockClient callback
      // Description:
      // - Assert the UML-compatible code-generation route and provide a second invitation code.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 containing WXYZ5678 and its expiry.
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
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 환자 연동 요청에 보호자 식별자와 환자 초대 코드를 함께 전달하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'requestPatientCaregiverLink sends caregiver hash and patient code',
    () async {
      late Map<String, dynamic> requestBody;
      // Function Name: MockClient callback
      // Description:
      // - Capture the caregiver and patient-code registration payload and acknowledge an active link.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 containing newly registered link 7.
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
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestUnlink scopes unlink request by user hash.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('requestUnlink scopes unlink request by user hash', () async {
    // Function Name: MockClient callback
    // Description:
    // - Assert user-scoped unlink routing and return the relationship marked inactive.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 containing link 7 with linked=false.
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

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestUnlink preserves the diagram-level control name.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('requestUnlink preserves the diagram-level control name', () async {
    // Function Name: MockClient callback
    // Description:
    // - Assert user-scoped unlink routing and return the relationship marked inactive.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 containing link 7 with linked=false.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 보호자 소유 연결의 환자 별칭을 갱신하고 서버 결과를 반영하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('savePatientAlias updates the caregiver-owned link alias', () async {
    late Map<String, dynamic> requestBody;
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 사용자 범위의 연결 별칭 PATCH를 검사하고 변경한 별칭을 활성 연결에 반영한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 지정 환자 별칭이 포함된 HTTP 200 응답.
    final client = MockClient((http.Request request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/link/7/patient-alias');
      expect(request.url.queryParameters['user_hash'], 'caregiver-a');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'id': 7,
            'patient_hash': 'patient-a',
            'caregiver_hash': 'caregiver-a',
            'patient_alias': '어머니',
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

    final link = await control.savePatientAlias(linkId: 7, patientAlias: '어머니');

    expect(requestBody['patient_alias'], '어머니');
    expect(link.patientAlias, '어머니');
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: PatientCaregiverLink는 미설정 별칭과 명시적 삭제를 구분한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('PatientCaregiverLink는 미설정 별칭과 명시적 삭제를 구분한다', () {
    final unsetAlias = PatientCaregiverLink.fromJson(const {
      'id': 1,
      'patient_hash': 'patient-a',
      'caregiver_hash': 'caregiver-a',
      'patient_alias': null,
      'linked': true,
    });
    final clearedAlias = PatientCaregiverLink.fromJson(const {
      'id': 1,
      'patient_hash': 'patient-a',
      'caregiver_hash': 'caregiver-a',
      'patient_alias': '',
      'linked': true,
    });

    expect(unsetAlias.patientAlias, isNull);
    expect(clearedAlias.patientAlias, '');
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 빈 로컬 환자 식별자가 기본 환자 범위로 정규화되는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('PatientHash normalizes an empty local patient scope', () {
    expect(
      PatientHash.normalizePatientHash(' '),
      PatientHash.defaultPatientHash,
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: PatientCaregiverLink preserves diagram lifecycle methods.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
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
