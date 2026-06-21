import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';

enum MedicationSaveStatus {
  saved,
  duplicate,
  failed,
}

class MedicationSaveResult {
  final MedicationSaveStatus status;
  final String message;

  const MedicationSaveResult({
    required this.status,
    required this.message,
  });

  bool get isCompleted {
    return status == MedicationSaveStatus.saved ||
        status == MedicationSaveStatus.duplicate;
  }
}

// 파일명: check_saved_medication_control.dart
// 역할: 저장된 복약 정보 생성, 조회, 삭제 API를 담당한다.

// 클래스명: CheckSavedMedication
// 역할: 분석된 약 상세 정보와 OCR 복약 일정을 저장 목록에 반영한다.
// 주요 책임:
// - 약 상세 정보와 OCR 일정 정보를 합쳐 저장 요청을 만든다.
// - 저장된 복약 정보 목록을 조회한다.
// - 사용자가 선택한 저장 항목을 삭제한다.
class CheckSavedMedication {
  final String baseUrl;
  final String patientHash;
  final String? userHash;
  final String role;
  final http.Client _client;
  final bool _ownsClient;

  CheckSavedMedication({
    this.baseUrl = ApiConfig.baseUrl,
    this.patientHash = PatientHash.defaultPatientHash,
    this.userHash,
    this.role = 'patient',
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  // 함수명: saveMedicationDetail
  // 함수역할:
  // - 분석된 약 상세 정보와 처방전 일정 정보를 저장 API로 보낸다.
  // 매개변수:
  // - medicationDetail: 저장할 약 상세 정보
  // - medicationSchedule: 같은 약에 대응하는 처방전 분석 일정
  // 반환값:
  // - 저장, 중복, 실패 상태를 담은 MedicationSaveResult
  Future<MedicationSaveResult> saveMedicationDetail(
    MedicationDetail medicationDetail, {
    MedicationSchedule? medicationSchedule,
  }) async {
    final savePayload = _buildSaveRequest(
      medicationDetail,
      medicationSchedule,
    );

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/save'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(savePayload),
          )
          .timeout(const Duration(seconds: 30));

      final responseBody = utf8.decode(response.bodyBytes);
      if (response.statusCode != 200) {
        return MedicationSaveResult(
          status: MedicationSaveStatus.failed,
          message: _extractErrorDetail(responseBody),
        );
      }

      final decodedData = _decodeMap(responseBody);
      final message = _readMessage(decodedData, '저장되었습니다.');
      if (decodedData['duplicate'] == true) {
        return MedicationSaveResult(
          status: MedicationSaveStatus.duplicate,
          message: message,
        );
      }
      if (decodedData['success'] == true) {
        return MedicationSaveResult(
          status: MedicationSaveStatus.saved,
          message: message,
        );
      }

      return MedicationSaveResult(
        status: MedicationSaveStatus.failed,
        message: message,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Medication detail save failed.',
        name: 'CheckSavedMedication',
        error: error,
        stackTrace: stackTrace,
      );
      return const MedicationSaveResult(
        status: MedicationSaveStatus.failed,
        message: '저장에 실패했습니다. 다시 시도해주세요.',
      );
    }
  }

  // 함수명: _buildSaveRequest
  // 함수역할:
  // - 저장 API가 요구하는 JSON 요청 본문을 만든다.
  // - 처방전에서 추출한 일정 값이 있으면 약 상세 정보보다 우선 사용한다.
  // 매개변수:
  // - medicationDetail: 저장할 약 상세 정보
  // - medicationSchedule: 같은 약에 대응하는 처방전 분석 일정
  // 반환값:
  // - 저장 API 요청 JSON Map
  Map<String, dynamic> _buildSaveRequest(
    MedicationDetail medicationDetail,
    MedicationSchedule? medicationSchedule,
  ) {
    final savePayload = medicationDetail.toSaveJson();
    final prescriptionDate =
        medicationSchedule?.prescriptionDate ?? medicationDetail.prescriptionDate;
    savePayload['patient_hash'] = patientHash;
    savePayload['prescription_date'] = _formatDate(prescriptionDate);
    savePayload['dosage_per_time'] = _readScheduleValue(
      medicationSchedule?.dosage,
      medicationDetail.dosagePerTime,
    );
    savePayload['daily_frequency'] = _readScheduleValue(
      medicationSchedule?.intakeTime,
      medicationDetail.dailyFrequency,
    );
    savePayload['total_days'] = _readScheduleValue(
      medicationSchedule?.medicationTimeLabel,
      medicationDetail.totalDays,
    );
    return savePayload;
  }

