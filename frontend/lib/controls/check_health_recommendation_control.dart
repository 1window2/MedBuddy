// 파일명: check_health_recommendation_control.dart
// 역할: 건강 관리 추천의 서버 조회, 언어별 캐시와 오류 처리를 수행한다.

import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/health_recommendation_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';



// 클래스명: CheckHealthRecommendation
// 역할: 현재 복용 약 조합 기반 건강 관리 추천을 서버에서 조회한다.
// 주요 책임:
// - 환자 해시와 역할 정보를 포함해 건강 관리 추천 API를 호출한다.
// - 서버 응답을 HealthRecommendation 모델로 변환한다.
// 속성:
// - baseUrl (String): 복약 API 기본 주소
// - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
// - _client (http.Client): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
class CheckHealthRecommendation {
  final String baseUrl;
  final String patientHash;
  final http.Client _client;
  final bool _ownsClient;

  // Function Name: CheckHealthRecommendation
  // Description: Normalizes the patient hash and binds recommendation queries to an injected or owned authenticated HTTP client.
  // Parameters:
  // - baseUrl (String): Base URL of the medication API.
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - client (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // Returns:
  // - CheckHealthRecommendation: the initialized instance.
  CheckHealthRecommendation({
    this.baseUrl = ApiConfig.baseUrl,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? client,
  }) : patientHash = PatientHash.normalizePatientHash(patientHash),
       _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // 함수이름: requestHealthRecommendation
  // 함수역할: 현재 복용 중인 약 조합을 바탕으로 건강 관리 추천을 요청한다.
  // 매개변수:
  // - language (String): 추천 문장 생성에 사용할 언어 코드
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
          language: language,
        );
      }
      throw StateError(
        'Server response did not include health recommendation.',
      );
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

  // Function Name: _buildHealthUri
  // Description: Builds the health endpoint URI with the normalized patient scope and requested recommendation language.
  // Parameters:
  // - path (String): Relative path appended to the configured API resource.
  // - language (String): Language code used for display or speech guidance.
  // Returns:
  // - Uri: Builds the health endpoint URI with the normalized patient scope and requested recommendation language.
  Uri _buildHealthUri(String path, String language) {
    return Uri.parse('$baseUrl/$path').replace(
      queryParameters: {'patient_hash': patientHash, 'language': language},
    );
  }

  // 함수이름: dispose
  // 함수역할: 직접 생성한 HTTP 클라이언트만 닫고 외부에서 주입한 클라이언트의 수명은 호출자에게 맡긴다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
