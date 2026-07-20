// 파일명: check_health_recommendation_control_test.dart
// 역할: 프론트 건강 관리 추천 control의 요청 범위와 응답 변환을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_health_recommendation_control.dart';

void main() {
  test('requestHealthRecommendation scopes request and decodes recommendation',
      () async {
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
  });

  test('requestHealthRecommendation supports a selected patient scope',
      () async {
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
  });
}
