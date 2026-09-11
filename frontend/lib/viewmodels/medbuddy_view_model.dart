// File Name: medbuddy_view_model.dart
// Role: Owns patient-scoped feature state and composes prescription, schedule, reminder, and settings extensions.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controls/check_health_recommendation_control.dart';
import '../controls/check_medication_detail_control.dart';
import '../controls/check_prescription_change_control.dart';
import '../controls/check_schedule_control.dart';
import '../controls/check_saved_medication_control.dart';
import '../controls/check_today_medication_info_control.dart';
import '../controls/input_prescription_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../controls/manage_account_control.dart';
import '../controls/set_notification_control.dart';
import '../entities/analyzed_medication_entity.dart';
import '../entities/health_recommendation_entity.dart';
import '../entities/identified_pill_save_request_entity.dart';
import '../entities/manual_medication_entry_entity.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_image_url_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../entities/pill_identification_entity.dart';
import '../entities/prescription_change_entity.dart';
import '../entities/prescription_flow_entity.dart';
import '../entities/recognized_text_region_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/authenticated_api_client.dart';
import '../services/medication_reminder_background_service.dart';
import '../services/manual_medication_image_store.dart';
import '../services/notification_service.dart';
import '../services/user_facing_error_message.dart';
import 'medbuddy_feature_updates.dart';

part 'medbuddy_prescription_view_model.dart';
part 'medbuddy_saved_medication_view_model.dart';
part 'medbuddy_schedule_view_model.dart';
part 'medbuddy_reminder_view_model.dart';
part 'medbuddy_health_recommendation_view_model.dart';
part 'medbuddy_user_setting_view_model.dart';

// 클래스명: TodayMedicationProgress
// 역할: 오늘 예정된 개별 복용 슬롯의 전체 수와 완료 수를 보관한다.
// 주요 책임:
// - 같은 약의 여러 복용 시간대를 각각 집계한 진행률을 홈 화면에 전달한다.
// 속성:
// - completedCount (int): 오늘 완료된 약별 복약 시간대 수
// - totalCount (int): 진행률 또는 집계의 전체 대상 수
class TodayMedicationProgress {
  final int completedCount;
  final int totalCount;

  // 함수이름: TodayMedicationProgress
  // 함수역할: 오늘 복약의 완료 슬롯 수와 전체 슬롯 수를 진행률 자료로 묶는다.
  // 매개변수:
  // - completedCount (int): 오늘 완료된 약별 복약 시간대 수
  // - totalCount (int): 진행률 또는 집계의 전체 대상 수
  // 반환값:
  // - TodayMedicationProgress: 초기화된 인스턴스.
  const TodayMedicationProgress({
    required this.completedCount,
    required this.totalCount,
  });
}

// Class Name: SavedMedicationBatchDeleteResult
// Role: Summarizes successful and failed saved-medication deletions.
// Responsibilities:
// - Distinguish an empty selection, full success, and partial failure for the list UI.
// Attributes:
// - successCount (int): Number of successfully saved or deleted items.
// - failureCount (int): Number of failed items.
class SavedMedicationBatchDeleteResult {
  final int successCount;
  final int failureCount;

  // Function Name: SavedMedicationBatchDeleteResult
  // Description: Captures successful and failed deletion counts for an explicitly selected medication batch.
  // Parameters:
  // - successCount (int): Number of successfully saved or deleted items.
  // - failureCount (int): Number of failed items.
  // Returns:
  // - SavedMedicationBatchDeleteResult: the initialized instance.
  const SavedMedicationBatchDeleteResult({
    required this.successCount,
    required this.failureCount,
  });

