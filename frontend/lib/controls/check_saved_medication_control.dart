// File Name: check_saved_medication_control.dart
// Role: Registers, lists, deduplicates, and deletes patient-scoped saved medications.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/json_value_reader.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_dose_rhythm.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';
import 'medication_history_control.dart';

// 클래스명: MedicationSaveStatus
// 역할: 저장 요청의 성공·중복·실패 상태를 구분한다.
// 주요 책임:
// - 화면이 재저장 필요 여부와 완료 상태를 일관되게 판단할 수 있도록 결과 범주를 제공한다.
enum MedicationSaveStatus { saved, duplicate, failed }

// 클래스명: MedicationSaveFailureKind
// 역할: 실패한 저장의 원인 범주를 구분해 화면이 서버 원문 대신 자기 언어의 안내 문구를 고르게 한다.
// 주요 책임:
// - none: 실패가 아닌 결과(저장·중복).
// - limitReached: 계정당 저장 가능한 약 수(기본 300개)를 넘어 서버가 409로 거절함.
// - network: 응답 지연·연결 실패로 서버 응답을 받지 못함.
// - other: 그 밖의 서버 거절·응답 형식 오류·저장 취소.
enum MedicationSaveFailureKind { none, limitReached, network, other }

enum MedicationRegimenAction { edit, stop, replace }

enum MedicationRegimenFailure {
  none,
  conflict,
  recordedDate,
  forbidden,
  missing,
  network,
  invalid,
  cancelled,
}

// 같은 확정 요청을 재시도할 때 ID와 본문을 보존해 중복 변경을 막는다.
class MedicationRegimenChange {
  final MedicationRegimenAction action;
  final DateTime effectiveDate;
  final int expectedRevision;
  final String operationId;
  final Map<String, dynamic> changes;

  MedicationRegimenChange({
    required this.action,
    required this.effectiveDate,
    required this.expectedRevision,
    String? operationId,
    Map<String, dynamic> changes = const {},
  }) : operationId = operationId ?? MedicationHistoryControl.newOperationId(),
       changes = Map.unmodifiable({
         for (final entry in changes.entries)
           entry.key: entry.value is List
               ? List.unmodifiable(entry.value as List)
               : entry.value,
       });

  Map<String, dynamic> toJson(String patientHash) => {
    'patient_hash': patientHash,
    'action': action.name,
    'effective_date': formatJsonDate(effectiveDate),
    'expected_revision': expectedRevision,
    'operation_id': operationId,
    'changes': changes,
  };
}

class MedicationRegimenResult {
  final MedicationRegimenFailure failure;
  final int? medicationId;
  final int? revision;
  final bool refreshFailed;

  const MedicationRegimenResult({
    this.failure = MedicationRegimenFailure.none,
    this.medicationId,
    this.revision,
    this.refreshFailed = false,
  });

  bool get success => failure == MedicationRegimenFailure.none;

  String message(bool english) => switch (failure) {
    MedicationRegimenFailure.none =>
      refreshFailed
          ? (english
                ? 'Saved. Refresh the pillbox and schedule to check the update.'
                : '변경은 저장됐습니다. 복약함과 일정을 새로고침해 확인해 주세요.')
          : (english
                ? 'Medication plan updated. Earlier records are kept.'
                : '복약 정보를 변경했습니다. 이전 기록은 유지됩니다.'),
    MedicationRegimenFailure.conflict =>
      english
          ? 'This medication changed on another device. Close this screen, refresh the pillbox, and review the latest plan.'
          : '다른 기기에서 약 정보가 변경됐습니다. 이 화면을 닫고 복약함을 새로고침한 뒤 최신 정보를 확인해 주세요.',
    MedicationRegimenFailure.recordedDate =>
      english
          ? 'Dose records already exist on or after this date. Choose a later date to keep them.'
          : '선택한 날짜부터 이미 복용 기록이 있습니다. 기록을 유지하려면 더 나중의 날짜를 선택해 주세요.',
    MedicationRegimenFailure.forbidden =>
      english
          ? 'You no longer have permission to change this medication.'
          : '이 약을 변경할 권한을 확인할 수 없습니다.',
    MedicationRegimenFailure.missing =>
      english
          ? 'This medication is no longer available. Refresh the pillbox.'
          : '해당 약을 찾을 수 없습니다. 복약함을 새로고침해 주세요.',
    MedicationRegimenFailure.network =>
      english
          ? 'Could not confirm the result. Retry without changing these fields to avoid duplicate updates.'
          : '변경 결과를 확인하지 못했습니다. 중복 변경을 막기 위해 같은 내용으로 다시 시도해 주세요.',
    MedicationRegimenFailure.cancelled =>
      english
          ? 'The account changed. Reopen the pillbox.'
          : '계정이 변경됐습니다. 복약함을 다시 열어 주세요.',
    MedicationRegimenFailure.invalid =>
      english
          ? 'Could not save this change. Check the plan and selected date.'
          : '변경을 저장하지 못했습니다. 입력 내용과 선택한 날짜를 확인해 주세요.',
  };
}

