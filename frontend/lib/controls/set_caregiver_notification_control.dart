import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/caregiver_notification_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';

// File Name: set_caregiver_notification_control.dart
// Role: Loads and saves caregiver notification conditions and deadlines per linked patient and schedule slot.

// 클래스명: SetCaregiverNotification
// 역할: 보호자 알림 설정 조회/변경 요청을 백엔드 control과 연결한다.
// 주요 책임:
// - 보호자-환자 쌍의 시간대별 알림 설정을 조회한다.
// - 보호자가 선택한 시간대의 알림 설정만 저장한다.
// 속성:
// - baseUrl (String): 복약 API 기본 주소
// - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
// - _client (http.Client): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
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

  // 함수이름: requestCaregiverNotificationSetting
  // 함수역할: 보호자-환자 쌍의 알림 설정을 조회한다.
  // 매개변수:
  // - patientHash (String): 보호자가 모니터링하는 환자 해시
  // - slotKey (String): 조회할 복약 시간대
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

  // 함수이름: requestCaregiverNotificationSettings
  // 함수역할: 한 환자의 모든 복약 시간대 알림 설정을 한 번에 조회한다.
  // 매개변수:
  // - patientHash (String): 보호자가 모니터링하는 환자 해시
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

  // 함수이름: saveCaregiverNotificationSetting
  // 함수역할: 보호자 알림 수신 여부를 저장한다.
  // 매개변수:
  // - patientHash (String): 보호자가 모니터링하는 환자 해시
  // - slotKey (String): 저장할 복약 시간대
  // - mode (CaregiverNotificationMode): 알림 수신 조건
  // - deadlineHour (int?): 미복약 판정 마감의 24시간제 시
  // - deadlineMinute (int?): 미복약 판정 마감의 분
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