  // Function Name: totalCount
  // Description: Computes the number of attempted medication deletions from success and failure counts.
  // Parameters:
  // - None.
  // Returns:
  // - int: Computes the number of attempted medication deletions from success and failure counts.
  int get totalCount => successCount + failureCount;
  // Function Name: allSucceeded
  // Description: Reports full success only when at least one medication was selected and no deletion failed.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Reports full success only when at least one medication was selected and no deletion failed.
  bool get allSucceeded => totalCount > 0 && failureCount == 0;
  // Function Name: hasFailures
  // Description: Reports whether any selected medication failed to delete.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether any selected medication failed to delete.
  bool get hasFailures => failureCount > 0;
}



// 클래스명: MedBuddyViewModel
// 역할: 처방전 인식, 약품 분석, 복약 정보 저장, 일정 조회, 설정 저장 흐름을 관리한다.
// 주요 책임:
// - 각 Control 객체의 API 호출 결과를 화면 상태로 변환한다.
// - 처방전 분석 흐름의 단계별 상태를 유지한다.
// - 저장된 복약 정보와 오늘의 복약 일정을 캐시한다.
// - 사용자 설정을 불러오고 변경 사항을 화면에 반영한다.
// 속성:
// - inputPrescription (InputPrescription): 이미지 선택·로컬 OCR·분석 요청 Control
// - checkMedicationDetail (CheckMedicationDetail): 공공데이터 약 상세 조회 Control
// - checkPrescriptionChange (CheckPrescriptionChange): 이전 처방 비교 조회 Control
// - checkSavedMedication (CheckSavedMedication): 저장 약 등록·조회·삭제 Control
// - checkSchedule (CheckSchedule): 일정 조회와 완료 상태 변경 Control
// - checkTodayMedicationInfo (CheckTodayMedicationInfo): 오늘 복약 요약 조회 Control
// - checkHealthRecommendation (CheckHealthRecommendation): 건강 관리 추천 조회 Control
// - setNotification (SetNotification): 알림 설정 저장 및 플랫폼 등록 Control
// - manageUserSetting (ManageUserSetting): 사용자별 설정 영속화 Control
// - manageAccount (ManageAccount): 서버 계정 삭제와 로컬 캐시 정리 Control
// - notificationService (NotificationService): 플랫폼 로컬 알림 서비스
// - manualMedicationImageStore (ManualMedicationImageStore): 직접 등록 약 사진의 기기 저장 경계
// - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
// - _apiClient (http.Client): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
// - _userSetting (UserSetting): 언어·접근성·알림 정책을 포함한 사용자 설정
// - _analyzedMedicationByScheduleIndex (Map<int, AnalyzedMedication>): 원래 OCR 행 인덱스별 분석 성공 결과
class MedBuddyViewModel extends ChangeNotifier {
  late final InputPrescription inputPrescription;
  late final CheckMedicationDetail checkMedicationDetail;
  late final CheckPrescriptionChange checkPrescriptionChange;
  late final CheckSavedMedication checkSavedMedication;
  late final CheckSchedule checkSchedule;
  late final CheckTodayMedicationInfo checkTodayMedicationInfo;
  late final CheckHealthRecommendation checkHealthRecommendation;
  late final SetNotification setNotification;
  late final ManageUserSetting manageUserSetting;
  late final ManageAccount manageAccount;
  final NotificationService notificationService;
  final ManualMedicationImageStore manualMedicationImageStore;
  final String patientHash;
  final http.Client _apiClient;
  final bool _ownsApiClient;
  bool _isDisposed = false;
  final Map<MedBuddyFeature, MedBuddyFeatureUpdates> _featureUpdates = {
    for (final feature in MedBuddyFeature.values)
      feature: MedBuddyFeatureUpdates(),
  };

  // 함수이름: updatesFor
  // 함수역할: 지정 기능의 변경 알림 채널을 제공해 관련 화면만 상태를 구독하게 한다.
  // 매개변수:
  // - feature (MedBuddyFeature): 변경 알림을 조회하거나 발행할 기능 영역
  // 반환값:
  // - MedBuddyFeatureUpdates: 지정 기능의 변경 알림 채널을 제공해 관련 화면만 상태를 구독하게 한다.
  MedBuddyFeatureUpdates updatesFor(MedBuddyFeature feature) {
    return _featureUpdates[feature]!;
  }

