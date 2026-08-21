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
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../entities/prescription_change_entity.dart';
import '../entities/prescription_flow_entity.dart';
import '../entities/recognized_text_region_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/authenticated_api_client.dart';
import '../services/notification_service.dart';
import '../services/user_facing_error_message.dart';
import 'medbuddy_feature_updates.dart';

part 'medbuddy_prescription_view_model.dart';
part 'medbuddy_saved_medication_view_model.dart';
part 'medbuddy_schedule_view_model.dart';
part 'medbuddy_reminder_view_model.dart';
part 'medbuddy_health_recommendation_view_model.dart';
part 'medbuddy_user_setting_view_model.dart';

class TodayMedicationProgress {
  final int completedCount;
  final int totalCount;

  const TodayMedicationProgress({
    required this.completedCount,
    required this.totalCount,
  });
}

class SavedMedicationBatchDeleteResult {
  final int successCount;
  final int failureCount;

  const SavedMedicationBatchDeleteResult({
    required this.successCount,
    required this.failureCount,
  });

  int get totalCount => successCount + failureCount;
  bool get allSucceeded => totalCount > 0 && failureCount == 0;
  bool get hasFailures => failureCount > 0;
}

// 파일명: medbuddy_view_model.dart
// 역할: 화면 상태와 컨트롤 계층을 연결하는 앱 전역 ViewModel을 정의한다.

