// 파일명: check_health_recommendation_control_test.dart
// 역할: 프론트 건강 관리 추천 control의 요청 범위와 응답 변환을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_health_recommendation_control.dart';

// 함수이름: main
// 함수역할:
// - 환자별 건강 추천 조회와 언어별 대체 안내 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 건강 추천 요청이 환자와 언어 범위를 전달하고 식사·운동·주의 정보를 해석하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'requestHealthRecommendation scopes request and decodes recommendation',
    () async {
      // Function Name: MockClient callback
      // Description:
      // - Assert patient-a and English request scope without legacy role/user parameters, then provide
      //   recommendations.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 with diet, exercise, caution, and medication-name data.
      final client = MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/health/recommendation');
        expect(request.url.queryParameters['patient_hash'], 'patient-a');
        expect(request.url.queryParameters.containsKey('role'), isFalse);
        expect(request.url.queryParameters.containsKey('user_hash'), isFalse);
        expect(request.url.queryParameters['language'], 'en');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'diet_recommendation': '위 자극을 줄이는 식사를 권장합니다.',
              'exercise_recommendation': '가벼운 산책을 권장합니다.',
              'caution_items': ['이상 증상이 있으면 의료진과 상담하세요.'],
              'medication_names': ['test-tablet'],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final control = CheckHealthRecommendation(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      );

      final recommendation = await control.requestHealthRecommendation(
        language: 'en',
      );

      expect(recommendation.dietRecommendation, '위 자극을 줄이는 식사를 권장합니다.');
      expect(recommendation.exerciseRecommendation, '가벼운 산책을 권장합니다.');
      expect(recommendation.cautionItems, ['이상 증상이 있으면 의료진과 상담하세요.']);
      expect(recommendation.medicationNames, ['test-tablet']);
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 선택한 다른 환자의 식별자로 건강 추천을 조회하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'requestHealthRecommendation supports a selected patient scope',
    () async {
      // Function Name: MockClient callback
      // Description:
      // - Assert that the selected patient-b scope and Korean language reach the recommendation endpoint.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 with fixed recommendation content.
      final client = MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/health/recommendation');
        expect(request.url.queryParameters['patient_hash'], 'patient-b');
        expect(request.url.queryParameters.containsKey('user_hash'), isFalse);
        expect(request.url.queryParameters.containsKey('role'), isFalse);
        expect(request.url.queryParameters['language'], 'ko');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'diet_recommendation': '식사',
              'exercise_recommendation': '운동',
              'caution_items': ['주의'],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final control = CheckHealthRecommendation(
        baseUrl: 'http://localhost',
        patientHash: 'patient-b',
        client: client,
      );

      final recommendation = await control.requestHealthRecommendation();

      expect(recommendation.dietRecommendation, '식사');
      expect(recommendation.exerciseRecommendation, '운동');
      expect(recommendation.cautionItems, ['주의']);
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 빈 건강 추천 응답에 영어 대체 문구를 사용하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'requestHealthRecommendation localizes empty English fallbacks',
    () async {
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 추천 본문과 주의 항목이 비어 있는 성공 응답으로 언어별 대체 안내를 유도한다.
      // 매개변수:
      // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청. 이 대역에서는 직접 사용하지 않는다.
      // 반환값:
      // - 빈 추천 필드를 가진 HTTP 200 응답.
      final client = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'diet_recommendation': '',
              'exercise_recommendation': '',
              'caution_items': <String>[],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final control = CheckHealthRecommendation(
        baseUrl: 'http://localhost',
        patientHash: 'patient-c',
        client: client,
      );

      final recommendation = await control.requestHealthRecommendation(
        language: 'en',
      );

      expect(
        recommendation.dietRecommendation,
        'Diet recommendation is unavailable.',
      );
      expect(
        recommendation.exerciseRecommendation,
        'Exercise recommendation is unavailable.',
      );
    },
  );
}