  PrescriptionFlowState _prescriptionFlowState = PrescriptionFlowState.idle;
  // 함수이름: prescriptionFlowState
  // 함수역할: 입력·인식·미리보기·분석·결과·실패를 구분하는 현재 처방 흐름 상태를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - PrescriptionFlowState: 입력·인식·미리보기·분석·결과·실패를 구분하는 현재 처방 흐름 상태를 제공한다.
  PrescriptionFlowState get prescriptionFlowState => _prescriptionFlowState;
  int _prescriptionOperationId = 0;

  AnalysisProgressStep _analysisProgressStep =
      AnalysisProgressStep.prescriptionRecognition;
  // 함수이름: analysisProgressStep
  // 함수역할: 현재 처방 인식 또는 약품 분석 진행 단계 값을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - AnalysisProgressStep: 현재 처방 인식 또는 약품 분석 진행 단계 값을 제공한다.
  AnalysisProgressStep get analysisProgressStep => _analysisProgressStep;

  // 함수이름: isPrescriptionAnalyzing
  // 함수역할: 처방전 인식이나 약품 상세 분석이 진행 중인 상태인지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 처방전 인식이나 약품 상세 분석이 진행 중인 상태인지 확인한다.
  bool get isPrescriptionAnalyzing {
    return _prescriptionFlowState ==
            PrescriptionFlowState.recognizingPrescription ||
        _prescriptionFlowState == PrescriptionFlowState.analyzingMedication;
  }

  // 함수이름: isLoading
  // 함수역할: 기존 호출부가 처방 인식·분석 진행 여부를 공통 로딩 값으로 읽도록 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 기존 호출부가 처방 인식·분석 진행 여부를 공통 로딩 값으로 읽도록 제공한다.
  bool get isLoading => isPrescriptionAnalyzing;

  int? _savingMedicationIndex;
  // Function Name: savingMedicationIndex
  // Description: Exposes the analysis-list index currently being saved, or null when no individual save is running.
  // Parameters:
  // - None.
  // Returns:
  // - int?: The analysis-list index currently being saved, or null when no individual save is running.
  int? get savingMedicationIndex => _savingMedicationIndex;
  // Function Name: isMedicationSaving
  // Description: Reports whether an individual medication save has an active list index.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether an individual medication save has an active list index.
  bool get isMedicationSaving => _savingMedicationIndex != null;

  final Set<int> _completedMedicationSaveIndexes = {};
  // 함수이름: completedMedicationSaveIndexes
  // 함수역할: 이미 저장 또는 중복 확인된 분석 목록 인덱스를 변경할 수 없는 집합으로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Set<int>: 이미 저장 또는 중복 확인된 분석 목록 인덱스를 변경할 수 없는 집합으로 제공한다.
  Set<int> get completedMedicationSaveIndexes =>
      Set.unmodifiable(_completedMedicationSaveIndexes);

  bool _isAllMedicationSaving = false;
  // 함수이름: isAllMedicationSaving
  // 함수역할: 분석 약 전체 저장 작업의 진행 여부를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 분석 약 전체 저장 작업의 진행 여부를 제공한다.
  bool get isAllMedicationSaving => _isAllMedicationSaving;

  bool _isSavedMedicationLoading = false;
  // Function Name: isSavedMedicationLoading
  // Description: Exposes whether the saved-medication list is being fetched.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether the saved-medication list is being fetched.
  bool get isSavedMedicationLoading => _isSavedMedicationLoading;

