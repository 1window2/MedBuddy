// File Name: medbuddy_view_model.dart
// Role: Composes independent patient-scoped feature owners and preserves the screen API.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../controls/check_health_recommendation_control.dart';
import '../controls/check_medication_detail_control.dart';
import '../entities/medication_match_review_entity.dart';
import '../controls/check_prescription_change_control.dart';
import '../controls/check_schedule_control.dart';
import '../controls/medication_history_control.dart';
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
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../entities/pill_identification_entity.dart';
import '../entities/prescription_change_entity.dart';
import '../entities/prescription_flow_entity.dart';
import '../entities/recognized_text_region_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/authenticated_api_client.dart';
import '../services/dose_outbox_store.dart';
import '../services/dose_sync_service.dart';
import '../services/dose_home_widget_service.dart';
import '../services/medication_reminder_background_service.dart';
import '../services/manual_medication_image_store.dart';
import '../services/notification_service.dart';
import 'medbuddy_feature_updates.dart';
import 'medbuddy_health_recommendation_view_model.dart';
import 'medbuddy_saved_medication_view_model.dart';
import 'medbuddy_schedule_view_model.dart';
import 'medbuddy_schedule_slot_policy.dart';
import 'medbuddy_reminder_view_model.dart';
import 'medbuddy_user_setting_view_model.dart';
import 'medbuddy_prescription_view_model.dart';
import 'saved_medication_batch_delete_result.dart';
export 'saved_medication_batch_delete_result.dart';

part 'medbuddy_saved_medication_facade.dart';

part 'medbuddy_application_flows.dart';

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

// Class Name: MedBuddyViewModel
// Role: Coordinates patient-scoped feature models and their legacy UI subscriptions.
// Responsibilities: Delegate prescription, schedule, saved-medication, reminder, settings and recommendation operations; synchronize dose and widget updates.
// Attributes: Feature models own their state; patientHash and the shared API client establish ownership; savedDoseRecords signals accepted history changes.
class MedBuddyViewModel extends ChangeNotifier {
  late final InputPrescription inputPrescription;
  late final MedBuddyPrescriptionViewModel _prescriptions;
  late final CheckMedicationDetail checkMedicationDetail;
  late final CheckPrescriptionChange checkPrescriptionChange;
  late final CheckSavedMedication checkSavedMedication;
  late final MedBuddySavedMedicationViewModel _savedMedications;
  late final CheckSchedule checkSchedule;
  late final MedBuddyScheduleViewModel _schedules;
  late final CheckTodayMedicationInfo checkTodayMedicationInfo;
  late final CheckHealthRecommendation checkHealthRecommendation;
  late final MedBuddyHealthRecommendationViewModel _healthRecommendations;
  late final SetNotification setNotification;
  late final MedBuddyReminderViewModel _reminders;
  late final ManageUserSetting manageUserSetting;
  late final MedBuddyUserSettingViewModel _settings;
  late final ManageAccount manageAccount;
  final NotificationService notificationService;
  final ManualMedicationImageStore manualMedicationImageStore;
  final String patientHash;
  final http.Client _apiClient;
  MedicationHistoryControl? _asNeededHistory;

  // Function Name: asNeededHistory
  // Description: Lazily creates the session-owned as-needed history controller and subscribes to accepted saves.
  // Parameters: None.
  // Returns: The same controller for subsequent accesses; pending intentions outlive individual screens.
  MedicationHistoryControl get asNeededHistory =>
      _asNeededHistory ??= MedicationHistoryControl(
        patientHash: patientHash,
        client: _apiClient,
      )..addListener(_onAsNeededHistoryChanged);

  // 서버가 이 계정의 복용 기록을 새로 받을 때마다 값이 바뀐다. 탭으로 열려 있는 복약 기록 화면은
  // 위에 열린 일정 화면에서 기록해도 다시 만들어지지 않으므로 이 신호로 다시 읽는다.
  final ValueNotifier<int> savedDoseRecords = ValueNotifier(0);
  int _seenAcceptedDoses = 0;
  int _seenAsNeededSaves = 0;
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

  // Function Name: prescriptionFlowState
  // Description: Exposes the prescription workflow stage used to choose the current screen.
  // Parameters: None.
  // Returns: The prescription feature's current flow state.
  PrescriptionFlowState get prescriptionFlowState =>
      _prescriptions.prescriptionFlowState;

  // Function Name: analysisProgressStep
  // Description: Exposes which analysis step is currently displayed.
  // Parameters: None.
  // Returns: The prescription feature's analysis progress step.
  AnalysisProgressStep get analysisProgressStep =>
      _prescriptions.analysisProgressStep;
  // 함수이름: completedMedicationAnalysisCount
  // 함수역할: 처방전 분석에서 완료된 약품 수를 하위 모델에서 읽는다.
  // 매개변수: 없음.
  // 반환값: 현재 분석의 완료 건수.
  int get completedMedicationAnalysisCount =>
      _prescriptions.completedMedicationAnalysisCount;
  // 함수이름: totalMedicationAnalysisCount
  // 함수역할: 처방전 분석의 전체 대상 약품 수를 제공한다.
  // 매개변수: 없음.
  // 반환값: 현재 분석의 대상 건수.
  int get totalMedicationAnalysisCount =>
      _prescriptions.totalMedicationAnalysisCount;

