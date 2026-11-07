// File Name: check_caregiver_medication_control.dart
// Role: Retrieves medication lists and monitoring snapshots for a caregiver's linked patients.

import 'package:http/http.dart' as http;

import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/caregiver_monitoring_snapshot_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';
import '../entities/json_value_reader.dart';

// Function Name: CaregiverMedicationInfo
// Description: Bundles a caregiver and patient scope with saved medication details and today's schedule list as one read-only response record.
// Parameters:
// - None.
// Returns:
// - A record containing caregiverHash, patientHash, savedMedications, and todayMedicationScheduleList. savedMedications is kept for the record shape and is always empty.
typedef CaregiverMedicationInfo = ({
  String caregiverHash,
  String patientHash,
  List<MedicationDetail> savedMedications,
  List<MedicationSchedule> todayMedicationScheduleList,
});

// Class Name: CheckCaregiverMedication
// Role: Queries linked-patient medication data within a caregiver account.
// Responsibilities: Decode and validate authorized snapshots, share concurrent schedule reads and retain brief same-day results.
// Attributes: baseUrl/caregiverHash define request scope; _client is injected or owned; schedule fields track in-flight and recent reads.
class CheckCaregiverMedication {
  final String baseUrl;
  final String caregiverHash;
  final http.Client _client;
  final bool _ownsClient;
  Future<List<CaregiverMonitoringSnapshot>>? _scheduleRead;
  List<CaregiverMonitoringSnapshot>? _recentSchedules;
  DateTime? _scheduleReadAt;
  bool _disposed = false;

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

  // 함수이름: requestScheduleSnapshot
  // 함수역할: 알림 설정과 무관한 환자 일정 일괄 조회를 공유하고 요청한 연동 범위로 결과를 제한한다.
  // 매개변수: links: 허용할 연동 목록; null이면 응답의 전체 승인된 연동을 유지한다.
  // 반환값: 연동별 스냅샷 Future; 조회 실패는 빈 목록으로 바꾸지 않고 전파한다.
  Future<List<CaregiverMonitoringSnapshot>> requestScheduleSnapshot({
    List<PatientCaregiverLink>? links,
  }) async {
    final snapshots = await (_scheduleRead ??= _loadScheduleSnapshot()
        .whenComplete(() => _scheduleRead = null));
    if (links == null) return snapshots;
    final allowed = {for (final link in links) (link.linkId, link.patientHash)};
    return snapshots.where((s) => allowed.contains((s.link.linkId, s.patientHash)))
        .toList(growable: false);
  }

  // 함수이름: _loadScheduleSnapshot
  // 함수역할: 기존 최근 결과를 지운 뒤 일정을 읽고 조회 중 날짜가 바뀌지 않은 경우에만 재사용 캐시에 보관한다.
  // 매개변수: 없음.
  // 반환값: 수신한 일정 스냅샷; 종료되거나 자정을 지나도 반환은 하되 캐시하지 않는다.
  Future<List<CaregiverMonitoringSnapshot>> _loadScheduleSnapshot() async {
    final started = DateTime.now();
    _recentSchedules = null;
    _scheduleReadAt = null;
    final snapshots = await _requestSnapshot('schedules');
    if (!_disposed && _sameDay(started, DateTime.now())) {
      _recentSchedules = snapshots;
      _scheduleReadAt = DateTime.now();
    }
    return snapshots;
  }

  // 함수이름: _sameDay
  // 함수역할: 두 시각의 연·월·일 필드가 같은지 확인한다.
  // 매개변수: a, b: 비교할 DateTime; 시간대 변환은 수행하지 않는다.
  // 반환값: 달력 날짜 필드가 모두 같으면 true.
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // 함수이름: requestMonitoringSnapshot
  // 함수역할: 보호자가 관리하는 모든 환자의 알림 설정과 오늘 일정을 한 번에 조회한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 환자별 통합 알림 감시 자료
  Future<List<CaregiverMonitoringSnapshot>> requestMonitoringSnapshot() {
    // 같은 로그인 세션의 홈 조회를 감시에도 재사용한다. 실패·자정에는 다시 읽는다.
    if (_scheduleRead != null) return _scheduleRead!;
    final at = _scheduleReadAt;
    final now = DateTime.now();
    if (!_disposed && at != null && _sameDay(at, now) &&
        now.difference(at) >= Duration.zero &&
        now.difference(at) < const Duration(seconds: 15)) {
      return Future.value(_recentSchedules!);
    }
    return _requestSnapshot('monitoring');
  }