  bool _isTodayScheduleLoading = false;
  // Function Name: isTodayScheduleLoading
  // Description: Exposes whether the tracked current schedule load is still pending.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether the tracked current schedule load is still pending.
  bool get isTodayScheduleLoading => _isTodayScheduleLoading;
  bool _hasTodayScheduleLoadError = false;
  // Function Name: hasTodayScheduleLoadError
  // Description: Exposes failure of the latest applicable schedule load for retry-state rendering.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Failure of the latest applicable schedule load for retry-state rendering.
  bool get hasTodayScheduleLoadError => _hasTodayScheduleLoadError;
  bool _lastTodayScheduleLoadSucceeded = false;
  int _todayScheduleEpoch = 0;
  // 가장 최근 일정 조회만 화면의 로딩 상태를 종료할 수 있도록 요청 번호를 보관한다.
  int? _activeTodayScheduleLoadEpoch;

  bool _isHealthRecommendationLoading = false;
  // 함수이름: isHealthRecommendationLoading
  // 함수역할: 건강 관리 추천 조회의 진행 여부를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 건강 관리 추천 조회의 진행 여부를 제공한다.
  bool get isHealthRecommendationLoading => _isHealthRecommendationLoading;

  bool _hasNoActiveHealthMedications = false;
  // 함수이름: hasNoActiveHealthMedications
  // 함수역할: 서버에서 확인된 건강 추천 대상 약 없음 상태를 제공한다. 매개변수: 없음. 반환값: 대상 약 없음 여부.
  bool get hasNoActiveHealthMedications => _hasNoActiveHealthMedications;

  String _statusMessage = '';
  // 함수이름: statusMessage
  // 함수역할: 최근 상태 안내를 제공하고 아직 없으면 현재 언어의 처방전 입력 안내를 사용한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 최근 상태 안내를 제공하고 아직 없으면 현재 언어의 처방전 입력 안내를 사용한다.
  String get statusMessage {
    if (_statusMessage.isNotEmpty) {
      return _statusMessage;
    }
    return _isEnglishSetting
        ? 'Take a prescription photo or choose an image.'
        : '처방전을 촬영하거나 이미지를 선택해주세요.';
  }

  String _analysisErrorMessage = '';
  // 함수이름: analysisErrorMessage
  // 함수역할: 처방 인식·상세 분석에서 기록한 최근 실패 안내를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 처방 인식·상세 분석에서 기록한 최근 실패 안내를 제공한다.
  String get analysisErrorMessage => _analysisErrorMessage;
  // 함수이름: canRetryPrescriptionAnalysis
  // 함수역할: 인식 결과가 남아 있는 상세 분석 실패 또는 미확인 재검토 상태에서만 재분석을 허용한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 인식 결과가 남아 있는 상세 분석 실패 또는 미확인 재검토 상태에서만 재분석을 허용한다.
  bool get canRetryPrescriptionAnalysis =>
      (_prescriptionFlowState == PrescriptionFlowState.analysisFailed ||
          _prescriptionFlowState ==
              PrescriptionFlowState.medicationReviewRequired) &&
      _analysisProgressStep != AnalysisProgressStep.prescriptionRecognition &&
      _recognizedMedicationScheduleList.isNotEmpty;

  int _lastPrescriptionRawMedicationCount = 0;
  int _lastPrescriptionParsedMedicationCount = 0;
  int _lastPrescriptionSkippedMedicationCount = 0;
  // Function Name: lastPrescriptionRawMedicationCount
  // Description: Exposes the latest raw OCR medication count before parsing exclusions.
  // Parameters:
  // - None.
  // Returns:
  // - int: The latest raw OCR medication count before parsing exclusions.
  int get lastPrescriptionRawMedicationCount =>
      _lastPrescriptionRawMedicationCount;
  // Function Name: lastPrescriptionParsedMedicationCount
  // Description: Exposes the latest count of usable parsed prescription entries.
  // Parameters:
  // - None.
  // Returns:
  // - int: The latest count of usable parsed prescription entries.
  int get lastPrescriptionParsedMedicationCount =>
      _lastPrescriptionParsedMedicationCount;
  // Function Name: lastPrescriptionSkippedMedicationCount
  // Description: Exposes the latest number of excluded OCR entries for the review notice.
  // Parameters:
  // - None.
  // Returns:
  // - int: The latest number of excluded OCR entries for the review notice.
  int get lastPrescriptionSkippedMedicationCount =>
      _lastPrescriptionSkippedMedicationCount;

