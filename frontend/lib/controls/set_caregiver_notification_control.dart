import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/caregiver_notification_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';

// 파일명: set_caregiver_notification_control.dart
// 역할: 보호자 알림 설정 API 호출을 담당한다.

// 클래스명: SetCaregiverNotification
// 역할: 보호자 알림 설정 조회/변경 요청을 백엔드 control과 연결한다.
// 주요 책임:
// - 보호자-환자 쌍의 시간대별 알림 설정을 조회한다.
// - 보호자가 선택한 시간대의 알림 설정만 저장한다.
class SetCaregiverNotification {
  final String baseUrl;
  final String caregiverHash;
  final http.Client _client;
  final bool _ownsClient;

  SetCaregiverNotification({
    this.baseUrl = ApiConfig.baseUrl,
    this.caregiverHash = PatientHash.defaultPatientHash,
    http.Client? client,
  }) : _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // 함수명: requestCaregiverNotificationSetting
  // 함수역할:
  // - 보호자-환자 쌍의 알림 설정을 조회한다.
  // 매개변수:
  // - patientHash: 보호자가 모니터링하는 환자 해시
  // - slotKey: 조회할 복약 시간대
  // 반환값:
  // - CaregiverNotification
  Future<CaregiverNotification> requestCaregiverNotificationSetting({
    required String patientHash,
    String slotKey = 'morning',
  }) async {
    try {
      final response = await _client
          .get(_buildCaregiverNotificationUri(patientHash, slotKey: slotKey))
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

  // 함수명: requestCaregiverNotificationSettings
  // 함수역할:
  // - 한 환자의 모든 복약 시간대 알림 설정을 한 번에 조회한다.
  // 매개변수:
  // - patientHash: 보호자가 모니터링하는 환자 해시
  // 반환값:
  // - 시간대 키로 조회할 수 있는 CaregiverNotification map
  Future<Map<String, CaregiverNotification>>
  requestCaregiverNotificationSettings({required String patientHash}) async {
    try {
      final response = await _client
          .get(_buildCaregiverNotificationSlotsUri(patientHash))
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Caregiver notification lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      return _decodeSettings(responseBody);
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
  // - slotKey: 저장할 복약 시간대
  // - mode: 알림 수신 조건
  // 반환값:
  // - 저장된 CaregiverNotification
  Future<CaregiverNotification> saveCaregiverNotificationSetting({
    required String patientHash,
    String slotKey = 'morning',
    required CaregiverNotificationMode mode,
    int? deadlineHour,
    int? deadlineMinute,
  }) async {
    try {
      final response = await _client
          .put(
            _buildCaregiverNotificationUri(patientHash, slotKey: slotKey),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'notification_enabled':
                  mode != CaregiverNotificationMode.disabled,
              'notification_type': mode.wireValue,
              'deadline_hour': deadlineHour,
              'deadline_minute': deadlineMinute,
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

  Map<String, CaregiverNotification> _decodeSettings(String responseBody) {
    final decodedData = ApiResponseParser.decodeMap(responseBody);
    final rawSettings = decodedData['data'];
    if (rawSettings is! List) {
      throw StateError(
        'Server response did not include caregiver notifications.',
      );
    }
    final settings = <String, CaregiverNotification>{};
    for (final rawSetting in rawSettings) {
      if (rawSetting is! Map) {
        continue;
      }
      final setting = CaregiverNotification.fromJson(
        Map<String, dynamic>.from(rawSetting),
      );
      settings[setting.slotKey] = setting;
    }
    return settings;
  }

  Uri _buildCaregiverNotificationUri(
    String patientHash, {
    required String slotKey,
  }) {
    return Uri.parse(
      '$baseUrl/caregiver-notification/settings/'
      '${Uri.encodeComponent(PatientHash.normalizePatientHash(patientHash))}',
    ).replace(
      queryParameters: {
        'caregiver_hash': PatientHash.normalizePatientHash(caregiverHash),
        'slot_key': slotKey,
      },
    );
  }

  Uri _buildCaregiverNotificationSlotsUri(String patientHash) {
    return Uri.parse(
      '$baseUrl/caregiver-notification/settings/'
      '${Uri.encodeComponent(PatientHash.normalizePatientHash(patientHash))}'
      '/slots',
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