  // Function Name: _requestSnapshot
  // Description: Fetches and decodes a caregiver snapshot with a 30-second timeout and ownership validation.
  // Parameters: resource: Caregiver endpoint suffix, such as schedules.
  // Returns: Authorized snapshots; transport, status, malformed payload and cross-scope responses fail through the request guard.
  Future<List<CaregiverMonitoringSnapshot>> _requestSnapshot(String resource) async {
    return ApiResponseParser.guardRequest(
      operation: 'Caregiver monitoring lookup failed',
      logName: 'CheckCaregiverMedication',
      logMessage: '보호자 통합 알림 자료 요청에 실패했습니다.',
      request: () async {
        final response = await _client
            .get(
              Uri.parse('$baseUrl/caregiver/$resource').replace(
                queryParameters: {
                  'caregiver_hash': PatientHash.normalizePatientHash(
                    caregiverHash,
                  ),
                },
              ),
            )
            .timeout(const Duration(seconds: 30));
        final responseBody = ApiResponseParser.requireOkBody(
          'Caregiver monitoring lookup failed',
          response,
        );

        final responseMap = ApiResponseParser.decodeMap(responseBody);
        final rawData = responseMap['data'];
        final rawPatients = rawData is Map ? rawData['patients'] : null;
        if (rawPatients is! List) {
          throw StateError(
            'Server response did not include caregiver monitoring data.',
          );
        }
        if (resource == 'schedules' && rawData['caregiver_hash'] != caregiverHash) {
          throw StateError('Caregiver schedule response scope mismatch.');
        }
        final snapshots = rawPatients
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
        if (snapshots.any((s) => !s.link.linkStatus ||
            (s.link.linkId ?? 0) <= 0 || s.link.caregiverHash != caregiverHash ||
            s.patientHash.isEmpty || s.patientHash == caregiverHash)) {
          throw StateError('Caregiver schedule response scope mismatch.');
        }
        return snapshots;
      },
    );
  }

  // Function Name: requestPatientMedicationInfo
  // Description: Requests the medication information of an explicitly selected linked patient. Only today's schedules are decoded; the saved medication list in the response is ignored.
  // Parameters:
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // Returns:
  // - Future<CaregiverMedicationInfo>: Requests the medication information of an explicitly selected linked patient.
  Future<CaregiverMedicationInfo> requestPatientMedicationInfo({
    required String patientHash,
  }) async {
    return ApiResponseParser.guardRequest(
      operation: 'Caregiver medication lookup failed',
      logName: 'CheckCaregiverMedication',
      logMessage: 'Caregiver medication request failed.',
      request: () async {
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
        final responseBody = ApiResponseParser.requireOkBody(
          'Caregiver medication lookup failed',
          response,
        );

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
          caregiverHash: readJsonText(
            data['caregiver_hash'] ?? data['guardian_hash'],
          ),
          patientHash: readJsonText(data['patient_hash']),
          // No screen reads the saved medication list, so the response field is not decoded on each poll.
          savedMedications: const <MedicationDetail>[],
          todayMedicationScheduleList: MedicationSchedule.fromScheduleJsonList(
            rawTodaySchedules,
          ),
        );
      },
    );
  }

  // 함수이름: dispose
  // 함수역할: 최근 일정 캐시를 비우고 객체를 종료 상태로 만든 뒤 소유한 HTTP 연결만 닫는다.
  // 매개변수: 없음.
  // 반환값: 없음; 주입 클라이언트는 닫지 않는다.
  void dispose() {
    _disposed = true;
    _recentSchedules = null;
    _scheduleReadAt = null;
    if (_ownsClient) {
      _client.close();
    }
  }
}