  // Function Name: correctedPrescriptionMedicationCount
  // Description: Counts recognized medication entries with recorded name corrections.
  // Parameters:
  // - None.
  // Returns:
  // - int: Counts recognized medication entries with recorded name corrections.
  int get correctedPrescriptionMedicationCount {
    return _recognizedMedicationScheduleList
        .where(/* Function Name: where callback
         * Description: Selects prescription schedules whose recognized medication name has been corrected.
         * Parameters:
         * - schedule (MedicationSchedule): Medication course with name, dose, duration, and slots.
         * Returns:
         * - Whether this schedule has a name correction.
         */(schedule) => schedule.hasNameCorrection)
        .length;
  }

  // Function Name: prescriptionRecognitionNotice
  // Description: Builds a localized preanalysis review notice for corrected names and skipped OCR entries, returning blank when neither occurred.
  // Parameters:
  // - None.
  // Returns:
  // - String: Builds a localized preanalysis review notice for corrected names and skipped OCR entries, returning blank when neither occurred.
  String get prescriptionRecognitionNotice {
    final correctedCount = correctedPrescriptionMedicationCount;
    final skippedCount = _lastPrescriptionSkippedMedicationCount;
    if (correctedCount <= 0 && skippedCount <= 0) {
      return '';
    }

    final parts = <String>[];
    if (correctedCount > 0) {
      parts.add(
        _isEnglishSetting
            ? '$correctedCount name correction'
            : '$correctedCount개 약명 보정',
      );
    }
    if (skippedCount > 0) {
      parts.add(
        _isEnglishSetting
            ? '$skippedCount OCR item skipped'
            : '$skippedCount개 OCR 항목 제외',
      );
    }

    return _isEnglishSetting
        ? '${parts.join(' · ')}. Please review before analysis.'
        : '${parts.join(' · ')} 내역을 분석 전 확인해주세요.';
  }

  UserSetting _userSetting = const UserSetting();
  // Function Name: userSetting
  // 함수역할: 현재 환자 범위의 접근성·언어·알림 설정을 제공한다.
  // Parameters:
  // - None.
  // Returns:
  // - UserSetting: User settings including language, accessibility, and notification policy.
  UserSetting get userSetting => _userSetting;
  // 함수이름: _isEnglishSetting
  // 함수역할: 사용자 언어 코드를 정규화해 영어 계열 표시를 선택해야 하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 사용자 언어 코드를 정규화해 영어 계열 표시를 선택해야 하는지 확인한다.
  bool get _isEnglishSetting =>
      userSetting.language.trim().toLowerCase().startsWith('en');

  List<MedicationSchedule> _recognizedMedicationScheduleList = [];
  // 함수이름: recognizedMedicationScheduleList
  // 함수역할: 사용자가 검토·수정 중인 OCR 복약 일정 목록을 읽기 전용으로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - List<MedicationSchedule>: 사용자가 검토·수정 중인 OCR 복약 일정 목록을 읽기 전용으로 제공한다.
  List<MedicationSchedule> get recognizedMedicationScheduleList =>
      List.unmodifiable(_recognizedMedicationScheduleList);
  List<RecognizedTextRegion> _recognizedTextRegionList = [];
  // 함수이름: recognizedTextRegionList
  // 함수역할: 현재 처방전 미리보기의 약품·개인정보 영역 목록을 읽기 전용으로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - List<RecognizedTextRegion>: 현재 처방전 미리보기의 약품·개인정보 영역 목록을 읽기 전용으로 제공한다.
  List<RecognizedTextRegion> get recognizedTextRegionList =>
      List.unmodifiable(_recognizedTextRegionList);
  String _prescriptionPreviewImagePath = '';
  // 함수이름: prescriptionPreviewImagePath
  // 함수역할: 현재 처방 검토 화면에 표시할 로컬 이미지 경로를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 현재 처방 검토 화면에 표시할 로컬 이미지 경로를 제공한다.
  String get prescriptionPreviewImagePath => _prescriptionPreviewImagePath;

