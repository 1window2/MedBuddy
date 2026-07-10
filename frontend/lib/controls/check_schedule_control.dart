import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';

// 파일명: check_schedule_control.dart
// 역할: 오늘의 복약 일정 조회와 복약 완료 상태 변경 API를 담당한다.

// 클래스명: CheckSchedule
// 역할: 저장된 복약 정보를 오늘 기준 일정으로 조회하고 상태 변경을 서버에 반영한다.
// 주요 책임:
// - 환자 해시와 역할 정보를 포함해 일정 API를 호출한다.
// - 서버 응답을 MedicationSchedule 목록으로 변환한다.
// - 복약 완료 여부를 업데이트한다.
class CheckSchedule {
  final String baseUrl;
  final String patientHash;
  final String? userHash;
  final String role;
  final http.Client _client;
  final bool _ownsClient;

  CheckSchedule({
    this.baseUrl = ApiConfig.baseUrl,
    this.patientHash = PatientHash.defaultPatientHash,
    this.userHash,
    this.role = 'patient',
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  CheckSchedule forScope({
    required String patientHash,
    String? userHash,
    String role = 'patient',
  }) {
    return CheckSchedule(
      baseUrl: baseUrl,
      patientHash: PatientHash.normalizePatientHash(patientHash),
      userHash: userHash == null || userHash.trim().isEmpty
          ? null
          : PatientHash.normalizePatientHash(userHash),
      role: role.trim().isEmpty ? 'patient' : role.trim().toLowerCase(),
      client: _client,
    );
  }

  // Function Name: requestMedicationSchedule
  // Description:
  // - Class diagram compatible wrapper for today's medication schedule lookup.
  // Returns:
  // - Today's medication schedule list.
  Future<List<MedicationSchedule>> requestMedicationSchedule() {
    return requestTodayMedicationSchedule();
  }

  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Requests today's medication schedule scoped to this patient hash.
  // Returns:
  // - Today's medication schedule list.
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    try {
      final response = await _client
          .get(_buildScheduleUri('schedule/today'))
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Schedule lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = ApiResponseParser.decodeMap(responseBody);
      return _decodeMedicationScheduleList(decodedData['data']);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Today medication schedule request failed.',
        name: 'CheckSchedule',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Schedule lookup failed.');
    }
  }

  // Function Name: updateMedicationStatus
  // Description:
  // - Persists one medication completion status.
  // Parameters:
  // - medicationId: Saved medication identifier.
  // - medicationStatus: New completion status.
  // Returns:
  // - Updated MedicationSchedule.
  Future<MedicationSchedule> updateMedicationStatus(
    String medicationId,
    bool medicationStatus, {
    String? slotKey,
  }) async {
    try {
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
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Status update failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = ApiResponseParser.decodeMap(responseBody);
      final rawSchedule = decodedData['data'];
      if (rawSchedule is Map) {
        return MedicationSchedule.fromScheduleJson(
          Map<String, dynamic>.from(rawSchedule),
        );
      }
      throw StateError('Server response did not include an updated schedule.');
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Medication status update failed.',
        name: 'CheckSchedule',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Status update failed.');
    }
  }

  List<MedicationSchedule> _decodeMedicationScheduleList(dynamic rawItems) {
    return MedicationSchedule.fromScheduleJsonList(rawItems);
  }

  Uri _buildScheduleUri(String path) {
    return Uri.parse('$baseUrl/$path').replace(
      queryParameters: {
        'patient_hash': patientHash,
        'role': role,
        if (userHash != null && userHash!.trim().isNotEmpty)
          'user_hash': userHash!.trim(),
      },
    );
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
