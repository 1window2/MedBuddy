// File Name: check_saved_medication_control.dart
// Role: Registers, lists, deduplicates, and deletes patient-scoped saved medications.

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';

// 클래스명: MedicationSaveStatus
// 역할: 저장 요청의 성공·중복·실패 상태를 구분한다.
// 주요 책임:
// - 화면이 재저장 필요 여부와 완료 상태를 일관되게 판단할 수 있도록 결과 범주를 제공한다.
enum MedicationSaveStatus { saved, duplicate, failed }

// 클래스명: MedicationSaveResult
// 역할: 약 저장 상태와 사용자 메시지, 저장된 항목 ID를 함께 전달한다.
// 주요 책임:
// - 중복 결과도 완료로 취급하고 후속 일정 갱신에 사용할 저장 식별자를 보존한다.
// 속성:
// - status (MedicationSaveStatus): 약 저장의 성공·중복·실패 상태
// - message (String): 사용자에게 표시하거나 오류로 보존할 안내 문구
// - savedMedicationId (int?): 대상 저장 복약정보의 식별자
class MedicationSaveResult {
  final MedicationSaveStatus status;
  final String message;
  final int? savedMedicationId;

  // 함수이름: MedicationSaveResult
  // 함수역할: 약 저장의 성공·중복·실패 상태와 안내 메시지 및 선택적인 저장 ID를 함께 보존한다.
  // 매개변수:
  // - status (MedicationSaveStatus): 약 저장의 성공·중복·실패 상태
  // - message (String): 사용자에게 표시하거나 오류로 보존할 안내 문구
  // - savedMedicationId (int?): 대상 저장 복약정보의 식별자
  // 반환값:
  // - MedicationSaveResult: 초기화된 인스턴스.
  const MedicationSaveResult({
    required this.status,
    required this.message,
    this.savedMedicationId,
  });

  // 함수이름: isCompleted
  // 함수역할: 새 저장과 기존 중복 항목을 모두 저장 완료로 취급하고 실패 결과만 제외한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 새 저장과 기존 중복 항목을 모두 저장 완료로 취급하고 실패 결과만 제외한다.
  bool get isCompleted {
    return status == MedicationSaveStatus.saved ||
        status == MedicationSaveStatus.duplicate;
  }
}



// 클래스명: CheckSavedMedication
// 역할: 분석된 약 상세 정보와 OCR 복약 일정을 저장 목록에 반영한다.
// 주요 책임:
// - 약 상세 정보와 OCR 일정 정보를 합쳐 저장 요청을 만든다.
// - 저장된 복약 정보 목록을 조회한다.
// - 사용자가 선택한 저장 항목을 삭제한다.
// 속성:
// - baseUrl (String): 복약 API 기본 주소
// - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
// - _client (http.Client): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
class CheckSavedMedication {
  final String baseUrl;
  final String patientHash;
  final http.Client _client;
  final bool _ownsClient;