  // 함수이름: medicationScheduleList
  // 함수역할: 기존 호출부가 인식된 처방 일정 목록을 읽을 수 있도록 호환 접근자를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - List<MedicationSchedule>: 기존 호출부가 인식된 처방 일정 목록을 읽을 수 있도록 호환 접근자를 제공한다.
  List<MedicationSchedule> get medicationScheduleList =>
      recognizedMedicationScheduleList;

  List<AnalyzedMedication> _analyzedMedicationList = [];
  // 함수이름: analyzedMedicationList
  // 함수역할: 원래 처방 순서로 정리된 상세 분석 성공 목록을 읽기 전용으로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - List<AnalyzedMedication>: 원래 처방 순서로 정리된 상세 분석 성공 목록을 읽기 전용으로 제공한다.
  List<AnalyzedMedication> get analyzedMedicationList =>
      List.unmodifiable(_analyzedMedicationList);

  // 상세조회가 끝난 약은 원래 OCR 행 인덱스와 함께 보존해 재조회 시 중복 호출을 막는다.
  final Map<int, AnalyzedMedication> _analyzedMedicationByScheduleIndex = {};
  final Set<int> _unverifiedMedicationScheduleIndexes = {};
  // 함수이름: verifiedMedicationScheduleIndexes
  // 함수역할: 공공데이터 상세 조회가 성공한 원래 OCR 행 인덱스를 읽기 전용 집합으로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Set<int>: 공공데이터 상세 조회가 성공한 원래 OCR 행 인덱스를 읽기 전용 집합으로 제공한다.
  Set<int> get verifiedMedicationScheduleIndexes =>
      Set.unmodifiable(_analyzedMedicationByScheduleIndex.keys.toSet());
  // 함수이름: unverifiedMedicationScheduleIndexes
  // 함수역할: 재검토 또는 재조회가 필요한 OCR 행 인덱스를 읽기 전용 집합으로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Set<int>: 재검토 또는 재조회가 필요한 OCR 행 인덱스를 읽기 전용 집합으로 제공한다.
  Set<int> get unverifiedMedicationScheduleIndexes =>
      Set.unmodifiable(_unverifiedMedicationScheduleIndexes);

  PrescriptionChangeRadar? _prescriptionChangeRadar;
  // 함수이름: prescriptionChangeRadar
  // 함수역할: 현재 처방과 이전 처방의 비교 결과를 제공하고 조회 전·실패 시 null 상태를 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - PrescriptionChangeRadar?: 현재 처방과 이전 처방의 비교 결과를 제공하고 조회 전·실패 시 null 상태를 유지한다.
  PrescriptionChangeRadar? get prescriptionChangeRadar =>
      _prescriptionChangeRadar;
  bool _isPrescriptionChangeLoading = false;
  // 함수이름: isPrescriptionChangeLoading
  // 함수역할: 결과 화면 뒤에서 진행하는 이전 처방 비교 요청의 로딩 상태를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 결과 화면 뒤에서 진행하는 이전 처방 비교 요청의 로딩 상태를 제공한다.
  bool get isPrescriptionChangeLoading => _isPrescriptionChangeLoading;

  List<MedicationDetail> _savedMedicationInfoList = [];
  // Function Name: savedMedicationInfoList
  // Description: Exposes an unmodifiable view of the currently loaded saved-medication details.
  // Parameters:
  // - None.
  // Returns:
  // - List<MedicationDetail>: An unmodifiable view of the currently loaded saved-medication details.
  List<MedicationDetail> get savedMedicationInfoList =>
      List.unmodifiable(_savedMedicationInfoList);