// 클래스명: MedBuddyViewModel
// 역할: 처방전 인식, 약품 분석, 복약 정보 저장, 일정 조회, 설정 저장 흐름을 관리한다.
// 주요 책임:
// - 각 Control 객체의 API 호출 결과를 화면 상태로 변환한다.
// - 처방전 분석 흐름의 단계별 상태를 유지한다.
// - 저장된 복약 정보와 오늘의 복약 일정을 캐시한다.
// - 사용자 설정을 불러오고 변경 사항을 화면에 반영한다.
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
  final String patientHash;
  final http.Client _apiClient;
  final bool _ownsApiClient;
  bool _isDisposed = false;
  final Map<MedBuddyFeature, MedBuddyFeatureUpdates> _featureUpdates = {
    for (final feature in MedBuddyFeature.values)
      feature: MedBuddyFeatureUpdates(),
  };

  MedBuddyFeatureUpdates updatesFor(MedBuddyFeature feature) {
    return _featureUpdates[feature]!;
  }

  PrescriptionFlowState _prescriptionFlowState = PrescriptionFlowState.idle;
  PrescriptionFlowState get prescriptionFlowState => _prescriptionFlowState;
  int _prescriptionOperationId = 0;

  AnalysisProgressStep _analysisProgressStep =
      AnalysisProgressStep.prescriptionRecognition;
  AnalysisProgressStep get analysisProgressStep => _analysisProgressStep;

  bool get isPrescriptionAnalyzing {
    return _prescriptionFlowState ==
            PrescriptionFlowState.recognizingPrescription ||
        _prescriptionFlowState == PrescriptionFlowState.analyzingMedication;
  }

  bool get isLoading => isPrescriptionAnalyzing;

  int? _savingMedicationIndex;
  int? get savingMedicationIndex => _savingMedicationIndex;
  bool get isMedicationSaving => _savingMedicationIndex != null;

  final Set<int> _completedMedicationSaveIndexes = {};
  Set<int> get completedMedicationSaveIndexes =>
      Set.unmodifiable(_completedMedicationSaveIndexes);

  bool _isAllMedicationSaving = false;
  bool get isAllMedicationSaving => _isAllMedicationSaving;

  bool _isSavedMedicationLoading = false;
  bool get isSavedMedicationLoading => _isSavedMedicationLoading;

  bool _isTodayScheduleLoading = false;
  bool get isTodayScheduleLoading => _isTodayScheduleLoading;
  bool _hasTodayScheduleLoadError = false;
  bool get hasTodayScheduleLoadError => _hasTodayScheduleLoadError;
  bool _lastTodayScheduleLoadSucceeded = false;
  int _todayScheduleEpoch = 0;
  int _todayScheduleLoadCount = 0;

  bool _isHealthRecommendationLoading = false;
  bool get isHealthRecommendationLoading => _isHealthRecommendationLoading;

  String _statusMessage = '처방전을 촬영하거나 이미지를 선택해주세요.';
  String get statusMessage => _statusMessage;

  String _analysisErrorMessage = '';
  String get analysisErrorMessage => _analysisErrorMessage;
  bool get canRetryPrescriptionAnalysis =>
      _prescriptionFlowState == PrescriptionFlowState.analysisFailed &&
      _analysisProgressStep != AnalysisProgressStep.prescriptionRecognition &&
      _recognizedMedicationScheduleList.isNotEmpty;

  int _lastPrescriptionRawMedicationCount = 0;
  int _lastPrescriptionParsedMedicationCount = 0;
  int _lastPrescriptionSkippedMedicationCount = 0;
  int get lastPrescriptionRawMedicationCount =>
      _lastPrescriptionRawMedicationCount;
  int get lastPrescriptionParsedMedicationCount =>
      _lastPrescriptionParsedMedicationCount;
  int get lastPrescriptionSkippedMedicationCount =>
      _lastPrescriptionSkippedMedicationCount;

  int get correctedPrescriptionMedicationCount {
    return _recognizedMedicationScheduleList
        .where((schedule) => schedule.hasNameCorrection)
        .length;
  }

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
  UserSetting get userSetting => _userSetting;
  bool get _isEnglishSetting =>
      userSetting.language.trim().toLowerCase().startsWith('en');

  List<MedicationSchedule> _recognizedMedicationScheduleList = [];
  List<MedicationSchedule> get recognizedMedicationScheduleList =>
      List.unmodifiable(_recognizedMedicationScheduleList);
  List<RecognizedTextRegion> _recognizedTextRegionList = [];
  List<RecognizedTextRegion> get recognizedTextRegionList =>
      List.unmodifiable(_recognizedTextRegionList);
  String _prescriptionPreviewImagePath = '';
  String get prescriptionPreviewImagePath => _prescriptionPreviewImagePath;

  List<MedicationSchedule> get medicationScheduleList =>
      recognizedMedicationScheduleList;

  List<AnalyzedMedication> _analyzedMedicationList = [];
  List<AnalyzedMedication> get analyzedMedicationList =>
      List.unmodifiable(_analyzedMedicationList);

  PrescriptionChangeRadar? _prescriptionChangeRadar;
  PrescriptionChangeRadar? get prescriptionChangeRadar =>
      _prescriptionChangeRadar;
  bool _isPrescriptionChangeLoading = false;
  bool get isPrescriptionChangeLoading => _isPrescriptionChangeLoading;

  List<MedicationDetail> _savedMedicationInfoList = [];
  List<MedicationDetail> get savedMedicationInfoList =>
      List.unmodifiable(_savedMedicationInfoList);

  List<MedicationSchedule> _todayMedicationScheduleList = [];
  List<MedicationSchedule> get todayMedicationScheduleList =>
      List.unmodifiable(_todayMedicationScheduleList);

  HealthRecommendation? _healthRecommendation;
  HealthRecommendation? get healthRecommendation => _healthRecommendation;

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
  Map<String, MedicationAlarm> get medicationReminderSettings =>
      Map.unmodifiable(_medicationReminderSettings);
  static const List<String> _reminderSlotKeys = medicationScheduleSlotKeys;

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
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? apiClient,
  }) : patientHash = PatientHash.normalizePatientHash(patientHash),
       _apiClient = apiClient ?? AuthenticatedApiClient(),
       _ownsApiClient = apiClient == null,
       notificationService =
           notificationService ?? NotificationService.instance {
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
    this.manageAccount = manageAccount ?? ManageAccount(client: _apiClient);
  }
  // 함수명: _notifyViewModelListeners
  // 함수역할:
  // - 기능별 ViewModel 확장에서 상태 변경을 화면에 알릴 수 있도록 ChangeNotifier 호출을 중계한다.
  // 반환값:
  // - 없음
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
