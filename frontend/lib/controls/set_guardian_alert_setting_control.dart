import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/guardian_alert_setting_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';

// 파일명: set_guardian_alert_setting_control.dart
// 역할: 보호자 알림 설정 API 호출을 담당한다.

// 클래스명: SetGuardianAlertSetting
// 역할: 보호자 알림 설정 조회/변경 요청을 백엔드 control과 연결한다.
// 주요 책임:
// - 보호자-환자 쌍의 알림 설정을 조회한다.
// - 보호자가 선택한 알림 수신 여부를 저장한다.
class SetGuardianAlertSetting {
  final String baseUrl;
  final String guardianHash;
  final http.Client _client;
  final bool _ownsClient;

  SetGuardianAlertSetting({
    this.baseUrl = ApiConfig.baseUrl,
    this.guardianHash = PatientHash.defaultPatientHash,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  SetGuardianAlertSetting forGuardian(String guardianHash) {
    return SetGuardianAlertSetting(
      baseUrl: baseUrl,
      guardianHash: PatientHash.normalizePatientHash(guardianHash),
      client: _client,
    );
  }

  // 함수명: requestGuardianAlertSetting
  // 함수역할:
  // - 보호자-환자 쌍의 알림 설정을 조회한다.
  // 매개변수:
  // - patientHash: 보호자가 모니터링하는 환자 해시
  // 반환값:
  // - GuardianAlertSetting
  Future<GuardianAlertSetting> requestGuardianAlertSetting({
    required String patientHash,
  }) async {
    try {
      final response = await _client
          .get(_buildGuardianAlertUri(patientHash))
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Guardian alert setting lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      return _decodeSetting(responseBody);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Guardian alert setting lookup failed.',
        name: 'SetGuardianAlertSetting',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Guardian alert setting lookup failed.');
    }
  }

  // 함수명: updateGuardianAlertSetting
  // 함수역할:
  // - 보호자 알림 수신 여부를 저장한다.
  // 매개변수:
  // - patientHash: 보호자가 모니터링하는 환자 해시
  // - enabled: 알림 수신 활성 여부
  // 반환값:
  // - 저장된 GuardianAlertSetting
  Future<GuardianAlertSetting> updateGuardianAlertSetting({
    required String patientHash,
    required bool enabled,
  }) async {
    try {
      final response = await _client
          .put(
            _buildGuardianAlertUri(patientHash),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'is_enabled': enabled,
              'alert_option': enabled ? 'enable' : 'disable',
            }),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Guardian alert setting save failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      return _decodeSetting(responseBody);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Guardian alert setting save failed.',
        name: 'SetGuardianAlertSetting',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Guardian alert setting save failed.');
    }
  }

  Future<GuardianAlertSetting> enableGuardianAlert({
    required String patientHash,
  }) {
    return updateGuardianAlertSetting(patientHash: patientHash, enabled: true);
  }

  Future<GuardianAlertSetting> disableGuardianAlert({
    required String patientHash,
  }) {
    return updateGuardianAlertSetting(patientHash: patientHash, enabled: false);
  }

  GuardianAlertSetting _decodeSetting(String responseBody) {
    final decodedData = ApiResponseParser.decodeMap(responseBody);
    final rawSetting = decodedData['data'];
    if (rawSetting is Map) {
      return GuardianAlertSetting.fromJson(
        Map<String, dynamic>.from(rawSetting),
      );
    }
    throw StateError('Server response did not include guardian alert setting.');
  }

  Uri _buildGuardianAlertUri(String patientHash) {
    return Uri.parse(
      '$baseUrl/guardian-alert/settings/'
      '${Uri.encodeComponent(PatientHash.normalizePatientHash(patientHash))}',
    ).replace(
      queryParameters: {
        'guardian_hash': PatientHash.normalizePatientHash(guardianHash),
      },
    );
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