  // Function Name: CheckSavedMedication
  // Description: Normalizes the patient hash and binds saved-medication requests to an injected or owned authenticated client.
  // Parameters:
  // - baseUrl (String): Base URL of the medication API.
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - client (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // Returns:
  // - CheckSavedMedication: the initialized instance.
  CheckSavedMedication({
    this.baseUrl = ApiConfig.baseUrl,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? client,
  }) : patientHash = PatientHash.normalizePatientHash(patientHash),
       _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // 함수이름: saveMedicationDetail
  // 함수역할: 분석된 약 상세 정보와 처방전 일정 정보를 저장 API로 보낸다.
  // 매개변수:
  // - medicationDetail (MedicationDetail): 저장할 약 상세 정보
  // - medicationSchedule (MedicationSchedule?): 같은 약에 대응하는 처방전 분석 일정
  // 반환값:
  // - 저장, 중복, 실패 상태를 담은 MedicationSaveResult
  Future<MedicationSaveResult> saveMedicationDetail(
    MedicationDetail medicationDetail, {
    MedicationSchedule? medicationSchedule,
  }) async {
    final savePayload = _buildSaveRequest(medicationDetail, medicationSchedule);

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/save'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(savePayload),
          )
          .timeout(const Duration(seconds: 30));

      final responseBody = ApiResponseParser.decodeBody(response);
      if (response.statusCode != 200) {
        return MedicationSaveResult(
          status: MedicationSaveStatus.failed,
          message: ApiResponseParser.extractErrorDetail(responseBody),
        );
      }

      final decodedData = ApiResponseParser.decodeMap(responseBody);
      final message = _readMessage(decodedData, '저장되었습니다.');
      final savedMedicationId = _readPositiveInt(decodedData['id']);
      if (decodedData['duplicate'] == true) {
        return MedicationSaveResult(
          status: MedicationSaveStatus.duplicate,
          message: message,
          savedMedicationId: savedMedicationId,
        );
      }
      if (decodedData['success'] == true) {
        return MedicationSaveResult(
          status: MedicationSaveStatus.saved,
          message: message,
          savedMedicationId: savedMedicationId,
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

  // 함수이름: _buildSaveRequest
  // 함수역할: 약 상세정보와 처방전 복약 일정을 저장 API 요청 형식으로 합친다. 사용자가 OCR 약명을 직접 수정한 경우 API 응답 이름보다 수정명을 우선한다.
  // 매개변수:
  // - medicationDetail (MedicationDetail): 저장할 공공데이터 약 상세정보
  // - medicationSchedule (MedicationSchedule?): 같은 약의 선택적 처방전 OCR 복약 일정
  // 반환값:
  // - 저장 API에 전달할 JSON Map
  Map<String, dynamic> _buildSaveRequest(
    MedicationDetail medicationDetail,
    MedicationSchedule? medicationSchedule,
  ) {
    final savePayload = medicationDetail.toSaveJson();
    final prescriptionDate =
        medicationSchedule?.prescriptionDate ??
        medicationDetail.prescriptionDate;
    final preferredScheduleMedicationName =
        medicationSchedule?.nameCorrectionSource == 'user_edit' ||
            medicationSchedule?.nameCorrectionSource == 'manual_entry'
        ? medicationSchedule?.medicationName.trim() ?? ''
        : '';
    savePayload['patient_hash'] = patientHash;
    if (preferredScheduleMedicationName.isNotEmpty) {
      savePayload['item_name'] = preferredScheduleMedicationName;
    }
    savePayload['prescription_date'] = _formatDate(prescriptionDate);
    final prescriptionBatchId =
        medicationSchedule?.prescriptionBatchId.trim() ?? '';
    if (prescriptionBatchId.isNotEmpty) {
      savePayload['prescription_batch_id'] = prescriptionBatchId;
    }
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
    savePayload['schedule_slot_keys'] =
        medicationSchedule?.slotKeys ?? const <String>[];
    return savePayload;
  }

  // 함수이름: _formatDate
  // 함수역할: 날짜를 백엔드가 받을 수 있는 YYYY-MM-DD 문자열로 바꾼다.
  // 매개변수:
  // - value (DateTime?): 직렬화할 선택적 달력 날짜
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

  // Function Name: _readScheduleValue
  // Description: Prefers nonempty trimmed prescription schedule text, otherwise uses the trimmed value already present in medication details.
  // Parameters:
  // - scheduleValue (String?): Optional dosage-schedule value obtained from prescription analysis.
  // - fallbackValue (String): Fallback for absent or unparseable input.
  // Returns:
  // - String: Prefers nonempty trimmed prescription schedule text, otherwise uses the trimmed value already present in medication details.
  String _readScheduleValue(String? scheduleValue, String fallbackValue) {
    final normalizedScheduleValue = scheduleValue?.trim() ?? '';
    if (normalizedScheduleValue.isNotEmpty) {
      return normalizedScheduleValue;
    }
    return fallbackValue.trim();
  }

  // Function Name: requestSavedMedicationInfo
  // Description: Retrieves the patient's saved medication details, returning an empty list for unsuccessful payloads and surfacing transport or server failures.
  // Parameters:
  // - None.
  // Returns:
  // - Future<List<MedicationDetail>>: Retrieves the patient's saved medication details, returning an empty list for unsuccessful payloads and surfacing transport or server failures.
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async {
    try {
      final response = await _client
          .get(_buildMedicationUri('list'))
          .timeout(const Duration(seconds: 30));

      final responseBody = ApiResponseParser.decodeBody(response);
      if (response.statusCode != 200) {
        throw StateError(
          '저장된 복약 정보 조회 실패 (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = ApiResponseParser.decodeMap(responseBody);
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

  // Function Name: requestDelete
  // Description: Deletes one saved medication within the current patient scope and reports whether the server returned HTTP 200.
  // Parameters:
  // - savedMedicationId (int): Identifier of the targeted saved medication.
  // Returns:
  // - Future<bool>: Deletes one saved medication within the current patient scope and reports whether the server returned HTTP 200.
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

  // 함수이름: _decodeSavedMedicationInfoList
  // 함수역할: 저장 응답의 Map 항목을 상세 모델로 변환하고 양수 저장 ID가 없는 항목은 제외한다.
  // 매개변수:
  // - rawItems (dynamic): 변환 전 서버 단일 항목 또는 목록
  // 반환값:
  // - List<MedicationDetail>: 저장 응답의 Map 항목을 상세 모델로 변환하고 양수 저장 ID가 없는 항목은 제외한다.
  List<MedicationDetail> _decodeSavedMedicationInfoList(dynamic rawItems) {
    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map(
          // 함수이름: map 콜백
          // 함수역할: 저장된 약 응답 항목을 상세 정보 모델로 변환한다.
          // 매개변수:
          // - item (Map): 현재 변환·검사 중인 응답 또는 목록 항목
          // 반환값:
          // - 저장된 약의 상세 정보.
          (item) => MedicationDetail.fromJson(Map<String, dynamic>.from(item)),
        )
        .where(/* Function Name: where callback
         * Description: Keeps only saved medications with a positive server-assigned ID.
         * Parameters:
         * - item (MedicationDetail): Current response or collection entry being transformed or checked.
         * Returns:
         * - Whether the medication has a usable saved ID.
         */(item) => item.id != null && item.id! > 0)
        .toList(growable: false);
  }

  // 함수이름: _readMessage
  // 함수역할: 서버 메시지를 공백 정리한 뒤 비어 있으면 호출자가 지정한 안내문을 사용한다.
  // 매개변수:
  // - decodedData (Map<String, dynamic>): JSON 객체로 해석한 서버 응답
  // - fallback (String): 값이 없거나 해석 불가할 때 사용할 대체값
  // 반환값:
  // - String: 서버 메시지를 공백 정리한 뒤 비어 있으면 호출자가 지정한 안내문을 사용한다.
  String _readMessage(Map<String, dynamic> decodedData, String fallback) {
    final message = decodedData['message']?.toString().trim() ?? '';
    return message.isEmpty ? fallback : message;
  }

  // 함수이름: _readPositiveInt
  // 함수역할: 숫자 또는 문자열에서 양수 정수 ID만 인정하고 변환 실패·0·음수는 null로 처리한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - int?: 숫자 또는 문자열에서 양수 정수 ID만 인정하고 변환 실패·0·음수는 null로 처리한다.
  int? _readPositiveInt(dynamic value) {
    final parsedValue = value is int
        ? value
        : int.tryParse(value?.toString().trim() ?? '');
    return parsedValue != null && parsedValue > 0 ? parsedValue : null;
  }

  // 함수이름: _buildMedicationUri
  // 함수역할: 현재 환자 소유권 정보를 포함한 저장 복약 API URI를 만든다.
  // 매개변수:
  // - path (String): baseUrl 아래의 API 경로
  // 반환값:
  // - patient_hash가 포함된 URI
  Uri _buildMedicationUri(String path) {
    return Uri.parse(
      '$baseUrl/$path',
    ).replace(queryParameters: {'patient_hash': patientHash});
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
