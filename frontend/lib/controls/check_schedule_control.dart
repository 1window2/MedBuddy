import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';

// File Name: check_schedule_control.dart
// Role: Loads patient medication schedules and persists individual or whole-slot completion changes.

// 클래스명: CheckSchedule
// 역할: 환자별 복약 일정과 기간 일정을 조회하고 복용 완료 상태를 저장한다.
// 주요 책임: 환자 소유권을 요청에 포함하고 응답 모델과 오프라인 기간을 검증한다.
// 속성: baseUrl/patientHash: API와 환자 범위; _client/_ownsClient: HTTP 연결과 해제 책임; _windowRequests: 일수별로 진행 중인 기간 일정 요청.
class CheckSchedule {
  final String baseUrl;
  final String patientHash;
  final http.Client _client;
  final bool _ownsClient;
  final Map<int, Future<Map<String, dynamic>>> _windowRequests = {};

  // Function Name: CheckSchedule
  // Description: Normalizes patient ownership and binds schedule reads and completion updates to an injected or owned authenticated client.
  // Parameters:
  // - baseUrl (String): Base URL of the medication API.
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - client (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // Returns:
  // - CheckSchedule: the initialized instance.
  CheckSchedule({
    this.baseUrl = ApiConfig.baseUrl,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? client,
  }) : patientHash = PatientHash.normalizePatientHash(patientHash),
       _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // Function Name: requestTodayMedicationSchedule
  // Description: Requests today's medication schedule scoped to this patient hash.
  // Parameters:
  // - None.
  // Returns:
  // - Today's medication schedule list; invalid or unsuccessful envelopes raise StateError.
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return ApiResponseParser.guardRequest(
      operation: 'Schedule lookup failed',
      logName: 'CheckSchedule',
      logMessage: 'Today medication schedule request failed.',
      request: () async {
        final response = await _client
            .get(_buildScheduleUri('schedule/today'))
            .timeout(const Duration(seconds: 30));
        final responseBody = ApiResponseParser.requireOkBody(
          'Schedule lookup failed',
          response,
        );

        final decodedData = ApiResponseParser.decodeMap(responseBody);
        if (decodedData['success'] != true || decodedData['data'] is! List) {
          throw StateError('Schedule response could not be verified.');
        }
        return MedicationSchedule.fromScheduleJsonList(decodedData['data']);
      },
    );
  }

  // 함수이름: requestMedicationScheduleWindow
  // 함수역할: 오늘부터 지정 기간과 겹치는 복약 과정을 알림 예약용으로 조회한다.
  // 매개변수: days: 오늘을 포함한 조회 일수, 1~14이며 기본 14.
  // 반환값: 복약 일정 목록 Future; 범위 밖 days는 ArgumentError, 응답 검증 실패는 오류로 전달한다.
  Future<List<MedicationSchedule>> requestMedicationScheduleWindow({
    int days = 14,
  }) => _requestScheduleWindow(days: days);

  // 함수이름: requestOfflineScheduleWindow
  // 함수역할: 오프라인 보관용 14일 일정을 조회하면서 서버가 명시한 시작일과 종료일을 검증한다.
  // 매개변수: expectedStartDay: 기대하는 시작 날짜 문자열.
  // 반환값: 기간이 일치하는 일정 목록; 기기 시각으로 유효기간을 임의 연장하지 않고 불일치 시 실패한다.
  Future<List<MedicationSchedule>> requestOfflineScheduleWindow({
    required String expectedStartDay,
  }) => _requestScheduleWindow(days: 14, expectedStartDay: expectedStartDay);

  // 함수이름: _sharedScheduleWindow
  // 함수역할: 같은 일수의 기간 일정 요청이 진행 중이면 그 응답을 함께 쓴다. 기록 동기화와 알림 동기화가 일정 갱신 직후 같은 14일 일정을 동시에 읽으므로 요청을 한 번만 보낸다. 끝난 응답은 보관하지 않는다.
  // 매개변수: days: 1~14일.
  // 반환값: 성공 응답의 JSON 맵 Future. 호출자는 읽기만 한다. 통신·응답 오류는 공유한 모든 호출자에게 전파한다.
  Future<Map<String, dynamic>> _sharedScheduleWindow(int days) {
    final pending = _windowRequests[days];
    if (pending != null) return pending;
    final request = () async {
      final response = await _client
          .get(_buildScheduleUri('schedule/window', {'days': '$days'}))
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.requireOkBody(
        'Schedule window lookup failed',
        response,
      );
      final decodedData = ApiResponseParser.decodeMap(responseBody);
      if (decodedData['success'] != true || decodedData['data'] is! List) {
        throw StateError('Schedule window response could not be verified.');
      }
      return decodedData;
    }();
    _windowRequests[days] = request;
    request.whenComplete(() {
      if (identical(_windowRequests[days], request)) _windowRequests.remove(days);
    }).ignore();
    return request;
  }