  // Function Name: savingMedicationIndex
  // Description: Identifies the analyzed medication currently being saved individually.
  // Parameters: None.
  // Returns: The source index, or null when no individual save is active.
  int? get savingMedicationIndex => _prescriptions.savingMedicationIndex;
  // Function Name: isMedicationSaving
  // Description: Reports whether an individual medication save is active.
  // Parameters: None.
  // Returns: The prescription feature's save-in-progress flag.
  bool get isMedicationSaving => _prescriptions.isMedicationSaving;

  // Function Name: completedMedicationSaveIndexes
  // Description: Exposes the analyzed medication indexes whose saves completed.
  // Parameters: None.
  // Returns: The prescription feature's completed-save index set.
  Set<int> get completedMedicationSaveIndexes =>
      _prescriptions.completedMedicationSaveIndexes;

  // Function Name: isAllMedicationSaving
  // Description: Reports whether the batch save of analyzed medications is active.
  // Parameters: None.
  // Returns: The prescription feature's batch-save flag.
  bool get isAllMedicationSaving => _prescriptions.isAllMedicationSaving;

  // Function Name: isSavedMedicationLoading
  // Description: Exposes whether the saved-medication list is being fetched.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether the saved-medication list is being fetched.
  bool get isSavedMedicationLoading => _savedMedications.isLoading;

  // Function Name: isTodayScheduleLoading
  // Description: Exposes the schedule feature's current loading state.
  // Parameters: None.
  // Returns: Whether today's schedules are being loaded.
  bool get isTodayScheduleLoading => _schedules.isTodayScheduleLoading;

  // Function Name: hasSettledTodaySchedule
  // Description: Distinguishes an initial unresolved schedule from a settled load.
  // Parameters: None.
  // Returns: The schedule feature's settled-state flag.
  bool get hasSettledTodaySchedule => _schedules.hasSettledTodaySchedule;

  // Function Name: hasTodayScheduleLoadError
  // Description: Exposes a failed current-day schedule load separately from loading.
  // Parameters: None.
  // Returns: Whether the schedule feature reports a load error.
  bool get hasTodayScheduleLoadError => _schedules.hasTodayScheduleLoadError;

  // Function Name: isHealthRecommendationLoading
  // Description: Reports whether the isolated health-recommendation request is active.
  // Parameters: None.
  // Returns: The recommendation feature's loading flag.
  bool get isHealthRecommendationLoading => _healthRecommendations.isLoading;

  // Function Name: hasNoActiveHealthMedications
  // Description: Exposes the server-confirmed absence of active medications for recommendations.
  // Parameters: None.
  // Returns: True only when the recommendation feature reports no eligible medications.
  bool get hasNoActiveHealthMedications =>
      _healthRecommendations.hasNoActiveMedications;

  // Function Name: healthRecommendationStatusMessage
  // Description: Keeps recommendation feedback independent of other features.
  // Parameters: None.
  // Returns: Current recommendation-only message.
  String get healthRecommendationStatusMessage =>
      _healthRecommendations.statusMessage;

  // Function Name: fetchHealthRecommendation
  // Description: Delegates to the isolated feature model using the current language.
  // Parameters: None.
  // Returns: Completion of the feature request.
  Future<void> fetchHealthRecommendation() =>
      _healthRecommendations.fetch(language: userSetting.language);

  // Function Name: _onHealthRecommendationChanged
  // Description: Bridges isolated state changes to existing feature subscribers.
  // Parameters: None.
  // Returns: None.
  void _onHealthRecommendationChanged() {
    _notifyViewModelListeners(MedBuddyFeature.healthRecommendation);
  }

  String _statusMessage = '';

  // Function Name: prescriptionStatusMessage
  // Description: Prevents unrelated feature feedback from replacing prescription guidance.
  // Parameters: None. Returns: Prescription-local message or initial guidance.
  String get prescriptionStatusMessage =>
      _prescriptions.statusMessage.isNotEmpty
      ? _prescriptions.statusMessage
      : _prescriptions.idlePrompt;

  // Function Name: reminderStatusMessage
  // Description: Exposes reminder feedback independently of background feature updates.
  // Parameters: None. Returns: Reminder-local feedback.
  String get reminderStatusMessage => _reminders.statusMessage;
  // Function Name: statusMessage
  // Description: Returns the latest shared feedback, falling back to localized prescription guidance.
  // Parameters: None.
  // Returns: The nonempty status message or the prescription idle prompt.
  String get statusMessage {
    if (_statusMessage.isNotEmpty) {
      return _statusMessage;
    }
    return _prescriptions.idlePrompt;
  }

