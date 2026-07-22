import 'dart:convert';

import 'package:http/http.dart' as http;

import '../entities/analyzed_medication_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../entities/prescription_change_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';

// 파일명: check_prescription_change_control.dart
// 역할: 현재 분석 결과를 백엔드 처방 변화 비교 API와 연결한다.

// 클래스명: CheckPrescriptionChange
// 역할: 현재 처방 목록을 전송하고 이전 처방과의 비교 결과를 반환한다.
// 주요 책임:
// - 분석된 약품, 효능과 복약 일정을 비교 요청 payload로 변환한다.
// - 환자 해시로 이전 처방 조회 범위를 제한한다.
// - 서버 응답을 PrescriptionChangeRadar Entity로 변환한다.
class CheckPrescriptionChange {
  final String baseUrl;
  final String patientHash;
  final http.Client _client;
  final bool _ownsClient;

  CheckPrescriptionChange({
    this.baseUrl = ApiConfig.baseUrl,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? client,
  }) : patientHash = PatientHash.normalizePatientHash(patientHash),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  // 함수이름: requestPrescriptionChange
  // 함수역할:
  // - 현재 분석된 처방을 서버에 전달하고 이전 처방과의 차이를 요청한다.
  // 매개변수:
  // - medications: 약품 상세정보와 OCR 복약 일정이 결합된 현재 처방 목록
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
                  .map((item) => item.schedule.prescriptionDate)
                  .whereType<DateTime>()
                  .firstOrNull,
            ),
            'medications': medications
                .map(
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
  // 함수역할:
  // - 조제일자를 백엔드 요청 형식인 YYYY-MM-DD 문자열로 변환한다.
  // 매개변수:
  // - value: 현재 처방의 조제일자
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
  // 함수역할:
  // - Control이 직접 생성한 HTTP Client를 정리한다.
  // 반환값:
  // - 없음
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
