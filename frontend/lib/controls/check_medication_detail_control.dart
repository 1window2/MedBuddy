import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../services/api_config.dart';

// 파일명: check_medication_detail_control.dart
// 역할: OCR로 추출한 약 이름을 백엔드 약품 상세 조회 API와 연결한다.

// 클래스명: CheckMedicationDetail
// 역할: 처방전에서 인식된 약 이름으로 공공데이터 기반 상세 정보를 요청한다.
// 주요 책임:
// - 약 이름이 비어 있는 경우 불필요한 API 호출을 막는다.
// - 서버 응답을 MedicationDetail 목록으로 변환한다.
// - 네트워크/서버 오류를 화면에서 처리 가능한 StateError로 바꾼다.
class CheckMedicationDetail {
  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  CheckMedicationDetail({
    this.baseUrl = ApiConfig.baseUrl,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  // 함수명: requestMedicationDetail
  // 함수역할:
  // - 처방전 OCR 결과의 약 이름으로 백엔드 상세 조회 API를 호출한다.
  // - 여러 후보가 반환되면 현재 화면 흐름에서는 첫 번째 후보를 사용한다.
  // 매개변수:
  // - medicationSchedule: OCR에서 인식한 약 이름과 복약 일정 정보
  // 반환값:
  // - 조회 성공 시 첫 번째 MedicationDetail
  // - 약 이름이 없거나 조회 결과가 없으면 null
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) async {
    final medicationName = medicationSchedule.medicationName.trim();
    if (medicationName.isEmpty) {
      return null;
    }

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/identify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'extracted_text': medicationName}),
          )
          .timeout(const Duration(seconds: 60));

      final responseBody = utf8.decode(response.bodyBytes);
      if (response.statusCode != 200) {
        throw StateError(
          '약품 정보 조회 실패 (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = _decodeMap(responseBody);
      if (decodedData['success'] != true) {
        return null;
      }

      final medicationDetailList = _decodeMedicationDetailList(
        decodedData['data'],
      );
      return medicationDetailList.isEmpty ? null : medicationDetailList.first;
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Medication detail request failed.',
        name: 'CheckMedicationDetail',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('약품 정보를 불러오지 못했습니다.');
    }
  }

  Map<String, dynamic> _decodeMap(String responseBody) {
    final dynamic decodedData = jsonDecode(responseBody);
    if (decodedData is Map<String, dynamic>) {
      return decodedData;
    }
    throw StateError('서버 응답 형식이 올바르지 않습니다.');
  }

  List<MedicationDetail> _decodeMedicationDetailList(dynamic rawItems) {
    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map((item) =>
            MedicationDetail.fromJson(Map<String, dynamic>.from(item)))
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

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
