// File Name: check_today_medication_info_control_test.dart
// Role: Regression coverage for today-medication summary response decoding.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_today_medication_info_control.dart';
import 'package:medbuddy_frontend/services/api_response_parser.dart';

// 함수이름: main
// 함수역할:
// - 오늘 복약 요약 응답 해석 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 오늘 복약 요약 응답에서 환자 범위의 일정 목록과 완료 정보를 해석하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'requestTodayMedicationInfo decodes schedules from summary payload',
    () async {
      // Function Name: MockClient callback
      // Description:
      // - Assert the patient-scoped summary request and provide counts together with per-slot schedules.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 with one completed dose out of three.
      final client = MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/schedule/today/info');
        expect(request.url.queryParameters['patient_hash'], 'patient-a');
        expect(request.url.queryParameters.containsKey('role'), isFalse);
        expect(request.url.queryParameters.containsKey('user_hash'), isFalse);
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'patient_hash': 'patient-a',
              'medication_count': 1,
              'total_dose_count': 3,
              'completed_dose_count': 1,
              'remaining_dose_count': 2,
              'progress_ratio': 1 / 3,
              'schedules': [
                {
                  'medication_id': '7',
                  'drug_name': 'test-tablet',
                  'daily_frequency': '3 times',
                  'slot_statuses': {
                    'morning': true,
                    'lunch': false,
                    'evening': false,
                  },
                  'patient_hash': 'patient-a',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final control = CheckTodayMedicationInfo(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      );

      final schedules = await control.requestTodayMedicationInfo();

      expect(schedules, hasLength(1));
      expect(schedules.first.patientID, 'patient-a');
      expect(schedules.first.medicationID, '7');
      expect(schedules.first.isSlotCompleted('morning'), isTrue);
    },
  );

  // 함수이름: 실패 분류 테스트
  // 함수역할: 거부 응답은 상태 코드와 서버 안내를 기존 문구 그대로 전달하고, 응답을 받지 못한 실패는
  //   원래 예외를 보존해 호출자가 연결·지연 안내를 고를 수 있게 하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('summary failures keep the status code or the transport cause', () async {
    CheckTodayMedicationInfo control(MockClient client) =>
        CheckTodayMedicationInfo(
          baseUrl: 'http://localhost',
          patientHash: 'patient-a',
          client: client,
        );

    await expectLater(
      control(
        MockClient(
          (_) async => http.Response(
            '{"detail":"Service unavailable"}',
            503,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ).requestTodayMedicationInfo(),
      throwsA(
        isA<ApiRequestException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having(
              (e) => e.message,
              'message',
              'Today medication info lookup failed (503): Service unavailable',
            ),
      ),
    );
    await expectLater(
      control(
        MockClient((_) async => throw http.ClientException('offline')),
      ).requestTodayMedicationInfo(),
      throwsA(
        isA<ApiRequestException>()
            .having((e) => e.cause, 'cause', isA<http.ClientException>())
            .having(
              (e) => e.message,
              'message',
              'Today medication info lookup failed.',
            ),
      ),
    );
  });
}