// 클래스명: MedicationSaveResult
// 역할: 약 저장 상태와 사용자 메시지, 저장된 항목 ID를 함께 전달한다.
// 주요 책임:
// - 중복 결과도 완료로 취급하고 후속 일정 갱신에 사용할 저장 식별자를 보존한다.
// 속성:
// - status (MedicationSaveStatus): 약 저장의 성공·중복·실패 상태
// - message (String): 사용자에게 표시하거나 오류로 보존할 안내 문구
// - savedMedicationId (int?): 대상 저장 복약정보의 식별자
// - failureKind (MedicationSaveFailureKind): 실패 원인 범주. 실패가 아니면 none, 지정하지 않은 실패는 other로 읽는다.
class MedicationSaveResult {
  final MedicationSaveStatus status;
  final String message;
  final int? savedMedicationId;
  final MedicationSaveFailureKind _failureKind;

  // 함수이름: MedicationSaveResult
  // 함수역할: 약 저장의 성공·중복·실패 상태와 안내 메시지 및 선택적인 저장 ID를 함께 보존한다.
  // 매개변수:
  // - status (MedicationSaveStatus): 약 저장의 성공·중복·실패 상태
  // - message (String): 사용자에게 표시하거나 오류로 보존할 안내 문구
  // - savedMedicationId (int?): 대상 저장 복약정보의 식별자
  // - failureKind (MedicationSaveFailureKind): 실패 원인 범주. 생략하면 실패 결과는 other로 취급한다.
  // 반환값:
  // - MedicationSaveResult: 초기화된 인스턴스.
  const MedicationSaveResult({
    required this.status,
    required this.message,
    this.savedMedicationId,
    MedicationSaveFailureKind failureKind = MedicationSaveFailureKind.none,
  }) : _failureKind = failureKind;

  // 함수이름: failureKind
  // 함수역할: 실패한 저장의 원인 범주를 알려 준다. 실패가 아닌 결과는 none, 원인을 지정하지 않은 실패는 other다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - MedicationSaveFailureKind: 화면이 안내 문구를 고를 실패 범주.
  MedicationSaveFailureKind get failureKind {
    if (status != MedicationSaveStatus.failed) {
      return MedicationSaveFailureKind.none;
    }
    return _failureKind == MedicationSaveFailureKind.none
        ? MedicationSaveFailureKind.other
        : _failureKind;
  }

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
    if (!(medicationSchedule?.isAsNeeded ?? medicationDetail.isAsNeeded) &&
        requiresDoseScheduleReview(
          medicationSchedule?.intakeTime ?? medicationDetail.dailyFrequency,
        )) {
      return const MedicationSaveResult(
        status: MedicationSaveStatus.failed,
        message: '복용 주기를 확인하지 못했습니다. 처방·복약지도에 맞는 일정으로 수정해 주세요.',
      );
    }
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
          // 저장 API의 409는 계정당 저장 가능한 약 수를 넘었을 때만 쓰인다.
          failureKind: response.statusCode == 409
              ? MedicationSaveFailureKind.limitReached
              : MedicationSaveFailureKind.other,
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
      return MedicationSaveResult(
        status: MedicationSaveStatus.failed,
        message: '저장에 실패했습니다. 다시 시도해주세요.',
        failureKind: error is TimeoutException || error is http.ClientException
            ? MedicationSaveFailureKind.network
            : MedicationSaveFailureKind.other,
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
    savePayload['prescription_date'] = formatJsonDate(prescriptionDate);
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
        medicationSchedule?.slotKeys ?? medicationDetail.scheduleSlotKeys;
    final isAsNeeded =
        medicationSchedule?.isAsNeeded ?? medicationDetail.isAsNeeded;
    savePayload['dosing_mode'] = isAsNeeded ? 'as_needed' : 'scheduled';
    if (isAsNeeded) savePayload['schedule_slot_keys'] = <String>[];
    return savePayload;
  }