  // Function Name: analysisErrorMessage
  // Description: Exposes the prescription feature's analysis failure message.
  // Parameters: None.
  // Returns: The current analysis error text, possibly empty.
  String get analysisErrorMessage => _prescriptions.analysisErrorMessage;
  // Function Name: canRetryPrescriptionAnalysis
  // Description: Reports whether the prescription feature permits another analysis attempt.
  // Parameters: None.
  // Returns: The current retry eligibility flag.
  bool get canRetryPrescriptionAnalysis =>
      _prescriptions.canRetryPrescriptionAnalysis;

  // Function Name: lastPrescriptionRawMedicationCount
  // Description: Exposes the number of medication rows received before parsing.
  // Parameters: None.
  // Returns: The raw count from the last prescription recognition.
  int get lastPrescriptionRawMedicationCount =>
      _prescriptions.lastPrescriptionRawMedicationCount;
  // Function Name: lastPrescriptionParsedMedicationCount
  // Description: Exposes the number of medication rows successfully parsed.
  // Parameters: None.
  // Returns: The parsed count from the last recognition.
  int get lastPrescriptionParsedMedicationCount =>
      _prescriptions.lastPrescriptionParsedMedicationCount;
  // Function Name: lastPrescriptionSkippedMedicationCount
  // Description: Exposes the number of recognition rows excluded during parsing.
  // Parameters: None.
  // Returns: The skipped count from the last recognition.
  int get lastPrescriptionSkippedMedicationCount =>
      _prescriptions.lastPrescriptionSkippedMedicationCount;

  // Function Name: correctedPrescriptionMedicationCount
  // Description: Exposes how many prescription medication names required correction.
  // Parameters: None.
  // Returns: The correction count maintained by the prescription feature.
  int get correctedPrescriptionMedicationCount =>
      _prescriptions.correctedPrescriptionMedicationCount;

  // Function Name: prescriptionRecognitionNotice
  // Description: Exposes localized guidance about the recognition result.
  // Parameters: None.
  // Returns: The prescription feature's recognition notice.
  String get prescriptionRecognitionNotice =>
      _prescriptions.prescriptionRecognitionNotice;

  // Function Name: userSetting
  // Description: Reads the settings feature's current account preferences.
  // Parameters: None.
  // Returns: The currently loaded UserSetting.
  UserSetting get userSetting => _settings.userSetting;
  // Function Name: _isEnglishSetting
  // Description: Checks the normalized language preference for English UI messages.
  // Parameters: None.
  // Returns: Whether the current setting selects English.
  bool get _isEnglishSetting => userSetting.isEnglish;

  // Function Name: recognizedMedicationScheduleList
  // Description: Exposes editable medication rows produced by prescription recognition.
  // Parameters: None.
  // Returns: The prescription feature's recognized schedule list.
  List<MedicationSchedule> get recognizedMedicationScheduleList =>
      _prescriptions.recognizedMedicationScheduleList;

  // Function Name: recognizedTextRegionList
  // Description: Exposes OCR text regions for the prescription preview overlay.
  // Parameters: None.
  // Returns: The recognized text region list.
  List<RecognizedTextRegion> get recognizedTextRegionList =>
      _prescriptions.recognizedTextRegionList;

  // Function Name: prescriptionPreviewImagePath
  // Description: Exposes the image path selected for the prescription preview.
  // Parameters: None.
  // Returns: The current preview path, possibly empty.
  String get prescriptionPreviewImagePath =>
      _prescriptions.prescriptionPreviewImagePath;

  // Function Name: analyzedMedicationList
  // Description: Exposes medication analysis results retained by the prescription feature.
  // Parameters: None.
  // Returns: The current analyzed medication list.
  List<AnalyzedMedication> get analyzedMedicationList =>
      _prescriptions.analyzedMedicationList;

  // Function Name: verifiedMedicationScheduleIndexes
  // Description: Exposes recognized-row indexes confirmed by medication lookup.
  // Parameters: None.
  // Returns: The prescription feature's verified index set.
  Set<int> get verifiedMedicationScheduleIndexes =>
      _prescriptions.verifiedMedicationScheduleIndexes;
  // 함수이름: medicationLookupStatuses
  // 함수역할: 처방전 각 행의 약품 조회 진행 상태를 제공한다.
  // 매개변수: 없음.
  // 반환값: 원래 행 인덱스를 키로 하는 조회 상태 맵.
  Map<int, MedicationLookupStatus> get medicationLookupStatuses =>
      _prescriptions.medicationLookupStatuses;
  // 함수이름: recognitionStage
  // 함수역할: 문자 인식과 약품 조회를 구분하는 현재 처리 단계를 제공한다.
  // 매개변수: 없음.
  // 반환값: 처방전 모델의 인식 단계.
  PrescriptionRecognitionStage get recognitionStage =>
      _prescriptions.recognitionStage;
  // Function Name: unverifiedMedicationScheduleIndexes
  // Description: Exposes recognized-row indexes still needing medication verification.
  // Parameters: None.
  // Returns: The prescription feature's unverified index set.
  Set<int> get unverifiedMedicationScheduleIndexes =>
      _prescriptions.unverifiedMedicationScheduleIndexes;
  // 함수이름: medicationMatchReviews
  // 함수역할: 처방전 행별로 사용자 확인이 필요한 약품 후보를 제공한다.
  // 매개변수: 없음.
  // 반환값: 행 인덱스별 후보 검토 정보.
  Map<int, MedicationMatchReview> get medicationMatchReviews =>
      _prescriptions.medicationMatchReviews;

