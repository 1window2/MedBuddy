import 'dart:convert';

import 'package:http/http.dart' as http;

import '../entities/caregiver_notification_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';

// File Name: set_caregiver_notification_control.dart
// Role: Loads and saves caregiver notification conditions and deadlines per linked patient and schedule slot.

// Class Name: SetCaregiverNotification
// Role: Load and save caregiver alert conditions for linked patients.
// Responsibilities: Scope requests by caregiver and update individual medication slots.
// Attributes: baseUrl/caregiverHash (String): API and owner scope; _client (http.Client): transport; _ownsClient (bool): cleanup ownership.
class SetCaregiverNotification {
  final String baseUrl;
  final String caregiverHash;
  final http.Client _client;
  final bool _ownsClient;

  // Function Name: SetCaregiverNotification
  // Description: Binds patient-slot notification settings to the current caregiver hash and an injected or owned authenticated client.
  // Parameters:
  // - baseUrl (String): Base URL of the medication API.
  // - caregiverHash (String): Caregiver hash defining the lookup or persistence scope.
  // - client (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // Returns:
  // - SetCaregiverNotification: the initialized instance.
  SetCaregiverNotification({
    this.baseUrl = ApiConfig.baseUrl,
    this.caregiverHash = PatientHash.defaultPatientHash,
    http.Client? client,
  }) : _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // Function Name: requestCaregiverNotificationSettings
  // Description: Fetch all medication-slot alert settings for a patient; request and decoding failures propagate through the guard.
  // Parameters: patientHash (String): monitored patient.
  // Returns: Future<Map<String, CaregiverNotification>>: settings keyed by slot.
  Future<Map<String, CaregiverNotification>>
  requestCaregiverNotificationSettings({required String patientHash}) async {
    return ApiResponseParser.guardRequest(
      operation: 'Caregiver notification lookup failed',
      logName: 'SetCaregiverNotification',
      logMessage: 'Caregiver notification lookup failed.',
      request: () async {
        final response = await _client
            .get(_buildCaregiverNotificationSlotsUri(patientHash))
            .timeout(const Duration(seconds: 30));
        final responseBody = ApiResponseParser.requireOkBody(
          'Caregiver notification lookup failed',
          response,
        );

        return _decodeSettings(responseBody);
      },
    );
  }

  // Function Name: saveCaregiverNotificationSetting
  // Description: Persist the alert mode and optional missed-dose deadline for one patient slot.
  // Parameters: patientHash (String): patient; slotKey (String): slot, default morning; mode (CaregiverNotificationMode): alert condition; deadlineHour/deadlineMinute (int?): deadline components.
  // Returns: Future<CaregiverNotification>: saved server setting; request/decoding failures propagate.
  Future<CaregiverNotification> saveCaregiverNotificationSetting({
    required String patientHash,
    String slotKey = 'morning',
    required CaregiverNotificationMode mode,
    int? deadlineHour,
    int? deadlineMinute,
  }) async {
    return ApiResponseParser.guardRequest(
      operation: 'Caregiver notification save failed',
      logName: 'SetCaregiverNotification',
      logMessage: 'Caregiver notification save failed.',
      request: () async {
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
        final responseBody = ApiResponseParser.requireOkBody(
          'Caregiver notification save failed',
          response,
        );

        return _decodeSetting(responseBody);
      },
    );
  }

  // Function Name: _decodeSetting
  // Description: Requires a single caregiver-notification data map and decodes it, rejecting a missing setting payload.
  // Parameters:
  // - responseBody (String): Server response body decoded as UTF-8.
  // Returns:
  // - CaregiverNotification: Requires a single caregiver-notification data map and decodes it, rejecting a missing setting payload.
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

  // 함수이름: _decodeSettings
  // 함수역할: 시간대 설정 배열의 Map 항목만 모델로 변환하고 시간대 키로 조회 가능한 사전을 만든다.
  // 매개변수:
  // - responseBody (String): UTF-8로 읽은 서버 응답 본문
  // 반환값:
  // - Map<String, CaregiverNotification>: 시간대 설정 배열의 Map 항목만 모델로 변환하고 시간대 키로 조회 가능한 사전을 만든다.
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

  // 함수이름: _buildCaregiverNotificationUri
  // 함수역할: 정규화한 환자 해시를 경로에 인코딩하고 보호자 해시와 시간대 키로 단일 설정 조회 범위를 지정한다.
  // 매개변수:
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - Uri: 정규화한 환자 해시를 경로에 인코딩하고 보호자 해시와 시간대 키로 단일 설정 조회 범위를 지정한다.
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

  // 함수이름: _buildCaregiverNotificationSlotsUri
  // 함수역할: 정규화한 환자·보호자 해시로 해당 연동의 모든 시간대 설정 조회 URI를 만든다.
  // 매개변수:
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // 반환값:
  // - Uri: 정규화한 환자·보호자 해시로 해당 연동의 모든 시간대 설정 조회 URI를 만든다.
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

  // Function Name: dispose
  // Description: Closes the HTTP client only when this control created it; injected clients remain owned by the caller.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
