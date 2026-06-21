import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';

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

  // 함수명: requestMedicationSchedule
  // 함수역할:
  // - 클래스 다이어그램의 기존 메서드명을 유지하기 위한 오늘 일정 조회 wrapper이다.
  // 반환값:
  // - 오늘의 복약 일정 목록
  Future<List<MedicationSchedule>> requestMedicationSchedule() {
    return requestTodayMedicationSchedule();
  }

  // 함수명: requestTodayMedicationSchedule
  // 함수역할:
  // - 현재 환자 해시 기준으로 오늘 복약 일정을 요청한다.
  // 반환값:
  // - 오늘의 복약 일정 목록
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    try {
      final response = await _client
          .get(_buildScheduleUri('schedule/today'))
          .timeout(const Duration(seconds: 30));
      final responseBody = utf8.decode(response.bodyBytes);

      if (response.statusCode != 200) {
        throw StateError(
          'Schedule lookup failed (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = _decodeMap(responseBody);
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

  // 함수명: updateMedicationStatus
  // 함수역할:
  // - 저장된 약 하나의 복약 완료 상태를 서버에 반영한다.
  // 매개변수:
  // - medicationId: 저장된 복약 정보 식별자
  // - medicationStatus: 새 복약 완료 상태
  // 반환값:
  // - 서버가 반환한 업데이트된 복약 일정
  Future<MedicationSchedule> updateMedicationStatus(
    String medicationId,
    bool medicationStatus,
  ) async {
    try {
      final response = await _client
          .patch(
            _buildScheduleUri('schedule/$medicationId/status'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'medication_status': medicationStatus}),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = utf8.decode(response.bodyBytes);

      if (response.statusCode != 200) {
        throw StateError(
          'Status update failed (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = _decodeMap(responseBody);
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
    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map(
          (item) => MedicationSchedule.fromScheduleJson(
            Map<String, dynamic>.from(item),
          ).getTodayMedicationSchedule(),
        )
        .toList(growable: false);
  }

  Map<String, dynamic> _decodeMap(String responseBody) {
    final dynamic decodedData = jsonDecode(responseBody);
    if (decodedData is Map<String, dynamic>) {
      return decodedData;
    }
    throw StateError('Server response format was invalid.');
  }

  String _extractErrorDetail(String responseBody) {
    try {
      final decodedError = _decodeMap(responseBody);
      if (decodedError['detail'] != null) {
        return decodedError['detail'].toString();
      }
    } catch (_) {
      return responseBody;
    }
    return responseBody;
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