  // 함수이름: confirmMedicationCandidate
  // 함수역할: 사용자가 선택한 약품 후보를 해당 처방전 행에 확정하도록 위임한다.
  // 매개변수: index: 원래 처방전 행 인덱스; detail: 선택한 약품 상세 정보.
  // 반환값: 없음; 검증과 상태 알림은 처방전 모델이 수행한다.
  void confirmMedicationCandidate(int index, MedicationDetail detail) =>
      _prescriptions.confirmMedicationCandidate(index, detail);

  // Function Name: prescriptionChangeRadar
  // Description: Exposes the latest comparison between the current and previous prescriptions.
  // Parameters: None.
  // Returns: The change radar, or null before a result is available.
  PrescriptionChangeRadar? get prescriptionChangeRadar =>
      _prescriptions.prescriptionChangeRadar;

  // Function Name: isPrescriptionChangeLoading
  // Description: Reports whether prescription comparison is in progress.
  // Parameters: None.
  // Returns: The prescription feature's comparison-loading flag.
  bool get isPrescriptionChangeLoading =>
      _prescriptions.isPrescriptionChangeLoading;

  // Function Name: savedMedicationInfoList
  // Description: Exposes an unmodifiable view of the currently loaded saved-medication details.
  // Parameters:
  // - None.
  // Returns:
  // - List<MedicationDetail>: An unmodifiable view of the currently loaded saved-medication details.
  List<MedicationDetail> get savedMedicationInfoList =>
      _savedMedications.medications;

  // Function Name: todayMedicationScheduleList
  // Description: Exposes today's schedule projection, including the dose-sync feature's pending changes.
  // Parameters: None.
  // Returns: The schedule feature's current medication list.
  List<MedicationSchedule> get todayMedicationScheduleList =>
      _schedules.todayMedicationScheduleList;

  // Function Name: healthRecommendation
  // Description: Exposes the latest recommendation for the active medication combination.
  // Parameters: None.
  // Returns: The recommendation, or null when none is available.
  HealthRecommendation? get healthRecommendation =>
      _healthRecommendations.recommendation;

