// File Name: medbuddy_view_model.dart
// Role: Composes independent patient-scoped feature owners and preserves the screen API.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

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
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../entities/pill_identification_entity.dart';
import '../entities/prescription_change_entity.dart';
import '../entities/prescription_flow_entity.dart';
import '../entities/recognized_text_region_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/authenticated_api_client.dart';
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

  PrescriptionFlowState get prescriptionFlowState =>
      _prescriptions.prescriptionFlowState;

  AnalysisProgressStep get analysisProgressStep =>
      _prescriptions.analysisProgressStep;

  bool get isPrescriptionAnalyzing => _prescriptions.isPrescriptionAnalyzing;

  bool get isLoading => _prescriptions.isLoading;

  int? get savingMedicationIndex => _prescriptions.savingMedicationIndex;
  bool get isMedicationSaving => _prescriptions.isMedicationSaving;

  Set<int> get completedMedicationSaveIndexes =>
      _prescriptions.completedMedicationSaveIndexes;

  bool get isAllMedicationSaving => _prescriptions.isAllMedicationSaving;

  // Function Name: isSavedMedicationLoading
  // Description: Exposes whether the saved-medication list is being fetched.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether the saved-medication list is being fetched.
  bool get isSavedMedicationLoading => _savedMedications.isLoading;

  bool get isTodayScheduleLoading => _schedules.isTodayScheduleLoading;

  bool get hasTodayScheduleLoadError => _schedules.hasTodayScheduleLoadError;

  // 함수이름: isHealthRecommendationLoading
  // 함수역할: 건강 관리 추천 조회의 진행 여부를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 건강 관리 추천 조회의 진행 여부를 제공한다.
  bool get isHealthRecommendationLoading => _healthRecommendations.isLoading;

  // 함수이름: hasNoActiveHealthMedications
  // 함수역할: 서버에서 확인된 건강 추천 대상 약 없음 상태를 제공한다. 매개변수: 없음. 반환값: 대상 약 없음 여부.
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
      : (_isEnglishSetting
            ? 'Take a prescription photo or choose an image.'
            : '처방전을 촬영하거나 이미지를 선택해주세요.');

  // Function Name: reminderStatusMessage
  // Description: Exposes reminder feedback independently of background feature updates.
  // Parameters: None. Returns: Reminder-local feedback.
  String get reminderStatusMessage => _reminders.statusMessage;
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

  String get analysisErrorMessage => _prescriptions.analysisErrorMessage;
  bool get canRetryPrescriptionAnalysis =>
      _prescriptions.canRetryPrescriptionAnalysis;

  int get lastPrescriptionRawMedicationCount =>
      _prescriptions.lastPrescriptionRawMedicationCount;
  int get lastPrescriptionParsedMedicationCount =>
      _prescriptions.lastPrescriptionParsedMedicationCount;
  int get lastPrescriptionSkippedMedicationCount =>
      _prescriptions.lastPrescriptionSkippedMedicationCount;

  int get correctedPrescriptionMedicationCount =>
      _prescriptions.correctedPrescriptionMedicationCount;

  String get prescriptionRecognitionNotice =>
      _prescriptions.prescriptionRecognitionNotice;

  UserSetting get userSetting => _settings.userSetting;
  // 함수이름: _isEnglishSetting
  // 함수역할: 사용자 언어 코드를 정규화해 영어 계열 표시를 선택해야 하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 사용자 언어 코드를 정규화해 영어 계열 표시를 선택해야 하는지 확인한다.
  bool get _isEnglishSetting =>
      userSetting.language.trim().toLowerCase().startsWith('en');

  List<MedicationSchedule> get recognizedMedicationScheduleList =>
      _prescriptions.recognizedMedicationScheduleList;

  List<RecognizedTextRegion> get recognizedTextRegionList =>
      _prescriptions.recognizedTextRegionList;

  String get prescriptionPreviewImagePath =>
      _prescriptions.prescriptionPreviewImagePath;

  List<MedicationSchedule> get medicationScheduleList =>
      _prescriptions.medicationScheduleList;

  List<AnalyzedMedication> get analyzedMedicationList =>
      _prescriptions.analyzedMedicationList;

  Set<int> get verifiedMedicationScheduleIndexes =>
      _prescriptions.verifiedMedicationScheduleIndexes;
  Set<int> get unverifiedMedicationScheduleIndexes =>
      _prescriptions.unverifiedMedicationScheduleIndexes;

  PrescriptionChangeRadar? get prescriptionChangeRadar =>
      _prescriptions.prescriptionChangeRadar;

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

  List<MedicationSchedule> get todayMedicationScheduleList =>
      _schedules.todayMedicationScheduleList;

  // 함수이름: healthRecommendation
  // 함수역할: 현재 복용 약 조합에 대한 최근 건강 관리 추천을 제공하고 조회 전에는 null을 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - HealthRecommendation?: 현재 복용 약 조합에 대한 최근 건강 관리 추천을 제공하고 조회 전에는 null을 유지한다.
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
    _settings = MedBuddyUserSettingViewModel(
      manageUserSetting: this.manageUserSetting,
      notificationService: this.notificationService,
      refreshMedicationOverview: refreshMedicationOverview,
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
      onChanged: _onReminderChanged,
    );
    _savedMedications = MedBuddySavedMedicationViewModel(
      checkSavedMedication: this.checkSavedMedication,
      checkMedicationDetail: this.checkMedicationDetail,
      manualMedicationImageStore: this.manualMedicationImageStore,
      patientHash: this.patientHash,
      readEnglishSetting: () => _isEnglishSetting,
      fetchTodayMedicationSchedule: fetchTodayMedicationSchedule,
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

  // Function Name: _onScheduleChanged
  // Description: Bridges isolated schedule state to existing listeners.
  // Parameters: message: Schedule feedback. Returns: None.
  void _onScheduleChanged(String message) {
    if (_isDisposed) return;
    _scheduleRefreshedAt = null;
    if (message.isNotEmpty) _statusMessage = message;
    _notifyViewModelListeners(MedBuddyFeature.schedule);
  }

  // Function Name: applyConfirmedTodaySchedules
  // Description: Delegates to the schedule feature.
  // Parameters: As declared in the schedule operation. Returns: Its result.
  void applyConfirmedTodaySchedules(List<MedicationSchedule> schedules) =>
      _schedules.applyConfirmedTodaySchedules(schedules);
  // Function Name: fetchTodayMedicationSchedule
  // Description: Delegates to the schedule feature.
  // Parameters: As declared in the schedule operation. Returns: Its result.
  Future<void> fetchTodayMedicationSchedule() =>
      _schedules.fetchTodayMedicationSchedule();
  // Function Name: fetchTodayMedicationInfo
  // Description: Delegates to the schedule feature.
  // Parameters: As declared in the schedule operation. Returns: Its result.
  Future<void> fetchTodayMedicationInfo() =>
      _schedules.fetchTodayMedicationInfo();
  // Function Name: isMedicationDoseCompleted
  // Description: Delegates to the schedule feature.
  // Parameters: As declared in the schedule operation. Returns: Its result.
  bool isMedicationDoseCompleted(String slotKey, MedicationSchedule schedule) =>
      _schedules.isMedicationDoseCompleted(slotKey, schedule);
  // Function Name: slotKeysForSchedule
  // Description: Delegates to the schedule feature.
  // Parameters: As declared in the schedule operation. Returns: Its result.
  List<String> slotKeysForSchedule(MedicationSchedule schedule) =>
      _schedules.slotKeysForSchedule(schedule);
  // Function Name: requestMedicationDoseStatusUpdate
  // Description: Delegates to the schedule feature.
  // Parameters: As declared in the schedule operation. Returns: Its result.
  Future<bool> requestMedicationDoseStatusUpdate(
    String slotKey,
    MedicationSchedule schedule,
    bool medicationStatus,
  ) => _schedules.requestMedicationDoseStatusUpdate(
    slotKey,
    schedule,
    medicationStatus,
  );
  // Function Name: requestMedicationSlotStatusUpdate
  // Description: Delegates to the schedule feature.
  // Parameters: As declared in the schedule operation. Returns: Its result.
  Future<bool> requestMedicationSlotStatusUpdate(
    String slotKey,
    bool medicationStatus, {
    String? expectedScheduleDate,
  }) => _schedules.requestMedicationSlotStatusUpdate(
    slotKey,
    medicationStatus,
    expectedScheduleDate: expectedScheduleDate,
  );
  // Function Name: requestMedicationStatusUpdate
  // Description: Delegates to the schedule feature.
  // Parameters: As declared in the schedule operation. Returns: Its result.
  Future<bool> requestMedicationStatusUpdate(
    MedicationSchedule medicationSchedule,
    bool medicationStatus, {
    String? slotKey,
  }) => _schedules.requestMedicationStatusUpdate(
    medicationSchedule,
    medicationStatus,
    slotKey: slotKey,
  );
  // Function Name: loadMedicationReminderSettings
  // Description: Delegates to isolated reminder state.
  // Parameters: As declared by the operation. Returns: Its result.
  Future<void> loadMedicationReminderSettings({bool notifyAfterLoad = true}) =>
      _reminders.loadMedicationReminderSettings(
        notifyAfterLoad: notifyAfterLoad,
      );
  // Function Name: requestMedicationReminderSave
  // Description: Delegates to isolated reminder state.
  // Parameters: As declared by the operation. Returns: Its result.
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
  // Description: Delegates to isolated reminder state.
  // Parameters: As declared by the operation. Returns: Its result.
  Future<bool> requestMedicationReminderCancel({
    required String slotKey,
    required String slotTitle,
  }) => _reminders.requestMedicationReminderCancel(
    slotKey: slotKey,
    slotTitle: slotTitle,
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
  // Description: Coordinates explicit reminder reconciliation after fresh schedule reads.
  // Parameters: None. Returns: Completion.
  Future<void> _synchronizeMedicationReminderSchedulesIfScheduleIsFresh() =>
      _reminders.synchronizeIfFresh();
  // Function Name: loadUserSetting
  // Description: Delegates settings operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
  Future<void> loadUserSetting() => _settings.loadUserSetting();
  // Function Name: requestUserSettingSave
  // Description: Delegates settings operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
  Future<UserSettingSaveResult> requestUserSettingSave({
    required String fontSizeOption,
    required String readingSpeedOption,
    required String language,
    String? languageMode,
    String? timeFormat,
    String? homeScheduleSource,
    bool? medicationNotificationsEnabled,
    bool? caregiverNotificationsEnabled,
    bool? chatNotificationsEnabled,
    String? notificationDetailMode,
    String? defaultMorningTime,
    String? defaultLunchTime,
    String? defaultEveningTime,
    String? defaultBedtime,
  }) => _settings.requestUserSettingSave(
    fontSizeOption: fontSizeOption,
    readingSpeedOption: readingSpeedOption,
    language: language,
    languageMode: languageMode,
    timeFormat: timeFormat,
    homeScheduleSource: homeScheduleSource,
    medicationNotificationsEnabled: medicationNotificationsEnabled,
    caregiverNotificationsEnabled: caregiverNotificationsEnabled,
    chatNotificationsEnabled: chatNotificationsEnabled,
    notificationDetailMode: notificationDetailMode,
    defaultMorningTime: defaultMorningTime,
    defaultLunchTime: defaultLunchTime,
    defaultEveningTime: defaultEveningTime,
    defaultBedtime: defaultBedtime,
  );
  // Function Name: requestCapturedPrescriptionImage
  // Description: Delegates prescription operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
  Future<void> requestCapturedPrescriptionImage(XFile image) =>
      _prescriptions.requestCapturedPrescriptionImage(image);
  // Function Name: requestPrescriptionImageFromGallery
  // Description: Delegates prescription operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
  Future<void> requestPrescriptionImageFromGallery() =>
      _prescriptions.requestPrescriptionImageFromGallery();
  // Function Name: updateRecognizedMedicationSchedule
  // Description: Delegates prescription operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
  void updateRecognizedMedicationSchedule(
    int scheduleIndex,
    MedicationSchedule medicationSchedule,
  ) => _prescriptions.updateRecognizedMedicationSchedule(
    scheduleIndex,
    medicationSchedule,
  );
  // Function Name: addRecognizedMedicationSchedule
  // Description: Delegates prescription operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
  void addRecognizedMedicationSchedule(MedicationSchedule medicationSchedule) =>
      _prescriptions.addRecognizedMedicationSchedule(medicationSchedule);
  // Function Name: returnToPrescriptionPreview
  // Description: Delegates prescription operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
  void returnToPrescriptionPreview() =>
      _prescriptions.returnToPrescriptionPreview();
  // Function Name: requestPrescriptionAnalysis
  // Description: Delegates prescription operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
  Future<void> requestPrescriptionAnalysis() =>
      _prescriptions.requestPrescriptionAnalysis();
  // Function Name: continueWithVerifiedMedicationAnalysis
  // Description: Delegates prescription operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
  bool continueWithVerifiedMedicationAnalysis() =>
      _prescriptions.continueWithVerifiedMedicationAnalysis();
  // Function Name: showMedicationAnalysisResult
  // Description: Delegates prescription operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
  void showMedicationAnalysisResult() =>
      _prescriptions.showMedicationAnalysisResult();
  // Function Name: requestMedicationSave
  // Description: Delegates prescription operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
  Future<bool> requestMedicationSave(
    AnalyzedMedication analyzedMedication,
    int medicationIndex,
  ) =>
      _prescriptions.requestMedicationSave(analyzedMedication, medicationIndex);
  // Function Name: requestAllAnalyzedMedicationSave
  // Description: Delegates prescription operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
  Future<bool> requestAllAnalyzedMedicationSave() =>
      _prescriptions.requestAllAnalyzedMedicationSave();
  // Function Name: clearAnalysisResult
  // Description: Delegates prescription operations to their state owner.
  // Parameters: As declared by the operation. Returns: Its result.
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

  // Production injects a durable queue; isolated view-model tests may omit it.
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

  void _onDoseSyncChanged() {
    final sync = doseSync;
    if (_isDisposed || sync == null) return;
    _schedules.applyDoseProjection(sync.schedules);
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
