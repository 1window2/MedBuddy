import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/health_recommendation_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';

// 파일명: check_health_recommendation_control.dart
// 역할: 건강 관리 추천 API 호출을 담당한다.

// 클래스명: CheckHealthRecommendation
// 역할: 현재 복용 약 조합 기반 건강 관리 추천을 서버에서 조회한다.
// 주요 책임:
// - 환자 해시와 역할 정보를 포함해 건강 관리 추천 API를 호출한다.
// - 서버 응답을 HealthRecommendation 모델로 변환한다.
class CheckHealthRecommendation {
  final String baseUrl;
  final String patientHash;
  final http.Client _client;
  final bool _ownsClient;

  CheckHealthRecommendation({
    this.baseUrl = ApiConfig.baseUrl,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? client,
  })  : patientHash = PatientHash.normalizePatientHash(patientHash),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  // 함수명: requestHealthRecommendation
  // 함수역할:
  // - 현재 복용 중인 약 조합을 바탕으로 건강 관리 추천을 요청한다.
  // 매개변수:
  // - language: 추천 문장 생성에 사용할 언어 코드
  // 반환값:
  // - HealthRecommendation 인스턴스
  Future<HealthRecommendation> requestHealthRecommendation({
    String language = 'ko',
  }) async {
    try {
      final response = await _client
          .get(_buildHealthUri('health/recommendation', language))
          .timeout(const Duration(seconds: 45));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Health recommendation failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = ApiResponseParser.decodeMap(responseBody);
      final rawRecommendation = decodedData['data'];
      if (rawRecommendation is Map) {
        return HealthRecommendation.fromJson(
          Map<String, dynamic>.from(rawRecommendation),
        );
      }
      throw StateError(
          'Server response did not include health recommendation.');
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Health recommendation request failed.',
        name: 'CheckHealthRecommendation',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Health recommendation failed.');
    }
  }

  Uri _buildHealthUri(String path, String language) {
    return Uri.parse('$baseUrl/$path').replace(
      queryParameters: {
        'patient_hash': patientHash,
        'language': language,
      },
    );
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