  // Function Name: todayMedicationProgress
  // Description: Counts every medication-slot dose in today's loaded schedules and separately totals slots marked completed.
  // Parameters:
  // - None.
  // Returns:
  // - TodayMedicationProgress: Counts every medication-slot dose in today's loaded schedules and separately totals slots marked completed.
  TodayMedicationProgress get todayMedicationProgress {
    var totalCount = 0;
    var completedCount = 0;

    for (final schedule in todayMedicationScheduleList) {
      for (final slotKey in resolveScheduleSlotKeys(schedule)) {
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

  // Function Name: medicationReminderSettings
  // Description: Exposes reminder configuration indexed by its reminder key.
  // Parameters: None.
  // Returns: The reminder feature's current alarm map.
  Map<String, MedicationAlarm> get medicationReminderSettings =>
      _reminders.medicationReminderSettings;

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
        checkMedicationDetail ??
        CheckMedicationDetail(
          client: _apiClient,
          readSearchMode: () => userSetting.medicationSearchMode,
        );
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
    _settings = MedBuddyUserSettingViewModel(
      manageUserSetting: this.manageUserSetting,
      notificationService: this.notificationService,
      refreshMedicationOverview: refreshMedicationOverview,
      startTodayMedicationInfo: fetchTodayMedicationInfo,
      refreshMedicationSchedule: refreshMedicationSchedule,
      loadMedicationReminderSettings: loadMedicationReminderSettings,
      onChanged: () => _notifyViewModelListeners(MedBuddyFeature.userSetting),
      readEnglish: () => _isEnglishSetting,
    );
    _healthRecommendations = MedBuddyHealthRecommendationViewModel(
      this.checkHealthRecommendation,
    )..addListener(_onHealthRecommendationChanged);
    _schedules = MedBuddyScheduleViewModel(
      checkSchedule: this.checkSchedule,
      checkTodayMedicationInfo: this.checkTodayMedicationInfo,
      readDoseSync: () => doseSync,
      readEnglish: () => _isEnglishSetting,
      onChanged: _onScheduleChanged,
    );
    _reminders = MedBuddyReminderViewModel(
      setNotification: this.setNotification,
      notificationService: this.notificationService,
      patientHash: this.patientHash,
      readUserSetting: () => userSetting,
      readSchedules: () => todayMedicationScheduleList,
      scheduleIsFresh: () => _schedules.lastLoadSucceeded,
      loadScheduleWindow: this.checkSchedule.requestMedicationScheduleWindow,
      onChanged: _onReminderChanged,
    );
    _savedMedications = MedBuddySavedMedicationViewModel(
      checkSavedMedication: this.checkSavedMedication,
      checkMedicationDetail: this.checkMedicationDetail,
      manualMedicationImageStore: this.manualMedicationImageStore,
      patientHash: this.patientHash,
      readEnglishSetting: () => _isEnglishSetting,
      fetchTodayMedicationSchedule: fetchTodayMedicationSchedule,
      invalidateSchedule: () async {
        if (_isDisposed) return;
        _schedules.clear();
        await doseSync?.invalidateSchedule();
      },
      suspendSchedule: () async {
        if (_isDisposed) return null;
        _schedules.clear();
        return doseSync?.suspendSchedule();
      },
      restoreSchedule: (backup) async {
        if (_isDisposed) return;
        await doseSync?.restoreSchedule(
          backup is DoseScheduleBackup ? backup : null,
        );
        // 되돌린 일정을 화면에 다시 올린다. 연결이 없으면 기기에 되돌린 일정을 쓴다.
        await fetchTodayMedicationSchedule();
      },
      synchronizeReminders:
          _synchronizeMedicationReminderSchedulesIfScheduleIsFresh,
      onChanged: _onSavedMedicationChanged,
    );
    _prescriptions = MedBuddyPrescriptionViewModel(
      inputPrescription: this.inputPrescription,
      checkMedicationDetail: this.checkMedicationDetail,
      checkPrescriptionChange: this.checkPrescriptionChange,
      savedMedications: _savedMedications,
      fetchTodayMedicationSchedule: fetchTodayMedicationSchedule,
      synchronizeReminders:
          _synchronizeMedicationReminderSchedulesIfScheduleIsFresh,
      readEnglish: () => _isEnglishSetting,
      onChanged: _onPrescriptionChanged,
    );
    this.manageAccount =
        manageAccount ??
        ManageAccount(userHash: this.patientHash, client: _apiClient);
  }

  // 함수이름: _onScheduleChanged
  // 함수역할: 일정 갱신 신선도 캐시를 지우고 일정 기능 구독자에게 변경을 알린다. 종료된 모델은 무시한다.
  // 매개변수: message: 비어 있지 않으면 공통 상태 안내로 반영할 일정 메시지.
  // 반환값: 없음.
  void _onScheduleChanged(String message) {
    if (_isDisposed) return;
    _scheduleRefreshedAt = null;
    if (message.isNotEmpty) _statusMessage = message;
    _notifyViewModelListeners(MedBuddyFeature.schedule);
  }

  // Function Name: applyConfirmedTodaySchedules
  // Description: Applies a server-confirmed schedule list through the schedule feature.
  // Parameters: schedules: Confirmed current-day MedicationSchedule values.
  // Returns: None; schedule state and its subscribers are updated by the delegate.
  void applyConfirmedTodaySchedules(List<MedicationSchedule> schedules) =>
      _schedules.applyConfirmedTodaySchedules(schedules);
  // Function Name: fetchTodayMedicationSchedule
  // Description: Requests today's medication schedules through the schedule feature.
  // Parameters: None.
  // Returns: A Future completing when that feature finishes its load.
  Future<void> fetchTodayMedicationSchedule() =>
      _schedules.fetchTodayMedicationSchedule();
  // Function Name: fetchTodayMedicationInfo
  // Description: Requests today's medication summary through the schedule feature.
  // Parameters: None.
  // Returns: A Future completing when the summary request finishes.
  Future<void> fetchTodayMedicationInfo() =>
      _schedules.fetchTodayMedicationInfo();
  // Function Name: isMedicationDoseCompleted
  // Description: Checks the effective completion state of one scheduled dose.
  // Parameters: slotKey: Dose slot; schedule: Medication whose state is queried.
  // Returns: The completion state resolved by the schedule feature.
  bool isMedicationDoseCompleted(String slotKey, MedicationSchedule schedule) =>
      _schedules.isMedicationDoseCompleted(slotKey, schedule);
  // Function Name: slotKeysForSchedule
  // Description: Resolves the dose slots represented by a medication schedule.
  // Parameters: schedule: MedicationSchedule to inspect.
  // Returns: The schedule feature's ordered slot keys.
  List<String> slotKeysForSchedule(MedicationSchedule schedule) =>
      _schedules.slotKeysForSchedule(schedule);
  // Function Name: requestMedicationDoseStatusUpdate
  // Description: Requests a completion-state change for one medication in one slot.
  // Parameters: slotKey: Target slot; schedule: Target medication; medicationStatus: Desired completion state.
  // Returns: A Future containing the schedule feature's acceptance result.
  Future<bool> requestMedicationDoseStatusUpdate(
    String slotKey,
    MedicationSchedule schedule,
    bool medicationStatus,
  ) => _afterDoseChange(
    _schedules.requestMedicationDoseStatusUpdate(
      slotKey,
      schedule,
      medicationStatus,
    ),
  );
  // Function Name: requestMedicationSlotStatusUpdate
  // Description: Requests a completion-state change for all medications in a slot.
  // Parameters: slotKey: Target slot; medicationStatus: Desired state; expectedScheduleDate: Optional stale-day guard.
  // Returns: A Future containing the schedule feature's acceptance result.
  Future<bool> requestMedicationSlotStatusUpdate(
    String slotKey,
    bool medicationStatus, {
    String? expectedScheduleDate,
  }) => _afterDoseChange(
    _schedules.requestMedicationSlotStatusUpdate(
      slotKey,
      medicationStatus,
      expectedScheduleDate: expectedScheduleDate,
    ),
  );
  // Function Name: requestMedicationStatusUpdate
  // Description: Delegates a medication completion change with an optional explicit slot.
  // Parameters: medicationSchedule: Target medication; medicationStatus: Desired state; slotKey: Optional slot override.
  // Returns: A Future containing the schedule feature's acceptance result.
  Future<bool> requestMedicationStatusUpdate(
    MedicationSchedule medicationSchedule,
    bool medicationStatus, {
    String? slotKey,
  }) => _afterDoseChange(
    _schedules.requestMedicationStatusUpdate(
      medicationSchedule,
      medicationStatus,
      slotKey: slotKey,
    ),
  );
  // Function Name: _afterDoseChange
  // Description: Starts reminder reconciliation once a dose change is accepted. Today's reminder is otherwise left as it
  //   was until the next schedule refresh, so undoing an accidental Taken whose reminder was already cancelled would leave
  //   the slot without its reminder today.
  // Parameters: accepted: The schedule feature's pending acceptance result.
  // Returns: The same acceptance result; reconciliation is not awaited.
  Future<bool> _afterDoseChange(Future<bool> accepted) async {
    final result = await accepted;
    if (result && !_isDisposed) {
      unawaited(_reminders.synchronizeAfterDoseChange());
    }
    return result;
  }

  // Function Name: loadMedicationReminderSettings
  // Description: Loads reminder settings through their owning feature.
  // Parameters: notifyAfterLoad: Whether the feature should publish a change after loading.
  // Returns: A Future completing when the reminder load finishes.
  Future<void> loadMedicationReminderSettings({bool notifyAfterLoad = true}) =>
      _reminders.loadMedicationReminderSettings(
        notifyAfterLoad: notifyAfterLoad,
      );
  // Function Name: requestMedicationReminderSave
  // Description: Saves and schedules a medication reminder through the reminder feature.
  // Parameters: slotKey and slotTitle: Reminder identity and display label; hour/minute: Local alarm time; schedules: Reminder medications.
  // Returns: A Future containing the reminder feature's success result.
  Future<bool> requestMedicationReminderSave({
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<MedicationSchedule> schedules,
  }) => _reminders.requestMedicationReminderSave(
    slotKey: slotKey,
    slotTitle: slotTitle,
    hour: hour,
    minute: minute,
    schedules: schedules,
  );
  // Function Name: requestMedicationReminderCancel
  // Description: Cancels a slot reminder or a specific time within that slot.
  // Parameters: slotKey and slotTitle: Reminder identity and label; hour/minute: Optional targeted alarm time.
  // Returns: A Future containing the cancellation result.
  Future<bool> requestMedicationReminderCancel({
    required String slotKey,
    required String slotTitle,
    int? hour,
    int? minute,
  }) => _reminders.requestMedicationReminderCancel(
    slotKey: slotKey,
    slotTitle: slotTitle,
    hour: hour,
    minute: minute,
  );
  // Function Name: _onReminderChanged
  // Description: Bridges reminder-local feedback to compatibility listeners.
  // Parameters: message: Feature feedback. Returns: None.
  void _onReminderChanged(String message) {
    if (_isDisposed) return;
    if (message.isNotEmpty) _statusMessage = message;
    _notifyViewModelListeners(MedBuddyFeature.reminder);
  }

  // Function Name: _synchronizeMedicationReminderSchedulesIfScheduleIsFresh
  // Description: Reconciles local reminder schedules only when the schedule feature has fresh data.
  // Parameters: None.
  // Returns: A Future completing after the reminder feature's conditional synchronization.
  Future<void> _synchronizeMedicationReminderSchedulesIfScheduleIsFresh() =>
      _reminders.synchronizeIfFresh();
  // Function Name: loadUserSetting
  // Description: Loads account preferences through the settings feature.
  // Parameters: None.
  // Returns: A Future completing when settings loading finishes.
  Future<void> loadUserSetting() => _settings.loadUserSetting();
  // Function Name: saveUserSetting
  // Description: Saves account preferences through the settings feature.
  // Parameters: setting: Requested UserSetting value.
  // Returns: A Future containing the save result, including any reported failure.
  Future<UserSettingSaveResult> saveUserSetting(UserSetting setting) =>
      _settings.saveUserSetting(setting);
  // 함수이름: synchronizeDeviceLanguage
  // 함수역할: 기기 언어의 설정 반영을 설정 모델에 위임한다.
  // 매개변수: retryRemoteLookup: 원격 설정 조회 재시도 여부.
  // 반환값: 설정 모델이 보고한 동기화 결과.
  Future<bool> synchronizeDeviceLanguage({bool retryRemoteLookup = false}) =>
      _settings.synchronizeDeviceLanguage(retryRemoteLookup: retryRemoteLookup);
  // Function Name: requestCapturedPrescriptionImage
  // Description: Starts prescription recognition from a captured image.
  // Parameters: image: Captured XFile passed to the prescription feature.
  // Returns: A Future completing when the feature finishes processing the input.
  Future<void> requestCapturedPrescriptionImage(XFile image) =>
      _prescriptions.requestCapturedPrescriptionImage(image);
  // Function Name: requestPrescriptionImageFromGallery
  // Description: Starts the prescription feature's gallery image selection flow.
  // Parameters: None.
  // Returns: A Future completing after selection and any ensuing processing.
  Future<void> requestPrescriptionImageFromGallery() =>
      _prescriptions.requestPrescriptionImageFromGallery();
  // Function Name: updateRecognizedMedicationSchedule
  // Description: Replaces an editable prescription row through the prescription feature.
  // Parameters: scheduleIndex: Row index; medicationSchedule: Replacement row values.
  // Returns: None; the prescription feature validates and publishes the edit.
  void updateRecognizedMedicationSchedule(
    int scheduleIndex,
    MedicationSchedule medicationSchedule,
  ) => _prescriptions.updateRecognizedMedicationSchedule(
    scheduleIndex,
    medicationSchedule,
  );
  // Function Name: addRecognizedMedicationSchedule
  // Description: Adds an editable medication row to the prescription feature.
  // Parameters: medicationSchedule: New prescription row.
  // Returns: None; the prescription feature owns the resulting state change.
  void addRecognizedMedicationSchedule(MedicationSchedule medicationSchedule) =>
      _prescriptions.addRecognizedMedicationSchedule(medicationSchedule);
  // Function Name: returnToPrescriptionPreview
  // Description: Returns the prescription workflow to its image-preview stage.
  // Parameters: None.
  // Returns: None; the prescription feature applies the transition.
  void returnToPrescriptionPreview() =>
      _prescriptions.returnToPrescriptionPreview();
  // Function Name: requestPrescriptionAnalysis
  // Description: Starts analysis of the current prescription rows.
  // Parameters: None.
  // Returns: A Future completing after the prescription feature's analysis attempt.
  Future<void> requestPrescriptionAnalysis() =>
      _prescriptions.requestPrescriptionAnalysis();
  // Function Name: continueWithVerifiedMedicationAnalysis
  // Description: Continues analysis using only medication rows already verified.
  // Parameters: None.
  // Returns: Whether the prescription feature accepted the continuation.
  bool continueWithVerifiedMedicationAnalysis() =>
      _prescriptions.continueWithVerifiedMedicationAnalysis();
  // Function Name: showMedicationAnalysisResult
  // Description: Requests display of the current medication analysis results.
  // Parameters: None.
  // Returns: None; the prescription feature controls the screen transition.
  void showMedicationAnalysisResult() =>
      _prescriptions.showMedicationAnalysisResult();
  // Function Name: requestMedicationSave
  // Description: Saves one analyzed medication through the prescription feature.
  // Parameters: analyzedMedication: Result to save; medicationIndex: Its source row index.
  // Returns: A Future containing the individual save result.
  Future<bool> requestMedicationSave(
    AnalyzedMedication analyzedMedication,
    int medicationIndex,
  ) =>
      _prescriptions.requestMedicationSave(analyzedMedication, medicationIndex);
  // Function Name: requestAllAnalyzedMedicationSave
  // Description: Requests saving of all current analyzed medication results.
  // Parameters: None.
  // Returns: A Future containing the prescription feature's batch-save result.
  Future<bool> requestAllAnalyzedMedicationSave() =>
      _prescriptions.requestAllAnalyzedMedicationSave();
  // Function Name: clearAnalysisResult
  // Description: Clears the current prescription analysis and its workflow state.
  // Parameters: None.
  // Returns: None; the prescription feature publishes the reset.
  void clearAnalysisResult() => _prescriptions.clearAnalysisResult();
  // Function Name: _onPrescriptionChanged
  // Description: Bridges prescription-local feedback to compatibility listeners.
  // Parameters: message: Feature feedback. Returns: None.
  void _onPrescriptionChanged(String message) {
    if (_isDisposed) return;
    if (message.isNotEmpty) _statusMessage = message;
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  DoseSyncService? doseSync;

  // 함수이름: restoreSessionReminders
  // 함수역할: 중단된 로그아웃 뒤 저장된 일정 기간과 알림 설정으로 예약을 복원한다. 세션이 바뀌면 중단한다.
  // 매개변수: isCurrent: 복원 작업의 세션 소유권을 재확인하는 함수.
  // 반환값: 복원 완료 Future; 하위 저장소나 예약 오류는 전파한다.
  Future<void> restoreSessionReminders(bool Function() isCurrent) async {
    final window = await doseSync?.offlineWindow();
    if (_isDisposed || !isCurrent()) return;
    await _reminders.restoreAfterAbortedSignOut(
      isCurrent: () => !_isDisposed && isCurrent(),
      courses: window == null
          ? null
          : MedicationSchedule.fromScheduleJsonList(window['courses']),
      lastAllowedDate: window == null
          ? null
          : DateTime.tryParse('${window['end']}'),
    );
  }

  Future<void>? _scheduleRefresh;
  DateTime? _scheduleRefreshedAt;
  String? _widgetConfigurationSignature;

  // Function Name: _onSavedMedicationChanged
  // Description: Bridges owned feature state to legacy facade subscribers.
  // Parameters: message: Saved-medication feedback. Returns: None.
  void _onSavedMedicationChanged(String message) {
    if (_isDisposed) return;
    if (message.isNotEmpty) _statusMessage = message;
    _notifyViewModelListeners(MedBuddyFeature.savedMedication);
  }

  // 함수이름: attachDoseSync
  // 함수역할: 복용 동기화 서비스를 연결하고 비동기로 시작한다. 저장소 열기 실패는 일정 안내로 전달한다.
  // 매개변수: service: 운영 환경에서 사용하는 영속 큐 서비스; 단위 테스트에서는 연결을 생략할 수 있다.
  // 반환값: 없음; 서비스 시작을 기다리지 않는다.
  void attachDoseSync(DoseSyncService service) {
    doseSync = service;
    service.addListener(_onDoseSyncChanged);
    unawaited(
      service.start().catchError((Object _) {
        _statusMessage = _isEnglishSetting
            ? 'Could not open local dose storage.'
            : '기기 복용 기록 저장소를 열지 못했습니다.';
        _notifyViewModelListeners(MedBuddyFeature.schedule);
      }),
    );
  }

  // Function Name: _onDoseSyncChanged
  // Description: Projects queued dose changes into today's schedules and signals newly accepted server records.
  // Parameters: None.
  // Returns: None; ignores notifications after disposal or without an attached service.
  void _onDoseSyncChanged() {
    final sync = doseSync;
    if (_isDisposed || sync == null) return;
    if (sync.acceptedRevision != _seenAcceptedDoses) {
      _seenAcceptedDoses = sync.acceptedRevision;
      savedDoseRecords.value++;
    }
    _schedules.applyDoseProjection(
      sync.schedules,
      hasCurrentDayCache: sync.hasCache,
    );
  }

  // Function Name: _onAsNeededHistoryChanged
  // Description: Signals history subscribers when the as-needed controller accepts a new save.
  // Parameters: None.
  // Returns: None; unchanged revisions and disposed models are ignored.
  void _onAsNeededHistoryChanged() {
    final control = _asNeededHistory;
    if (_isDisposed || control == null) return;
    if (control.savedRevision != _seenAsNeededSaves) {
      _seenAsNeededSaves = control.savedRevision;
      savedDoseRecords.value++;
    }
  }

  // Function Name: _notifyViewModelListeners
  // Description: Notifies feature subscribers and publishes changed reminder/settings configuration to the home widget.
  // Parameters: feature: One feature to notify, or null for all features.
  // Returns: None; widget publication is asynchronous and failures permit a later retry.
  void _notifyViewModelListeners([MedBuddyFeature? feature]) {
    if (_isDisposed) {
      return;
    }
    if (doseSync != null &&
        (feature == MedBuddyFeature.userSetting ||
            feature == MedBuddyFeature.reminder)) {
      final configuration = {
        'language': userSetting.language,
        'source': userSetting.homeScheduleSource,
        'hide_names': userSetting.notificationDetailMode != 'full',
        'alarms': {
          for (final entry in medicationReminderSettings.entries)
            entry.key: entry.value.timeLabel,
        },
      };
      final signature = jsonEncode(configuration);
      if (_widgetConfigurationSignature != signature) {
        _widgetConfigurationSignature = signature;
        unawaited(
          DoseHomeWidget.publish(
                owner: patientHash,
                configuration: configuration,
              )
              .then((state) async {
                if (state?.view['source'] == 'patients') {
                  await DoseHomeWidget.refreshInBackground();
                }
                return state;
              })
              .catchError((_) {
                if (_widgetConfigurationSignature == signature) {
                  _widgetConfigurationSignature = null;
                }
                return null;
              }),
        );
      }
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

  // Function Name: dispose
  // Description: Disposes feature state, invalidates history ownership and releases subscriptions and owned resources.
  // Parameters: None.
  // Returns: None; repeated disposal is ignored, and an injected API client remains open.
  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _asNeededHistory?.removeListener(_onAsNeededHistoryChanged);
    _asNeededHistory?.invalidateSession();
    _asNeededHistory?.dispose();
    savedDoseRecords.dispose();
    _savedMedications.dispose();
    _schedules.dispose();
    _reminders.dispose();
    _settings.dispose();
    _healthRecommendations.removeListener(_onHealthRecommendationChanged);
    _healthRecommendations.dispose();
    doseSync?.removeListener(_onDoseSyncChanged);
    doseSync?.dispose();
    for (final updates in _featureUpdates.values) {
      updates.dispose();
    }
    _prescriptions.dispose();
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