  // 함수명: _formatDate
  // 함수역할:
  // - 날짜를 백엔드가 받을 수 있는 YYYY-MM-DD 문자열로 바꾼다.
  // 반환값:
  // - 날짜 문자열 또는 null
  String? _formatDate(DateTime? value) {
    if (value == null) {
      return null;
    }
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  // 함수명: _readScheduleValue
  // 함수역할:
  // - OCR 일정 값을 우선 사용하고 비어 있으면 약 상세 정보 값을 사용한다.
  // 반환값:
  // - 공백이 제거된 일정 문자열
  String _readScheduleValue(String? scheduleValue, String fallbackValue) {
    final normalizedScheduleValue = scheduleValue?.trim() ?? '';
    if (normalizedScheduleValue.isNotEmpty) {
      return normalizedScheduleValue;
    }
    return fallbackValue.trim();
  }

  // 함수명: requestSavedMedicationInfo
  // 함수역할:
  // - 저장된 복약 정보 목록을 서버에서 가져온다.
  // 반환값:
  // - 저장된 약 상세 정보 목록
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async {
    try {
      final response = await _client
          .get(_buildMedicationUri('list'))
          .timeout(const Duration(seconds: 30));

      final responseBody = utf8.decode(response.bodyBytes);
      if (response.statusCode != 200) {
        throw StateError(
          '저장된 복약 정보 조회 실패 (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = _decodeMap(responseBody);
      if (decodedData['success'] != true) {
        return [];
      }

      return _decodeSavedMedicationInfoList(decodedData['data']);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Saved medication list request failed.',
        name: 'CheckSavedMedication',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('저장된 복약 정보를 불러오지 못했습니다.');
    }
  }

  // 함수명: requestDelete
  // 함수역할:
  // - 저장된 복약 정보 하나를 서버에서 삭제한다.
  // 매개변수:
  // - savedMedicationId: 삭제할 저장 복약 정보 식별자
  // 반환값:
  // - 삭제 성공 여부
  Future<bool> requestDelete(int savedMedicationId) async {
    try {
      final response = await _client
          .delete(_buildMedicationUri('delete/$savedMedicationId'))
          .timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (error, stackTrace) {
      developer.log(
        'Saved medication delete failed.',
        name: 'CheckSavedMedication',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Map<String, dynamic> _decodeMap(String responseBody) {
    final dynamic decodedData = jsonDecode(responseBody);
    if (decodedData is Map<String, dynamic>) {
      return decodedData;
    }
    throw StateError('서버 응답 형식이 올바르지 않습니다.');
  }

  List<MedicationDetail> _decodeSavedMedicationInfoList(dynamic rawItems) {
    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map((item) =>
            MedicationDetail.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.id != null && item.id! > 0)
        .toList(growable: false);
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

  String _readMessage(Map<String, dynamic> decodedData, String fallback) {
    final message = decodedData['message']?.toString().trim() ?? '';
    return message.isEmpty ? fallback : message;
  }

  // 함수명: _buildMedicationUri
  // 함수역할:
  // - 현재 환자 소유권 정보를 포함한 저장 복약 API URI를 만든다.
  // 매개변수:
  // - path: baseUrl 아래의 API 경로
  // 반환값:
  // - patient_hash, role, user_hash가 포함된 URI
  Uri _buildMedicationUri(String path) {
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
