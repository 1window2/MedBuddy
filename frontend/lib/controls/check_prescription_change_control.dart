import 'dart:convert';

import 'package:http/http.dart' as http;

import '../entities/analyzed_medication_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../entities/prescription_change_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';

// 파일명: check_prescription_change_control.dart
// 역할: 현재 분석 처방과 이전 처방의 차이를 환자 범위 안에서 조회한다.

// Class Name: CheckPrescriptionChange
// Role: Sends the current prescription for comparison with the patient's preceding prescription.
// Responsibilities:
// - Serialize analyzed drug details and schedules, preserve patient scope, and decode the change-radar response.
// Attributes:
// - baseUrl (String): Base URL of the medication API.
// - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
// - _client (http.Client): HTTP transport; constructor documentation specifies ownership for injected clients.
class CheckPrescriptionChange {
  final String baseUrl;
  final String patientHash;
  final http.Client _client;
  final bool _ownsClient;

  // Function Name: CheckPrescriptionChange
  // Description: Normalizes patient ownership and binds prescription comparison requests to the configured backend and HTTP client.
  // Parameters:
  // - baseUrl (String): Base URL of the medication API.
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - client (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // Returns:
  // - CheckPrescriptionChange: the initialized instance.
  CheckPrescriptionChange({
    this.baseUrl = ApiConfig.baseUrl,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? client,
  }) : patientHash = PatientHash.normalizePatientHash(patientHash),
       _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // 함수이름: requestPrescriptionChange
  // 함수역할: 현재 분석된 처방을 서버에 전달하고 이전 처방과의 차이를 요청한다.
  // 매개변수:
  // - medications (List<AnalyzedMedication>): 약품 상세정보와 OCR 복약 일정이 결합된 현재 처방 목록
  // 반환값:
  // - 이전 처방 존재 여부와 변화 목록을 포함한 PrescriptionChangeRadar
  Future<PrescriptionChangeRadar> requestPrescriptionChange(
    List<AnalyzedMedication> medications,
  ) async {
    if (medications.isEmpty) {
      return const PrescriptionChangeRadar(hasPreviousPrescription: false);
    }

    final response = await _client
        .post(
          Uri.parse('$baseUrl/prescription/change-radar'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'patient_hash': patientHash,
            'prescription_date': _formatDate(
              medications
                  .map(/* 함수이름: map 콜백
                   * 함수역할: 비교 대상 약의 일정에서 처방 날짜를 추출한다.
                   * 매개변수:
                   * - item (AnalyzedMedication): 현재 변환·검사 중인 응답 또는 목록 항목
                   * 반환값:
                   * - 해당 약의 처방 날짜.
                   */(item) => item.schedule.prescriptionDate)
                  .whereType<DateTime>()
                  .firstOrNull,
            ),
            'medications': medications
                .map(
                  // 함수이름: map 콜백
                  // 함수역할: 분석된 약의 식별 정보·효능·용량·횟수·기간을 처방 변경 비교 요청 형식으로 묶는다.
                  // 매개변수:
                  // - item (AnalyzedMedication): 현재 변환·검사 중인 응답 또는 목록 항목
                  // 반환값:
                  // - 서버 비교 요청에 사용할 약 정보 맵.
                  (item) => {
                    'item_seq': item.detail.itemSeq,
                    'item_name': item.displayName,
                    'efficacy': item.detail.efficacy,
                    'dosage_per_time': item.schedule.dosage,
                    'daily_frequency': item.schedule.intakeTime,
                    'total_days': item.schedule.medicationTimeLabel,
                  },
                )
                .toList(growable: false),
          }),
        )
        .timeout(const Duration(seconds: 15));

    final responseBody = ApiResponseParser.decodeBody(response);
    if (response.statusCode != 200) {
      throw StateError(
        '처방 변화 조회 실패 (${response.statusCode}): '
        '${ApiResponseParser.extractErrorDetail(responseBody)}',
      );
    }
    return PrescriptionChangeRadar.fromJson(
      ApiResponseParser.decodeMap(responseBody),
    );
  }

  // 함수이름: _formatDate
  // 함수역할: 조제일자를 백엔드 요청 형식인 YYYY-MM-DD 문자열로 변환한다.
  // 매개변수:
  // - value (DateTime?): 현재 처방의 조제일자
  // 반환값:
  // - 변환된 날짜 문자열 또는 날짜가 없으면 null
  String? _formatDate(DateTime? value) {
    if (value == null) {
      return null;
    }
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  // 함수이름: dispose
  // 함수역할: Control이 직접 생성한 HTTP Client를 정리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