  List<MedicationSchedule> _todayMedicationScheduleList = [];
  // Function Name: todayMedicationScheduleList
  // Description: Exposes an unmodifiable list of the currently loaded medication courses for today.
  // Parameters:
  // - None.
  // Returns:
  // - List<MedicationSchedule>: An unmodifiable list of the currently loaded medication courses for today.
  List<MedicationSchedule> get todayMedicationScheduleList =>
      List.unmodifiable(_todayMedicationScheduleList);

  HealthRecommendation? _healthRecommendation;
  // 함수이름: healthRecommendation
  // 함수역할: 현재 복용 약 조합에 대한 최근 건강 관리 추천을 제공하고 조회 전에는 null을 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - HealthRecommendation?: 현재 복용 약 조합에 대한 최근 건강 관리 추천을 제공하고 조회 전에는 null을 유지한다.
  HealthRecommendation? get healthRecommendation => _healthRecommendation;

  // Function Name: todayMedicationProgress
  // Description: Counts every medication-slot dose in today's loaded schedules and separately totals slots marked completed.
  // Parameters:
  // - None.
  // Returns:
  // - TodayMedicationProgress: Counts every medication-slot dose in today's loaded schedules and separately totals slots marked completed.
  TodayMedicationProgress get todayMedicationProgress {
    var totalCount = 0;
    var completedCount = 0;

    for (final schedule in _todayMedicationScheduleList) {
      for (final slotKey in _slotKeysForSchedule(schedule)) {
        totalCount += 1;
        if (schedule.isSlotCompleted(slotKey)) {
          completedCount += 1;
        }
      }
    }

    return TodayMedicationProgress(
      completedCount: completedCount,
      totalCount: totalCount,
    );
  }

  final Map<String, MedicationAlarm> _medicationReminderSettings = {};
  // Function Name: medicationReminderSettings
  // Description: Exposes an unmodifiable slot-keyed map of the current medication alarm settings.
  // Parameters:
  // - None.
  // Returns:
  // - Map<String, MedicationAlarm>: An unmodifiable slot-keyed map of the current medication alarm settings.
  Map<String, MedicationAlarm> get medicationReminderSettings =>
      Map.unmodifiable(_medicationReminderSettings);
  static const List<String> _reminderSlotKeys = medicationScheduleSlotKeys;