  // 약 삭제를 사용하지 않고 적용일 이후의 처방만 변경한다.
  Future<MedicationRegimenResult> changeRegimen(
    int medicationId,
    MedicationRegimenChange change,
  ) async {
    if (medicationId <= 0 || change.expectedRevision < 0) {
      return const MedicationRegimenResult(
        failure: MedicationRegimenFailure.invalid,
      );
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/care/medications/$medicationId/change'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(change.toJson(patientHash)),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        final detail = ApiResponseParser.extractErrorDetail(
          ApiResponseParser.decodeBody(response),
        );
        if (response.statusCode == 409 &&
            detail.contains('already has dose records')) {
          return const MedicationRegimenResult(
            failure: MedicationRegimenFailure.recordedDate,
          );
        }
        return MedicationRegimenResult(
          failure: switch (response.statusCode) {
            409 => MedicationRegimenFailure.conflict,
            401 || 403 => MedicationRegimenFailure.forbidden,
            404 => MedicationRegimenFailure.missing,
            >= 500 => MedicationRegimenFailure.network,
            _ => MedicationRegimenFailure.invalid,
          },
        );
      }
      final data = ApiResponseParser.decodeMap(
        ApiResponseParser.decodeBody(response),
      );
      final id = _readPositiveInt(data['id']);
      final revision = int.tryParse('${data['revision']}');
      if (data['success'] != true ||
          id == null ||
          revision == null ||
          revision < 0) {
        return const MedicationRegimenResult(
          failure: MedicationRegimenFailure.network,
        );
      }
      return MedicationRegimenResult(medicationId: id, revision: revision);
    } catch (_) {
      return const MedicationRegimenResult(
        failure: MedicationRegimenFailure.network,
      );
    }
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

  // 함수이름: requestSavedMedicationInfo
  // 함수역할: 저장 약 목록을 조회하며 실패하거나 목록이 누락된 응답은 오류로 구분한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<List<MedicationDetail>>: 성공적으로 조회한 목록. 확인 실패 시 StateError.
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async {
    // 원래 예외를 함께 전달해 화면이 응답 지연·연결 실패 같은 원인별 안내를 고를 수 있게 한다.
    return ApiResponseParser.guardRequest(
      operation: '저장된 복약 정보를 불러오지 못했습니다',
      logName: 'CheckSavedMedication',
      logMessage: 'Saved medication list request failed.',
      request: () async {
        final response = await _client
            .get(_buildMedicationUri('list'))
            .timeout(const Duration(seconds: 30));

        final responseBody = ApiResponseParser.requireOkBody(
          '저장된 복약 정보 조회 실패',
          response,
        );

        final decodedData = ApiResponseParser.decodeMap(responseBody);
        // 조회 실패를 약이 없는 상태로 표시하지 않도록 응답을 검증한다.
        if (decodedData['success'] != true || decodedData['data'] is! List) {
          throw StateError('저장된 복약 정보 응답을 확인하지 못했습니다.');
        }

        return _decodeSavedMedicationInfoList(decodedData['data']);
      },
    );
  }

  // Function Name: requestDelete
  // Description: Deletes one saved medication within the current patient scope. HTTP 404 means the medication no longer exists in this scope (for example it was deleted on another device), so it counts as deleted and the list can drop it.
  // Parameters:
  // - savedMedicationId (int): Identifier of the targeted saved medication.
  // Returns:
  // - Future<bool>: true when the server returned HTTP 200 or 404; false for other responses and transport failures.
  Future<bool> requestDelete(int savedMedicationId) async {
    try {
      final response = await _client
          .delete(_buildMedicationUri('delete/$savedMedicationId'))
          .timeout(const Duration(seconds: 30));
      return response.statusCode == 200 || response.statusCode == 404;
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
        .where(
          /* Function Name: where callback
         * Description: Keeps only saved medications with a positive server-assigned ID.
         * Parameters:
         * - item (MedicationDetail): Current response or collection entry being transformed or checked.
         * Returns:
         * - Whether the medication has a usable saved ID.
         */
          (item) => item.id != null && item.id! > 0,
        )
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
