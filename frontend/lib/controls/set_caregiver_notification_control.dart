import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/caregiver_notification_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';

// 파일명: set_caregiver_notification_control.dart
// 역할: 보호자 알림 설정 API 호출을 담당한다.

// 클래스명: SetCaregiverNotification
// 역할: 보호자 알림 설정 조회/변경 요청을 백엔드 control과 연결한다.
// 주요 책임:
// - 보호자-환자 쌍의 알림 설정을 조회한다.
// - 보호자가 선택한 알림 수신 여부를 저장한다.
class SetCaregiverNotification {
  final String baseUrl;
  final String caregiverHash;
  final http.Client _client;
  final bool _ownsClient;

  SetCaregiverNotification({
    this.baseUrl = ApiConfig.baseUrl,
    this.caregiverHash = PatientHash.defaultPatientHash,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  // 함수명: requestCaregiverNotificationSetting
  // 함수역할:
  // - 보호자-환자 쌍의 알림 설정을 조회한다.
  // 매개변수:
  // - patientHash: 보호자가 모니터링하는 환자 해시
  // 반환값:
  // - CaregiverNotification
  Future<CaregiverNotification> requestCaregiverNotificationSetting({
    required String patientHash,
  }) async {
    try {
      final response = await _client
          .get(_buildCaregiverNotificationUri(patientHash))
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Caregiver notification lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      return _decodeSetting(responseBody);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Caregiver notification lookup failed.',
        name: 'SetCaregiverNotification',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Caregiver notification lookup failed.');
    }
  }

  // 함수명: saveCaregiverNotificationSetting
  // 함수역할:
  // - 보호자 알림 수신 여부를 저장한다.
  // 매개변수:
  // - patientHash: 보호자가 모니터링하는 환자 해시
  // - enabled: 알림 수신 활성 여부
  // 반환값:
  // - 저장된 CaregiverNotification
  Future<CaregiverNotification> saveCaregiverNotificationSetting({
    required String patientHash,
    required bool enabled,
  }) async {
    try {
      final response = await _client
          .put(
            _buildCaregiverNotificationUri(patientHash),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'notification_enabled': enabled,
              'notification_type': enabled ? 'enable' : 'disable',
            }),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Caregiver notification save failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      return _decodeSetting(responseBody);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Caregiver notification save failed.',
        name: 'SetCaregiverNotification',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Caregiver notification save failed.');
    }
  }

  CaregiverNotification _decodeSetting(String responseBody) {
    final decodedData = ApiResponseParser.decodeMap(responseBody);
    final rawSetting = decodedData['data'];
    if (rawSetting is Map) {
      return CaregiverNotification.fromJson(
        Map<String, dynamic>.from(rawSetting),
      );
    }
    throw StateError('Server response did not include caregiver notification.');
  }

  Uri _buildCaregiverNotificationUri(String patientHash) {
    return Uri.parse(
      '$baseUrl/caregiver-notification/settings/'
      '${Uri.encodeComponent(PatientHash.normalizePatientHash(patientHash))}',
    ).replace(
      queryParameters: {
        'caregiver_hash': PatientHash.normalizePatientHash(caregiverHash),
      },
    );
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