  // 함수이름: MedBuddyViewModel
  // 함수역할: 환자 해시를 정규화하고 공유 API 클라이언트를 통해 기능별 Control과 알림·기기 사진 경계를 주입하거나 생성한다.
  // 매개변수:
  // - inputPrescription (InputPrescription?): 이미지 선택·로컬 OCR·분석 요청 Control
  // - checkMedicationDetail (CheckMedicationDetail?): 공공데이터 약 상세 조회 Control
  // - checkPrescriptionChange (CheckPrescriptionChange?): 이전 처방 비교 조회 Control
  // - checkSavedMedication (CheckSavedMedication?): 저장 약 등록·조회·삭제 Control
  // - checkSchedule (CheckSchedule?): 일정 조회와 완료 상태 변경 Control
  // - checkTodayMedicationInfo (CheckTodayMedicationInfo?): 오늘 복약 요약 조회 Control
  // - checkHealthRecommendation (CheckHealthRecommendation?): 건강 관리 추천 조회 Control
  // - setNotification (SetNotification?): 알림 설정 저장 및 플랫폼 등록 Control
  // - manageUserSetting (ManageUserSetting?): 사용자별 설정 영속화 Control
  // - manageAccount (ManageAccount?): 서버 계정 삭제와 로컬 캐시 정리 Control
  // - notificationService (NotificationService?): 플랫폼 로컬 알림 서비스
  // - manualMedicationImageStore (ManualMedicationImageStore?): 직접 등록 약 사진의 기기 저장 경계
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - apiClient (http.Client?): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
  // 반환값:
  // - MedBuddyViewModel: 초기화된 인스턴스.
  MedBuddyViewModel({
    InputPrescription? inputPrescription,
    CheckMedicationDetail? checkMedicationDetail,
    CheckPrescriptionChange? checkPrescriptionChange,
    CheckSavedMedication? checkSavedMedication,
    CheckSchedule? checkSchedule,
    CheckTodayMedicationInfo? checkTodayMedicationInfo,
    CheckHealthRecommendation? checkHealthRecommendation,
    SetNotification? setNotification,
    ManageUserSetting? manageUserSetting,
    ManageAccount? manageAccount,
    NotificationService? notificationService,
    ManualMedicationImageStore? manualMedicationImageStore,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? apiClient,
  }) : patientHash = PatientHash.normalizePatientHash(patientHash),
       _apiClient = apiClient ?? AuthenticatedApiClient(),
       _ownsApiClient = apiClient == null,
       notificationService =
           notificationService ?? NotificationService.instance,
       manualMedicationImageStore =
           manualMedicationImageStore ?? const ManualMedicationImageStore() {
    this.inputPrescription =
        inputPrescription ?? InputPrescription(client: _apiClient);
    this.checkMedicationDetail =
        checkMedicationDetail ?? CheckMedicationDetail(client: _apiClient);
    this.checkPrescriptionChange =
        checkPrescriptionChange ??
        CheckPrescriptionChange(
          patientHash: this.patientHash,
          client: _apiClient,
        );
    this.checkSavedMedication =
        checkSavedMedication ??
        CheckSavedMedication(patientHash: this.patientHash, client: _apiClient);
    this.checkSchedule =
        checkSchedule ??
        CheckSchedule(patientHash: this.patientHash, client: _apiClient);
    this.checkTodayMedicationInfo =
        checkTodayMedicationInfo ??
        CheckTodayMedicationInfo(
          patientHash: this.patientHash,
          client: _apiClient,
        );
    this.checkHealthRecommendation =
        checkHealthRecommendation ??
        CheckHealthRecommendation(
          patientHash: this.patientHash,
          client: _apiClient,
        );
    this.setNotification =
        setNotification ??
        SetNotification(
          patientHash: this.patientHash,
          client: _apiClient,
          notificationRegistrar: this.notificationService.registerNotification,
        );
    this.manageUserSetting =
        manageUserSetting ??
        ManageUserSetting(userHash: this.patientHash, client: _apiClient);
    this.manageAccount =
        manageAccount ??
        ManageAccount(userHash: this.patientHash, client: _apiClient);
  }
  // 함수이름: _notifyViewModelListeners
  // 함수역할: 기능별 ViewModel 확장에서 상태 변경을 화면에 알릴 수 있도록 ChangeNotifier 호출을 중계한다.
  // 매개변수:
  // - feature (MedBuddyFeature?): 변경 알림을 조회하거나 발행할 기능 영역
  // 반환값:
  // - 없음.
  void _notifyViewModelListeners([MedBuddyFeature? feature]) {
    if (_isDisposed) {
      return;
    }
    if (feature == null) {
      for (final updates in _featureUpdates.values) {
        updates.markChanged();
      }
    } else {
      _featureUpdates[feature]!.markChanged();
    }
    notifyListeners();
  }

  // 함수이름: dispose
  // 함수역할: 기능별 알림 채널과 처방 작업을 종료하고 모든 Control 및 직접 소유한 API 클라이언트만 정리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    for (final updates in _featureUpdates.values) {
      updates.dispose();
    }
    _cancelPrescriptionOperation();
    inputPrescription.dispose();
    checkMedicationDetail.dispose();
    checkPrescriptionChange.dispose();
    checkSavedMedication.dispose();
    checkSchedule.dispose();
    checkTodayMedicationInfo.dispose();
    checkHealthRecommendation.dispose();
    setNotification.dispose();
    manageUserSetting.dispose();
    if (_ownsApiClient) {
      _apiClient.close();
    }
    super.dispose();
  }
}