  // 함수이름: _requestScheduleWindow
  // 함수역할: 환자별 기간 일정을 30초 제한으로 읽고 선택적으로 정확한 조회 기간까지 검증한다.
  // 매개변수: days: 1~14일; expectedStartDay: 지정 시 서버 기간과 대조할 시작일.
  // 반환값: 검증된 일정 목록 Future; 일수 범위 오류와 통신·응답·기간 오류를 전파한다.
  Future<List<MedicationSchedule>> _requestScheduleWindow({
    required int days,
    String? expectedStartDay,
  }) async {
    if (days < 1 || days > 14) {
      throw ArgumentError.value(days, 'days', 'Must be between 1 and 14.');
    }
    return ApiResponseParser.guardRequest(
      operation: 'Schedule window lookup failed',
      logName: 'CheckSchedule',
      logMessage: 'Medication schedule window request failed.',
      request: () async {
        final decodedData = await _sharedScheduleWindow(days);
        if (expectedStartDay != null) {
          final start = DateTime.parse(expectedStartDay);
          final end = DateTime(
            start.year,
            start.month,
            start.day + days - 1,
          ).toIso8601String().substring(0, 10);
          if (decodedData['window_start'] != expectedStartDay ||
              decodedData['window_end'] != end) {
            throw StateError(
              'The medication schedule window has expired. Please refresh.',
            );
          }
        }
        return MedicationSchedule.fromScheduleJsonList(decodedData['data']);
      },
    );
  }

  // 함수이름: updateMedicationStatus
  // 함수역할: 약 한 건의 복용 상태를 저장하고 서버가 확정한 일정 모델을 읽는다.
  // 매개변수: medicationId: 저장 약 ID; medicationStatus: 새 완료 여부; slotKey: 선택적 복용 구간, 공백 제거·소문자 변환 후 전송.
  // 반환값: 갱신 일정 Future; 응답에 일정이 없거나 요청이 실패하면 오류를 전파한다.
  Future<MedicationSchedule> updateMedicationStatus(
    String medicationId,
    bool medicationStatus, {
    String? slotKey,
  }) async {
    return ApiResponseParser.guardRequest(
      operation: 'Status update failed',
      logName: 'CheckSchedule',
      logMessage: 'Medication status update failed.',
      request: () async {
        final response = await _client
            .patch(
              _buildScheduleUri('schedule/$medicationId/status'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'medication_status': medicationStatus,
                if (slotKey != null && slotKey.trim().isNotEmpty)
                  'slot_key': slotKey.trim().toLowerCase(),
              }),
            )
            .timeout(const Duration(seconds: 30));
        final responseBody = ApiResponseParser.requireOkBody(
          'Status update failed',
          response,
        );

        final decodedData = ApiResponseParser.decodeMap(responseBody);
        final rawSchedule = decodedData['data'];
        if (rawSchedule is Map) {
          return MedicationSchedule.fromScheduleJson(
            Map<String, dynamic>.from(rawSchedule),
          );
        }
        throw StateError(
          'Server response did not include an updated schedule.',
        );
      },
    );
  }

  // Function Name: updateMedicationSlotStatus
  // Description: Atomically applies one completion state to every medication in a time slot through the backend bulk-update endpoint.
  // Parameters:
  // - slotKey (String): Morning, lunch, evening, or bedtime schedule key.
  // - medicationStatus (bool): Completion state applied to the whole slot.
  // - expectedScheduleDate (String?): ISO dose day to guard delayed actions.
  // Returns:
  // - Updated schedules returned by the backend.
  Future<List<MedicationSchedule>> updateMedicationSlotStatus(
    String slotKey,
    bool medicationStatus, {
    String? expectedScheduleDate,
  }) async {
    final normalizedSlotKey = slotKey.trim().toLowerCase();
    if (!medicationScheduleSlotKeys.contains(normalizedSlotKey)) {
      throw ArgumentError.value(slotKey, 'slotKey', 'Unsupported slot key.');
    }
    try {
      final response = await _client
          .patch(
            _buildScheduleUri('schedule/slot/$normalizedSlotKey/status'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'medication_status': medicationStatus,
              'expected_schedule_date': ?expectedScheduleDate,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.requireOkBody(
        'Slot status update failed',
        response,
      );
      final decodedData = ApiResponseParser.decodeMap(responseBody);
      return MedicationSchedule.fromScheduleJsonList(decodedData['data']);
    } on ArgumentError {
      rethrow;
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Medication slot status update failed.',
        name: 'CheckSchedule',
        error: error,
        stackTrace: stackTrace,
      );
      throw ApiResponseParser.transportFailure(
        'Slot status update failed',
        error,
      );
    }
  }

  // Function Name: _buildScheduleUri
  // Description: Builds a schedule endpoint URI with patient ownership and optional window query parameters.
  // Parameters:
  // - path (String): Relative path appended to the configured API resource.
  // - additionalQueryParameters (Map<String, String>): Additional HTTP query fields beyond the ownership scope.
  // Returns:
  // - Uri: Builds a schedule endpoint URI with patient ownership and optional window query parameters.
  Uri _buildScheduleUri(
    String path, [
    Map<String, String> additionalQueryParameters = const {},
  ]) {
    return Uri.parse('$baseUrl/$path').replace(
      queryParameters: {
        'patient_hash': patientHash,
        ...additionalQueryParameters,
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
