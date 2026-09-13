// File Name: check_caregiver_medication_control.dart
// Role: Retrieves medication lists and monitoring snapshots for a caregiver's linked patients.
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/caregiver_monitoring_snapshot_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';

// Function Name: CaregiverMedicationInfo
// Description: Bundles a caregiver and patient scope with saved medication details and today's schedule list as one read-only response record.
// Parameters:
// - None.
// Returns:
// - A record containing caregiverHash, patientHash, savedMedications, and todayMedicationScheduleList.
typedef CaregiverMedicationInfo = ({
  String caregiverHash,
  String patientHash,
  List<MedicationDetail> savedMedications,
  List<MedicationSchedule> todayMedicationScheduleList,
});

// 클래스명: CheckCaregiverMedication
// 역할: 연동된 환자의 복약 정보를 보호자 범위에서 읽기 전용으로 조회한다.
// 주요 책임:
// - 보호자 해시로 조회 범위를 지정하고 저장 약·오늘 일정·통합 감시 응답을 모델로 변환한다.
// 속성:
// - baseUrl (String): 복약 API 기본 주소
// - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
// - _client (http.Client): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
class CheckCaregiverMedication {
  final String baseUrl;
  final String caregiverHash;
  final http.Client _client;
  final bool _ownsClient;

  // Function Name: CheckCaregiverMedication
  // Description: Binds caregiver-scoped medication queries to the configured backend and an injected or owned authenticated HTTP client.
  // Parameters:
  // - baseUrl (String): Base URL of the medication API.
  // - caregiverHash (String): Caregiver hash defining the lookup or persistence scope.
  // - client (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // Returns:
  // - CheckCaregiverMedication: the initialized instance.
  CheckCaregiverMedication({
    this.baseUrl = ApiConfig.baseUrl,
    this.caregiverHash = PatientHash.defaultPatientHash,
    http.Client? client,
  }) : _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // 함수이름: requestMonitoringSnapshot
  // 함수역할: 보호자가 관리하는 모든 환자의 알림 설정과 오늘 일정을 한 번에 조회한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 환자별 통합 알림 감시 자료
  Future<List<CaregiverMonitoringSnapshot>> requestMonitoringSnapshot() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/caregiver/monitoring').replace(
              queryParameters: {
                'caregiver_hash': PatientHash.normalizePatientHash(
                  caregiverHash,
                ),
              },
            ),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);
      if (response.statusCode != 200) {
        throw StateError(
          'Caregiver monitoring lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final responseMap = ApiResponseParser.decodeMap(responseBody);
      final rawData = responseMap['data'];
      final rawPatients = rawData is Map ? rawData['patients'] : null;
      if (rawPatients is! List) {
        throw StateError(
          'Server response did not include caregiver monitoring data.',
        );
      }
      return rawPatients
          .whereType<Map>()
          .map(
            // 함수이름: map 콜백
            // 함수역할: 보호자 모니터링 응답 항목의 키를 문자열로 맞춰 환자별 스냅샷으로 변환한다.
            // 매개변수:
            // - item (Map): 현재 변환·검사 중인 응답 또는 목록 항목
            // 반환값:
            // - 환자 연결·설정·일정을 담은 모니터링 스냅샷.
            (item) => CaregiverMonitoringSnapshot.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        '보호자 통합 알림 자료 요청에 실패했습니다.',
        name: 'CheckCaregiverMedication',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Caregiver monitoring lookup failed.');
    }
  }

  // Function Name: requestPatientMedicationInfo
  // Description: Requests the medication information of an explicitly selected linked patient.
  // Parameters:
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // Returns:
  // - Future<CaregiverMedicationInfo>: Requests the medication information of an explicitly selected linked patient.
  Future<CaregiverMedicationInfo> requestPatientMedicationInfo({
    required String patientHash,
  }) async {
    try {
      final normalizedPatientHash = PatientHash.normalizePatientHash(
        patientHash,
      );
      final response = await _client
          .get(
            Uri.parse(
              '$baseUrl/caregiver/medications/'
              '${Uri.encodeComponent(normalizedPatientHash)}',
            ).replace(
              queryParameters: {
                'caregiver_hash': PatientHash.normalizePatientHash(
                  caregiverHash,
                ),
              },
            ),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);
      if (response.statusCode != 200) {
        throw StateError(
          'Caregiver medication lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final responseMap = ApiResponseParser.decodeMap(responseBody);
      final rawData = responseMap['data'];
      if (rawData is! Map) {
        throw StateError('Server response did not include medication data.');
      }
      final data = Map<String, dynamic>.from(rawData);
      final todayMedicationInfo = data['today_medication_info'];
      final rawTodaySchedules = todayMedicationInfo is Map
          ? todayMedicationInfo['schedules']
          : todayMedicationInfo;
      return (
        caregiverHash: _readString(
          data['caregiver_hash'] ?? data['guardian_hash'],
        ),
        patientHash: _readString(data['patient_hash']),
        savedMedications: _readSavedMedications(data['saved_medications']),
        todayMedicationScheduleList: MedicationSchedule.fromScheduleJsonList(
          rawTodaySchedules,
        ),
      );
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Caregiver medication request failed.',
        name: 'CheckCaregiverMedication',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Caregiver medication lookup failed.');
    }
  }

  // Function Name: _readSavedMedications
  // Description: Decodes map entries into saved medication details, treating a nonlist payload as an empty collection.
  // Parameters:
  // - rawItems (dynamic): Raw server item or list before model conversion.
  // Returns:
  // - List<MedicationDetail>: Decodes map entries into saved medication details, treating a nonlist payload as an empty collection.
  static List<MedicationDetail> _readSavedMedications(dynamic rawItems) {
    if (rawItems is! List) {
      return const [];
    }
    return rawItems
        .whereType<Map>()
        .map(
          // Function Name: map callback
          // Description: Parses one medication response object into the shared medication-detail model.
          // Parameters:
          // - item (Map): Current response or collection entry being transformed or checked.
          // Returns:
          // - The parsed medication details.
          (item) => MedicationDetail.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  // Function Name: _readString
  // Description: Converts a nullable API field into trimmed text, using an empty string for null.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // Returns:
  // - String: trimmed field text, or an empty string for null.
  static String _readString(dynamic value) {
    return value?.toString().trim() ?? '';
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
