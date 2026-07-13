import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../controls/check_health_recommendation_control.dart';
import '../controls/check_medication_detail_control.dart';
import '../controls/check_schedule_control.dart';
import '../controls/check_saved_medication_control.dart';
import '../controls/check_today_medication_info_control.dart';
import '../controls/input_prescription_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../controls/set_notification_control.dart';
import '../entities/analyzed_medication_entity.dart';
import '../entities/health_recommendation_entity.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../entities/prescription_flow_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/medication_notification_service.dart';

class TodayMedicationProgress {
  final int completedCount;
  final int totalCount;

  const TodayMedicationProgress({
    required this.completedCount,
    required this.totalCount,
  });
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
  late final PrescriptionAnalysisControl prescriptionAnalysisControl;
  late final CheckMedicationDetail checkMedicationDetail;
  late final CheckSavedMedication checkSavedMedication;
  late final CheckSchedule checkSchedule;
  late final CheckTodayMedicationInfo checkTodayMedicationInfo;
  late final CheckHealthRecommendation checkHealthRecommendation;
  late final SetNotification setNotification;
  late final ManageUserSetting manageUserSetting;
  final MedicationNotificationService notificationService;
  final http.Client _apiClient;
  final bool _ownsApiClient;
  CheckSavedMedication? _scopedCheckSavedMedication;
  CheckSchedule? _scopedCheckSchedule;
  CheckTodayMedicationInfo? _scopedCheckTodayMedicationInfo;
  CheckHealthRecommendation? _scopedCheckHealthRecommendation;
  SetNotification? _scopedSetNotification;

  String _medicationPatientHash = PatientHash.defaultPatientHash;
  String? _medicationUserHash;
  String _medicationRole = 'patient';
  int _medicationScopeRevision = 0;
  String get medicationPatientHash => _medicationPatientHash;
  String? get medicationUserHash => _medicationUserHash;
  String get medicationRole => _medicationRole;

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
  bool _lastTodayScheduleLoadSucceeded = false;

  bool _isHealthRecommendationLoading = false;
  bool get isHealthRecommendationLoading => _isHealthRecommendationLoading;

  bool _isUserSettingLoading = false;
  bool get isUserSettingLoading => _isUserSettingLoading;

  String _statusMessage = '처방전을 촬영하거나 이미지를 선택해주세요.';
  String get statusMessage => _statusMessage;

  String _analysisErrorMessage = '';
  String get analysisErrorMessage => _analysisErrorMessage;

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
  UserSetting get userSetting =>
      manageUserSetting.requestUserSetting(_userSetting);
  bool get _isEnglishSetting =>
      userSetting.language.trim().toLowerCase().startsWith('en');

  List<MedicationSchedule> _recognizedMedicationScheduleList = [];
  List<MedicationSchedule> get recognizedMedicationScheduleList =>
      List.unmodifiable(_recognizedMedicationScheduleList);

  List<MedicationSchedule> get medicationScheduleList =>
      recognizedMedicationScheduleList;

  List<AnalyzedMedication> _analyzedMedicationList = [];
  List<AnalyzedMedication> get analyzedMedicationList =>
      List.unmodifiable(_analyzedMedicationList);

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
    PrescriptionAnalysisControl? prescriptionAnalysisControl,
    CheckMedicationDetail? checkMedicationDetail,
    CheckSavedMedication? checkSavedMedication,
    CheckSchedule? checkSchedule,
    CheckTodayMedicationInfo? checkTodayMedicationInfo,
    CheckHealthRecommendation? checkHealthRecommendation,
    SetNotification? setNotification,
    ManageUserSetting? manageUserSetting,
    MedicationNotificationService? notificationService,
    http.Client? apiClient,
  })  : _apiClient = apiClient ?? http.Client(),
        _ownsApiClient = apiClient == null,
        notificationService =
            notificationService ?? MedicationNotificationService.instance {
    this.prescriptionAnalysisControl = prescriptionAnalysisControl ??
        PrescriptionAnalysisControl(client: _apiClient);
    this.checkMedicationDetail =
        checkMedicationDetail ?? CheckMedicationDetail(client: _apiClient);
    this.checkSavedMedication =
        checkSavedMedication ?? CheckSavedMedication(client: _apiClient);
    this.checkSchedule = checkSchedule ?? CheckSchedule(client: _apiClient);
    this.checkTodayMedicationInfo = checkTodayMedicationInfo ??
        CheckTodayMedicationInfo(client: _apiClient);
    this.checkHealthRecommendation = checkHealthRecommendation ??
        CheckHealthRecommendation(client: _apiClient);
    this.setNotification =
        setNotification ?? SetNotification(client: _apiClient);
    this.manageUserSetting =
        manageUserSetting ?? ManageUserSetting(client: _apiClient);
  }

  void setMedicationAccessScope({
    required String patientHash,
    String? userHash,
    String role = 'patient',
  }) {
    final normalizedPatientHash = PatientHash.normalizePatientHash(patientHash);
    final normalizedUserHash = userHash == null || userHash.trim().isEmpty
        ? null
        : PatientHash.normalizePatientHash(userHash);
    final requestedRole =
        role.trim().isEmpty ? 'patient' : role.trim().toLowerCase();
    final normalizedRole =
        requestedRole == 'caregiver' ? 'guardian' : requestedRole;
    if (normalizedRole != 'patient' && normalizedRole != 'guardian') {
      throw ArgumentError.value(
        role,
        'role',
        'Only patient and guardian medication access roles are supported.',
      );
    }
    if (normalizedRole == 'guardian' && normalizedUserHash == null) {
      throw ArgumentError(
        'userHash is required for guardian medication access.',
      );
    }
    if (normalizedRole == 'patient' &&
        normalizedUserHash != null &&
        normalizedUserHash != normalizedPatientHash) {
      throw ArgumentError(
        'Patient medication access cannot target another patient hash.',
      );
    }

    if (_medicationPatientHash == normalizedPatientHash &&
        _medicationUserHash == normalizedUserHash &&
        _medicationRole == normalizedRole) {
      return;
    }

    _medicationPatientHash = normalizedPatientHash;
    _medicationUserHash = normalizedUserHash;
    _medicationRole = normalizedRole;
    _medicationScopeRevision += 1;
    _rebuildMedicationScopeControls();
    _savedMedicationInfoList = [];
    _todayMedicationScheduleList = [];
    _healthRecommendation = null;
    _medicationReminderSettings.clear();
    _completedMedicationSaveIndexes.clear();
    _savingMedicationIndex = null;
    _isAllMedicationSaving = false;
    _isSavedMedicationLoading = false;
    _isTodayScheduleLoading = false;
    _isHealthRecommendationLoading = false;
    _lastTodayScheduleLoadSucceeded = false;
    notifyListeners();
  }

  // 함수명: loadUserSetting
  // 함수역할:
  // - 앱 시작 시 로컬 저장소에 보관된 사용자 설정을 불러온다.
  // 반환값:
  // 함수명: loadUserSetting
  // 함수역할:
  // - 앱 시작 시 로컬 사용자 설정, 알림 설정, 오늘 복약 일정을 함께 불러온다.
  // 반환값:
  // - 없음
  Future<void> loadUserSetting() async {
    _isUserSettingLoading = true;
    notifyListeners();

    try {
      _userSetting = await manageUserSetting.requestStoredUserSetting();
      await refreshMedicationOverview();
    } finally {
      _isUserSettingLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshMedicationOverview() async {
    final scopeRevision = _medicationScopeRevision;
    await Future.wait([
      loadMedicationReminderSettings(notifyAfterLoad: false),
      fetchTodayMedicationSchedule(),
    ]);
    if (!_isCurrentMedicationScope(scopeRevision)) {
      return;
    }
    await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
  }

  // - 없음
  Future<void> requestPrescriptionImage() async {
    await _requestPrescriptionRecognition(
      imageRequest: prescriptionAnalysisControl.startPrescriptionInput,
      cancelledMessage: '사진 촬영이 취소되었습니다.',
    );
  }

  // 함수명: requestPrescriptionImageFromGallery
  // 함수역할:
  // - 갤러리 이미지 선택 기반 처방전 OCR 흐름을 시작한다.
  // 반환값:
  // - 없음
  Future<void> requestPrescriptionImageFromGallery() async {
    await _requestPrescriptionRecognition(
      imageRequest:
          prescriptionAnalysisControl.requestPrescriptionImageFromGallery,
      cancelledMessage: '이미지 선택이 취소되었습니다.',
    );
  }

  // 함수명: requestMedicationAnalysis
  // 함수역할:
  // - UC-1에서 인식된 약 목록 각각에 대해 공공데이터 기반 상세 정보를 요청한다.
  // - 저장은 하지 않고 분석 성공/실패 화면 상태까지만 변경한다.
  // 반환값:
  // - 없음
  Future<void> requestMedicationAnalysis() async {
    if (_recognizedMedicationScheduleList.isEmpty) {
      _showAnalysisFailure('인식된 처방 내역이 없습니다.');
      return;
    }

    final operationId = _beginPrescriptionOperation();
    final recognizedSchedules =
        List<MedicationSchedule>.of(_recognizedMedicationScheduleList);
    _analysisProgressStep = AnalysisProgressStep.medicationAnalysis;
    _prescriptionFlowState = PrescriptionFlowState.analyzingMedication;
    _statusMessage = '약물 정보를 분석 중입니다...';
    _analysisErrorMessage = '';
    _analyzedMedicationList = [];
    notifyListeners();

    try {
      final analysisResults = await Future.wait(
        recognizedSchedules.map((schedule) async {
          try {
            final detail = await checkMedicationDetail.requestMedicationDetail(
              schedule,
            );
            if (detail == null) {
              return null;
            }
            return AnalyzedMedication(schedule: schedule, detail: detail);
          } catch (_) {
            return null;
          }
        }),
      );
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      final analyzedMedicationList = analysisResults
          .whereType<AnalyzedMedication>()
          .toList(growable: false);
      final failedAnalysisCount =
          analysisResults.length - analyzedMedicationList.length;

      _analysisProgressStep = AnalysisProgressStep.scheduleGeneration;
      notifyListeners();

      if (analyzedMedicationList.isEmpty) {
        _showAnalysisFailure('약물 상세 정보를 찾지 못했습니다.');
        return;
      }

      _analyzedMedicationList = analyzedMedicationList;
      _prescriptionFlowState = PrescriptionFlowState.analysisSucceeded;
      _statusMessage = failedAnalysisCount > 0
          ? '처방전 분석은 완료되었지만 $failedAnalysisCount개 약 정보는 확인하지 못했습니다.'
          : '처방전 분석이 완료되었습니다.';
      notifyListeners();
    } on StateError catch (error) {
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      _showAnalysisFailure(error.message);
    } catch (_) {
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      _showAnalysisFailure('처방전 분석 중 오류가 발생했습니다.');
    }
  }

  // 함수명: showMedicationAnalysisResult
  // 함수역할:
  // - 분석 성공 화면에서 실제 결과 목록 화면으로 이동할 수 있도록 상태를 변경한다.
  // 반환값:
  // - 없음
  void showMedicationAnalysisResult() {
    if (_analyzedMedicationList.isEmpty) {
      _showAnalysisFailure('확인할 분석 결과가 없습니다.');
      return;
    }

    _prescriptionFlowState = PrescriptionFlowState.resultReady;
    notifyListeners();
  }

  // 함수명: requestAnalyzedMedicationSave
  // 함수역할:
  // - 이미 분석된 약 상세 정보를 저장 목록에 저장한다.
  // 매개변수:
  // - analyzedMedication: OCR 스케줄과 상세 정보가 결합된 분석 결과
  // - medicationIndex: 저장 버튼 로딩 표시를 위한 화면상 인덱스
  // 반환값:
  // - 저장 성공 여부
  Future<bool> requestAnalyzedMedicationSave(
    AnalyzedMedication analyzedMedication,
    int medicationIndex,
  ) async {
    final scopeRevision = _medicationScopeRevision;
    if (_completedMedicationSaveIndexes.contains(medicationIndex)) {
      _statusMessage = '이미 추가된 약입니다.';
      notifyListeners();
      return true;
    }

    _statusMessage = '${analyzedMedication.displayName} 저장 중...';
    _setSavingMedicationIndex(medicationIndex);

    try {
      final result = await saveMedicationInfo(
        analyzedMedication.detail,
        medicationSchedule: analyzedMedication.schedule,
      );
      if (result.isCompleted && _isCurrentMedicationScope(scopeRevision)) {
        _completedMedicationSaveIndexes.add(medicationIndex);
        notifyListeners();
      }
      return result.isCompleted;
    } finally {
      _setSavingMedicationIndex(null);
    }
  }

  Future<bool> requestAllAnalyzedMedicationSave() async {
    if (_analyzedMedicationList.isEmpty) {
      _statusMessage = '저장할 분석 결과가 없습니다.';
      notifyListeners();
      return false;
    }

    final scopeRevision = _medicationScopeRevision;
    _isAllMedicationSaving = true;
    _statusMessage = '전체 복약 일정을 저장 중입니다...';
    notifyListeners();

    var savedCount = 0;
    var duplicateCount = 0;
    var failedCount = 0;

    try {
      for (var index = 0; index < _analyzedMedicationList.length; index += 1) {
        if (!_isCurrentMedicationScope(scopeRevision)) {
          return false;
        }
        if (_completedMedicationSaveIndexes.contains(index)) {
          duplicateCount += 1;
          continue;
        }

        _savingMedicationIndex = index;
        notifyListeners();

        final analyzedMedication = _analyzedMedicationList[index];
        final result = await saveMedicationInfo(
          analyzedMedication.detail,
          medicationSchedule: analyzedMedication.schedule,
          refreshAfterSave: false,
        );
        if (!_isCurrentMedicationScope(scopeRevision)) {
          return false;
        }
        if (result.status == MedicationSaveStatus.saved) {
          savedCount += 1;
          _completedMedicationSaveIndexes.add(index);
        } else if (result.status == MedicationSaveStatus.duplicate) {
          duplicateCount += 1;
          _completedMedicationSaveIndexes.add(index);
        } else {
          failedCount += 1;
        }
      }

      await fetchSavedMedicationInfo();
      await fetchTodayMedicationSchedule();
      if (!_isCurrentMedicationScope(scopeRevision)) {
        return false;
      }
      await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
      _statusMessage = _buildBulkSaveMessage(
        savedCount: savedCount,
        duplicateCount: duplicateCount,
        failedCount: failedCount,
      );
      return failedCount == 0;
    } finally {
      _savingMedicationIndex = null;
      _isAllMedicationSaving = false;
      notifyListeners();
    }
  }

  Future<bool> requestMedicationSave(
    MedicationSchedule medicationSchedule,
    int medicationIndex,
  ) async {
    final scopeRevision = _medicationScopeRevision;
    final drugName = medicationSchedule.displayName;
    _statusMessage = '$drugName 정보를 공공 API와 AI가 분석 중입니다...';
    _setSavingMedicationIndex(medicationIndex);

    try {
      final medicationInfo =
          await checkMedicationDetail.requestMedicationDetail(
        medicationSchedule,
      );
      if (!_isCurrentMedicationScope(scopeRevision)) {
        return false;
      }
      if (medicationInfo == null) {
        _statusMessage = '해당 의약품 정보를 찾을 수 없습니다.';
        return false;
      }

      final result = await saveMedicationInfo(
        medicationInfo,
        medicationSchedule: medicationSchedule,
      );
      return result.isCompleted;
    } on StateError catch (error) {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _statusMessage = error.message;
      }
      return false;
    } catch (_) {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _statusMessage = '의약품 분석 중 오류가 발생했습니다.';
      }
      return false;
    } finally {
      _setSavingMedicationIndex(null);
    }
  }

  // 함수명: saveMedicationInfo
  // 함수역할:
  // - 약 상세 정보와 선택적 복약 스케줄을 저장 API로 전달하고 저장 목록을 갱신한다.
  // 매개변수:
  // - medicationInfo: 저장할 약 상세 정보
  // - medicationSchedule: OCR에서 추출된 선택적 복약 일정
  // 반환값:
  // - 저장 성공 여부
  Future<MedicationSaveResult> saveMedicationInfo(
    MedicationDetail medicationInfo, {
    MedicationSchedule? medicationSchedule,
    bool refreshAfterSave = true,
  }) async {
    final scopeRevision = _medicationScopeRevision;
    final savedMedicationControl = _activeCheckSavedMedication;
    _statusMessage = '${medicationInfo.itemName} 저장 중...';
    notifyListeners();

    final result = await savedMedicationControl.saveMedicationDetail(
      medicationInfo,
      medicationSchedule: medicationSchedule,
    );
    if (!_isCurrentMedicationScope(scopeRevision)) {
      return result;
    }
    if (result.status == MedicationSaveStatus.failed) {
      _statusMessage = result.message;
      notifyListeners();
      return result;
    }

    _statusMessage = result.status == MedicationSaveStatus.duplicate
        ? '이미 추가된 약입니다.'
        : '복약 정보가 성공적으로 저장되었습니다.';
    if (refreshAfterSave) {
      await fetchSavedMedicationInfo();
      await fetchTodayMedicationSchedule();
      await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
    }
    notifyListeners();
    return result;
  }

  // 함수명: fetchSavedMedicationInfo
  // 함수역할:
  // - 저장된 복약 정보 목록을 서버에서 가져와 화면 상태에 반영한다.
  // 반환값:
  // - 없음
  Future<void> fetchSavedMedicationInfo() async {
    final scopeRevision = _medicationScopeRevision;
    final savedMedicationControl = _activeCheckSavedMedication;
    _isSavedMedicationLoading = true;
    notifyListeners();

    try {
      final savedMedicationInfoList =
          await savedMedicationControl.requestSavedMedicationInfo();
      if (_isCurrentMedicationScope(scopeRevision)) {
        _savedMedicationInfoList = savedMedicationInfoList;
      }
    } on StateError catch (error) {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _statusMessage = error.message;
      }
    } catch (_) {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _statusMessage = '저장된 복약 정보를 불러오지 못했습니다.';
      }
    } finally {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _isSavedMedicationLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> requestDeleteSavedMedication(int savedMedicationId) async {
    final scopeRevision = _medicationScopeRevision;
    final savedMedicationControl = _activeCheckSavedMedication;
    final success = await savedMedicationControl.requestDelete(
      savedMedicationId,
    );

    if (success && _isCurrentMedicationScope(scopeRevision)) {
      _savedMedicationInfoList = _savedMedicationInfoList
          .where((item) => item.id != savedMedicationId)
          .toList(growable: false);
      await fetchTodayMedicationSchedule();
      await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
    }
    return success;
  }

  // 함수명: fetchTodayMedicationSchedule
  // 함수역할:
  // - 오늘 기준으로 복용해야 하는 약 일정을 서버에서 가져온다.
  // 반환값:
  // - 없음
  Future<void> fetchTodayMedicationSchedule() async {
    final scopeRevision = _medicationScopeRevision;
    final todayMedicationInfoControl = _activeCheckTodayMedicationInfo;
    _isTodayScheduleLoading = true;
    notifyListeners();

    try {
      final todayMedicationScheduleList =
          await todayMedicationInfoControl.requestTodayMedicationInfo();
      if (_isCurrentMedicationScope(scopeRevision)) {
        _todayMedicationScheduleList = todayMedicationScheduleList;
        _lastTodayScheduleLoadSucceeded = true;
      }
    } on StateError catch (error) {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _lastTodayScheduleLoadSucceeded = false;
        _statusMessage = error.message;
      }
    } catch (_) {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _lastTodayScheduleLoadSucceeded = false;
        _statusMessage = '복약 일정을 불러오지 못했습니다.';
      }
    } finally {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _isTodayScheduleLoading = false;
        notifyListeners();
      }
    }
  }

  // 함수명: fetchHealthRecommendation
  // 함수역할:
  // - 현재 복용 중인 약 조합을 바탕으로 건강 관리 추천을 서버에서 가져온다.
  // 반환값:
  // - 없음
  Future<void> fetchHealthRecommendation() async {
    final scopeRevision = _medicationScopeRevision;
    final healthRecommendationControl = _activeCheckHealthRecommendation;
    _isHealthRecommendationLoading = true;
    _healthRecommendation = null;
    _statusMessage = _isEnglishSetting
        ? 'Loading health recommendations.'
        : '건강 관리 추천을 불러오는 중입니다.';
    notifyListeners();

    try {
      final healthRecommendation =
          await healthRecommendationControl.requestHealthRecommendation(
        language: userSetting.language,
      );
      if (!_isCurrentMedicationScope(scopeRevision)) {
        return;
      }
      _healthRecommendation = healthRecommendation;
      _statusMessage = _isEnglishSetting
          ? 'Health recommendations loaded.'
          : '건강 관리 추천을 불러왔습니다.';
    } on StateError catch (error) {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _statusMessage = error.message;
      }
    } catch (_) {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _statusMessage = _isEnglishSetting
            ? 'Could not load health recommendations.'
            : '건강 관리 추천을 불러오지 못했습니다.';
      }
    } finally {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _isHealthRecommendationLoading = false;
        notifyListeners();
      }
    }
  }

  // 함수명: loadMedicationReminderSettings
  // 함수역할:
  // - 로컬 저장소에서 시간대별 복약 알림 설정을 불러온다.
  // 매개변수:
  // - notifyAfterLoad: 불러온 뒤 화면 갱신 여부
  // 반환값:
  // - 없음
  Future<void> loadMedicationReminderSettings({
    bool notifyAfterLoad = true,
  }) async {
    final scopeRevision = _medicationScopeRevision;
    final alarmControl = _activeSetNotification;
    try {
      final settings = await alarmControl.requestMedicationAlarm();
      if (!_isCurrentMedicationScope(scopeRevision)) {
        return;
      }
      final settingsBySlot = {
        for (final slotKey in _reminderSlotKeys)
          slotKey: MedicationAlarm.defaults(slotKey),
      };
      for (final setting in settings) {
        if (_reminderSlotKeys.contains(setting.slotKey)) {
          settingsBySlot[setting.slotKey] = setting;
        }
      }
      _medicationReminderSettings
        ..clear()
        ..addAll(settingsBySlot);

      final preferences = await SharedPreferences.getInstance();
      for (final setting in settingsBySlot.values) {
        if (!_isCurrentMedicationScope(scopeRevision)) {
          return;
        }
        await _cacheMedicationReminderSetting(preferences, setting);
      }
    } catch (_) {
      if (!_isCurrentMedicationScope(scopeRevision)) {
        return;
      }
      await _loadMedicationReminderSettingsFromCache();
    }

    if (notifyAfterLoad && _isCurrentMedicationScope(scopeRevision)) {
      notifyListeners();
    }
  }

  // 함수명: requestMedicationReminderSave
  // 함수역할:
  // - 사용자가 설정한 시간대별 복약 알림을 휴대폰 로컬 알림으로 예약한다.
  // 매개변수:
  // - slotKey: morning, lunch, evening, bedtime 중 하나
  // - slotTitle: 사용자에게 보여줄 시간대명
  // - hour: 24시간 기준 시
  // - minute: 분
  // - schedules: 해당 시간대에 복용할 약 목록
  // 반환값:
  // - 알림 예약 성공 여부
  Future<bool> requestMedicationReminderSave({
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<MedicationSchedule> schedules,
  }) async {
    final scopeRevision = _medicationScopeRevision;
    final alarmControl = _activeSetNotification;
    final storageKey = _reminderStorageKey(slotKey);
    if (schedules.isEmpty) {
      _statusMessage = _isEnglishSetting
          ? 'There is no medication in this time slot.'
          : '이 시간대에 복용할 약이 없습니다.';
      notifyListeners();
      return false;
    }

    bool hasPermission;
    try {
      hasPermission = await notificationService.requestPermission();
    } catch (_) {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _statusMessage = _isEnglishSetting
            ? 'Could not request notification permission.'
            : '알림 권한을 요청하지 못했습니다.';
        notifyListeners();
      }
      return false;
    }
    if (!_isCurrentMedicationScope(scopeRevision)) {
      return false;
    }
    if (!hasPermission) {
      _statusMessage = _isEnglishSetting
          ? 'Notification permission was not allowed.'
          : '알림 권한이 허용되지 않았습니다.';
      notifyListeners();
      return false;
    }

    MedicationAlarm? persistedSetting;
    try {
      final setting = await alarmControl.setMedicationAlarm(
        slotKey: slotKey,
        hour: hour,
        minute: minute,
      );
      persistedSetting = setting;
      if (await _rollbackReminderSaveIfScopeChanged(
        scopeRevision: scopeRevision,
        alarmControl: alarmControl,
        setting: setting,
        storageKey: storageKey,
      )) {
        return false;
      }

      await _scheduleMedicationReminder(
        setting: setting,
        slotTitle: slotTitle,
        schedules: schedules,
      );
      if (await _rollbackReminderSaveIfScopeChanged(
        scopeRevision: scopeRevision,
        alarmControl: alarmControl,
        setting: setting,
        storageKey: storageKey,
      )) {
        return false;
      }

      final preferences = await SharedPreferences.getInstance();
      await _cacheMedicationReminderSetting(
        preferences,
        setting,
        storageKey: storageKey,
      );
      if (await _rollbackReminderSaveIfScopeChanged(
        scopeRevision: scopeRevision,
        alarmControl: alarmControl,
        setting: setting,
        storageKey: storageKey,
      )) {
        return false;
      }
      _medicationReminderSettings[setting.slotKey] = setting;
      _statusMessage = _isEnglishSetting
          ? '$slotTitle reminder is set for ${setting.timeLabel}.'
          : '$slotTitle 알림이 ${setting.timeLabel}에 설정되었습니다.';
      notifyListeners();
      return true;
    } on StateError catch (error) {
      await _rollbackMedicationReminderSave(
        alarmControl: alarmControl,
        setting: persistedSetting,
        storageKey: storageKey,
      );
      if (_isCurrentMedicationScope(scopeRevision)) {
        _statusMessage = error.message;
        notifyListeners();
      }
      return false;
    } catch (_) {
      await _rollbackMedicationReminderSave(
        alarmControl: alarmControl,
        setting: persistedSetting,
        storageKey: storageKey,
      );
      if (_isCurrentMedicationScope(scopeRevision)) {
        _statusMessage = _isEnglishSetting
            ? 'Could not set the $slotTitle reminder.'
            : '$slotTitle 알림을 설정하지 못했습니다.';
        notifyListeners();
      }
      return false;
    }
  }

  // 함수명: requestMedicationReminderCancel
  // 함수역할:
  // - 이미 활성화된 시간대별 복약 알림을 취소하고 로컬 설정을 비활성화한다.
  // 매개변수:
  // - slotKey: morning, lunch, evening, bedtime 중 하나
  // - slotTitle: 사용자에게 보여줄 시간대명
  // 반환값:
  // - 알림 취소 성공 여부
  Future<bool> requestMedicationReminderCancel({
    required String slotKey,
    required String slotTitle,
  }) async {
    final scopeRevision = _medicationScopeRevision;
    final alarmControl = _activeSetNotification;
    final storageKey = _reminderStorageKey(slotKey);
    try {
      final disabledSetting = await alarmControl.disableAlarmSetting(slotKey);
      await _cancelMedicationReminder(disabledSetting);
      final preferences = await SharedPreferences.getInstance();
      await _cacheMedicationReminderSetting(
        preferences,
        disabledSetting,
        storageKey: storageKey,
      );
      if (!_isCurrentMedicationScope(scopeRevision)) {
        return true;
      }
      _medicationReminderSettings[disabledSetting.slotKey] = disabledSetting;
      _statusMessage = _isEnglishSetting
          ? '$slotTitle reminder has been turned off.'
          : '$slotTitle 알림을 해제했습니다.';
      notifyListeners();
      return true;
    } catch (_) {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _statusMessage = _isEnglishSetting
            ? 'Could not turn off the $slotTitle reminder.'
            : '$slotTitle 알림을 해제하지 못했습니다.';
        notifyListeners();
      }
      return false;
    }
  }

  String _reminderStorageKey(String slotKey) {
    final userScope = _medicationUserHash ?? _medicationPatientHash;
    return 'medbuddy_medication_reminder_'
        '${_medicationRole}_${userScope}_${_medicationPatientHash}_$slotKey';
  }

  String _legacyReminderStorageKey(String slotKey) {
    return 'medbuddy_medication_reminder_$slotKey';
  }

  Future<void> _cacheMedicationReminderSetting(
    SharedPreferences preferences,
    MedicationAlarm setting, {
    String? storageKey,
  }) async {
    await preferences.setString(
      storageKey ?? _reminderStorageKey(setting.slotKey),
      jsonEncode(setting.toJson()),
    );
  }

  Future<void> _rollbackMedicationReminderSave({
    required SetNotification alarmControl,
    required MedicationAlarm? setting,
    required String storageKey,
  }) async {
    if (setting == null) {
      return;
    }

    try {
      await _cancelMedicationReminder(setting);
    } catch (_) {
      // Local cancellation is best-effort while restoring cross-system state.
    }

    MedicationAlarm disabledSetting = setting.copyWith(enabled: false);
    try {
      disabledSetting = await alarmControl.disableAlarmSetting(setting.slotKey);
    } catch (_) {
      // The disabled cache state prevents an offline reload from rescheduling it.
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      await _cacheMedicationReminderSetting(
        preferences,
        disabledSetting,
        storageKey: storageKey,
      );
    } catch (_) {
      // Cache rollback is best-effort after backend or plugin failure.
    }
  }

  Future<bool> _rollbackReminderSaveIfScopeChanged({
    required int scopeRevision,
    required SetNotification alarmControl,
    required MedicationAlarm setting,
    required String storageKey,
  }) async {
    if (_isCurrentMedicationScope(scopeRevision)) {
      return false;
    }
    await _rollbackMedicationReminderSave(
      alarmControl: alarmControl,
      setting: setting,
      storageKey: storageKey,
    );
    return true;
  }

  Future<void> _loadMedicationReminderSettingsFromCache() async {
    final preferences = await SharedPreferences.getInstance();
    for (final slotKey in _reminderSlotKeys) {
      final rawSetting = preferences.getString(_reminderStorageKey(slotKey)) ??
          preferences.getString(_legacyReminderStorageKey(slotKey));
      if (rawSetting == null || rawSetting.trim().isEmpty) {
        _medicationReminderSettings[slotKey] =
            MedicationAlarm.defaults(slotKey);
        continue;
      }

      try {
        final decodedSetting = jsonDecode(rawSetting);
        if (decodedSetting is Map<String, dynamic>) {
          _medicationReminderSettings[slotKey] =
              MedicationAlarm.fromJson(decodedSetting);
          continue;
        }
      } catch (_) {
        // Invalid cache entries are ignored and replaced with defaults.
      }
      _medicationReminderSettings[slotKey] = MedicationAlarm.defaults(slotKey);
    }
  }

  Future<void> _synchronizeMedicationReminderSchedules() async {
    if (_medicationReminderSettings.isEmpty) {
      return;
    }

    final scopeRevision = _medicationScopeRevision;
    final alarmControl = _activeSetNotification;
    final preferences = await SharedPreferences.getInstance();
    for (final slotKey in _reminderSlotKeys) {
      if (!_isCurrentMedicationScope(scopeRevision)) {
        return;
      }
      final setting = _medicationReminderSettings[slotKey] ??
          MedicationAlarm.defaults(slotKey);
      if (!setting.isEnabled) {
        await _cancelMedicationReminder(setting);
        continue;
      }

      final schedules = _schedulesForReminderSlot(slotKey);
      if (schedules.isEmpty) {
        final disabledSetting = await _disableReminderSettingForEmptySlot(
          alarmControl,
          slotKey,
          setting,
        );
        if (!_isCurrentMedicationScope(scopeRevision)) {
          await _cancelMedicationReminder(disabledSetting);
          return;
        }
        await _cacheMedicationReminderSetting(preferences, disabledSetting);
        _medicationReminderSettings[disabledSetting.slotKey] = disabledSetting;
        await _cancelMedicationReminder(disabledSetting);
        continue;
      }

      await _scheduleMedicationReminder(
        setting: setting,
        slotTitle: _reminderSlotTitle(slotKey),
        schedules: schedules,
      );
      if (!_isCurrentMedicationScope(scopeRevision)) {
        await _cancelMedicationReminder(setting);
        return;
      }
    }
  }

  Future<void>
      _synchronizeMedicationReminderSchedulesIfScheduleIsFresh() async {
    if (!_lastTodayScheduleLoadSucceeded) {
      return;
    }
    await _synchronizeMedicationReminderSchedules();
  }

  Future<MedicationAlarm> _disableReminderSettingForEmptySlot(
    SetNotification alarmControl,
    String slotKey,
    MedicationAlarm fallbackSetting,
  ) async {
    try {
      return await alarmControl.disableAlarmSetting(slotKey);
    } catch (_) {
      return fallbackSetting.copyWith(enabled: false);
    }
  }

  Future<void> _scheduleMedicationReminder({
    required MedicationAlarm setting,
    required String slotTitle,
    required List<MedicationSchedule> schedules,
  }) async {
    await _cancelLegacyMedicationReminder(setting);
    await notificationService.scheduleDailyReminder(
      id: setting.notificationId,
      slotKey: setting.slotKey,
      slotTitle: slotTitle,
      hour: setting.hour,
      minute: setting.minute,
      medicationNames: schedules
          .map((schedule) => schedule.displayName)
          .where((name) => name.trim().isNotEmpty)
          .toList(growable: false),
      language: userSetting.language,
    );
  }

  Future<void> _cancelMedicationReminder(MedicationAlarm setting) async {
    await notificationService.cancelReminder(setting.notificationId);
    await _cancelLegacyMedicationReminder(setting);
  }

  Future<void> _cancelLegacyMedicationReminder(MedicationAlarm setting) async {
    final legacyId = setting.legacyNotificationId;
    if (legacyId != setting.notificationId) {
      await notificationService.cancelReminder(legacyId);
    }
  }

  List<MedicationSchedule> _schedulesForReminderSlot(String slotKey) {
    return _todayMedicationScheduleList.where((schedule) {
      return _slotKeysForSchedule(schedule).contains(slotKey);
    }).toList(growable: false);
  }

  String _reminderSlotTitle(String slotKey) {
    final isEnglish = _isEnglishSetting;
    return switch (slotKey) {
      'morning' => isEnglish ? 'Morning' : '아침',
      'lunch' => isEnglish ? 'Lunch' : '점심',
      'evening' => isEnglish ? 'Evening' : '저녁',
      'bedtime' => isEnglish ? 'Bedtime' : '취침 전',
      _ => isEnglish ? 'Schedule' : '일정',
    };
  }

  // 함수명: isMedicationDoseCompleted
  // 함수역할:
  // - MedicationCompletion 기반 시간대별 복약 완료 상태를 반환한다.
  // - slot 상태가 없는 이전 응답은 기존 medicationStatus 값으로 처리한다.
  // 매개변수:
  // - slotKey: 확인할 시간대 키
  // - schedule: 확인할 복약 일정
  // 반환값:
  // - 해당 시간대가 완료 처리되어 있으면 True
  bool isMedicationDoseCompleted(
    String slotKey,
    MedicationSchedule schedule,
  ) {
    return schedule.isSlotCompleted(slotKey);
  }

  List<String> slotKeysForSchedule(MedicationSchedule schedule) {
    return _slotKeysForSchedule(schedule);
  }

  // 함수명: requestMedicationDoseStatusUpdate
  // 함수역할:
  // - 복약 완료 상태를 백엔드 일정 상태 변경 API로 저장한다.
  // - slotKey를 함께 전달해 하루 여러 번 복용하는 약의 완료 상태를 분리한다.
  // 매개변수:
  // - slotKey: 상태를 변경할 시간대 키
  // - schedule: 상태를 변경할 복약 일정
  // - medicationStatus: 새 완료 상태
  // 반환값:
  // - 백엔드 갱신에 성공하면 True
  Future<bool> requestMedicationDoseStatusUpdate(
    String slotKey,
    MedicationSchedule schedule,
    bool medicationStatus,
  ) async {
    return requestMedicationStatusUpdate(
      schedule,
      medicationStatus,
      slotKey: slotKey,
    );
  }

  Future<bool> requestMedicationStatusUpdate(
    MedicationSchedule medicationSchedule,
    bool medicationStatus, {
    String? slotKey,
  }) async {
    if (medicationSchedule.medicationID.trim().isEmpty) {
      return false;
    }

    final scopeRevision = _medicationScopeRevision;
    final scheduleControl = _activeCheckSchedule;
    try {
      final updatedSchedule = await scheduleControl.updateMedicationStatus(
        medicationSchedule.medicationID,
        medicationStatus,
        slotKey: slotKey,
      );
      if (!_isCurrentMedicationScope(scopeRevision)) {
        return false;
      }
      _todayMedicationScheduleList = _todayMedicationScheduleList
          .map(
            (item) => item.medicationID == updatedSchedule.medicationID
                ? updatedSchedule
                : item,
          )
          .toList(growable: false);
      notifyListeners();
      return true;
    } on StateError catch (error) {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _statusMessage = error.message;
        notifyListeners();
      }
      return false;
    } catch (_) {
      if (_isCurrentMedicationScope(scopeRevision)) {
        _statusMessage = '복약 상태를 업데이트하지 못했습니다.';
        notifyListeners();
      }
      return false;
    }
  }

  void clearAnalysisResult() {
    _cancelPrescriptionOperation();
    _recognizedMedicationScheduleList = [];
    _analyzedMedicationList = [];
    _completedMedicationSaveIndexes.clear();
    _isAllMedicationSaving = false;
    _savingMedicationIndex = null;
    _analysisErrorMessage = '';
    _clearPrescriptionRecognitionCounts();
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;
    _prescriptionFlowState = PrescriptionFlowState.idle;
    _statusMessage = '처방전을 촬영하거나 이미지를 선택해주세요.';
    notifyListeners();
  }

  Future<void> requestUserSettingSave({
    required String fontSizeOption,
    required String readingSpeedOption,
    required String language,
  }) async {
    _userSetting = await manageUserSetting.requestSettingSave(
      currentSetting: _userSetting,
      fontSizeOption: fontSizeOption,
      readingSpeedOption: readingSpeedOption,
      language: language,
    );
    notifyListeners();
  }

  // 함수명: _requestPrescriptionRecognition
  // 함수역할:
  // - 카메라/갤러리 공통 처방전 OCR 흐름을 상태 머신 형태로 처리한다.
  // - 사용자가 선택을 취소하면 분석 화면으로 넘어가지 않도록 idle 상태로 되돌린다.
  // 매개변수:
  // - imageRequest: 이미지 선택과 OCR 요청을 수행하는 함수
  // - cancelledMessage: 사용자가 취소했을 때 보여줄 상태 메시지
  // 반환값:
  // - 없음
  Future<void> _requestPrescriptionRecognition({
    required Future<List<MedicationSchedule>?> Function({
      VoidCallback? onImageSelected,
    }) imageRequest,
    required String cancelledMessage,
  }) async {
    final operationId = _beginPrescriptionOperation();
    _recognizedMedicationScheduleList = [];
    _analyzedMedicationList = [];
    _analysisErrorMessage = '';
    _clearPrescriptionRecognitionCounts();
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;

    try {
      final result = await imageRequest(
        onImageSelected: () {
          if (_isCurrentPrescriptionOperation(operationId)) {
            _showPrescriptionRecognitionProgress();
          }
        },
      );
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      if (result == null) {
        _statusMessage = cancelledMessage;
        _prescriptionFlowState = PrescriptionFlowState.idle;
        notifyListeners();
        return;
      }

      if (result.isEmpty) {
        _showAnalysisFailure('처방전에서 약 정보를 찾지 못했습니다.');
        return;
      }

      _recognizedMedicationScheduleList = result;
      _recordPrescriptionRecognitionCounts(result);
      _prescriptionFlowState = PrescriptionFlowState.previewReady;
      _statusMessage = prescriptionRecognitionNotice.isEmpty
          ? '처방전 인식이 완료되었습니다.'
          : '처방전 인식이 완료되었습니다. 인식 내역을 확인해주세요.';
      notifyListeners();
    } on StateError catch (error) {
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      _showAnalysisFailure(error.message);
    } catch (_) {
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      _showAnalysisFailure('처방전 인식 중 오류가 발생했습니다.');
    }
  }

  int _beginPrescriptionOperation() {
    _prescriptionOperationId += 1;
    return _prescriptionOperationId;
  }

  void _cancelPrescriptionOperation() {
    _prescriptionOperationId += 1;
  }

  bool _isCurrentPrescriptionOperation(int operationId) {
    return _prescriptionOperationId == operationId;
  }

  void _showPrescriptionRecognitionProgress() {
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;
    _prescriptionFlowState = PrescriptionFlowState.recognizingPrescription;
    _statusMessage = '처방전을 인식 중입니다...';
    notifyListeners();
  }

  void _clearPrescriptionRecognitionCounts() {
    _lastPrescriptionRawMedicationCount = 0;
    _lastPrescriptionParsedMedicationCount = 0;
    _lastPrescriptionSkippedMedicationCount = 0;
  }

  void _recordPrescriptionRecognitionCounts(
    List<MedicationSchedule> schedules,
  ) {
    final parsedCount =
        prescriptionAnalysisControl.lastParsedMedicationCount > 0
            ? prescriptionAnalysisControl.lastParsedMedicationCount
            : schedules.length;
    final rawCount = prescriptionAnalysisControl.lastRawMedicationCount > 0
        ? prescriptionAnalysisControl.lastRawMedicationCount
        : parsedCount;
    final skippedCount =
        prescriptionAnalysisControl.lastSkippedMedicationCount > 0
            ? prescriptionAnalysisControl.lastSkippedMedicationCount
            : rawCount - parsedCount;

    _lastPrescriptionParsedMedicationCount = parsedCount < 0 ? 0 : parsedCount;
    _lastPrescriptionRawMedicationCount = rawCount < 0 ? 0 : rawCount;
    _lastPrescriptionSkippedMedicationCount =
        skippedCount < 0 ? 0 : skippedCount;
  }

  void _showAnalysisFailure(String message) {
    _analysisErrorMessage = message;
    _statusMessage = message;
    _prescriptionFlowState = PrescriptionFlowState.analysisFailed;
    notifyListeners();
  }

  void _setSavingMedicationIndex(int? value) {
    _savingMedicationIndex = value;
    notifyListeners();
  }

  String _buildBulkSaveMessage({
    required int savedCount,
    required int duplicateCount,
    required int failedCount,
  }) {
    final parts = <String>[];
    if (savedCount > 0) {
      parts.add('$savedCount개 저장');
    }
    if (duplicateCount > 0) {
      parts.add('$duplicateCount개 중복');
    }
    if (failedCount > 0) {
      parts.add('$failedCount개 실패');
    }
    if (parts.isEmpty) {
      return '이미 추가된 약입니다.';
    }
    return '전체 저장 완료: ${parts.join(', ')}';
  }

  CheckSavedMedication get _activeCheckSavedMedication =>
      _scopedCheckSavedMedication ?? checkSavedMedication;

  CheckSchedule get _activeCheckSchedule =>
      _scopedCheckSchedule ?? checkSchedule;

  CheckTodayMedicationInfo get _activeCheckTodayMedicationInfo =>
      _scopedCheckTodayMedicationInfo ?? checkTodayMedicationInfo;

  CheckHealthRecommendation get _activeCheckHealthRecommendation =>
      _scopedCheckHealthRecommendation ?? checkHealthRecommendation;

  SetNotification get _activeSetNotification =>
      _scopedSetNotification ?? setNotification;

  bool _isCurrentMedicationScope(int scopeRevision) {
    return scopeRevision == _medicationScopeRevision;
  }

  List<String> _slotKeysForSchedule(MedicationSchedule schedule) {
    if (schedule.slotStatuses.isNotEmpty) {
      final slotKeys = medicationScheduleSlotKeys
          .where((slotKey) => schedule.slotStatuses.containsKey(slotKey))
          .toList(growable: false);
      if (slotKeys.isNotEmpty) {
        return slotKeys;
      }
    }
    return schedule.slotKeys;
  }

  void _rebuildMedicationScopeControls() {
    _scopedCheckSavedMedication?.dispose();
    _scopedCheckSchedule?.dispose();
    _scopedCheckTodayMedicationInfo?.dispose();
    _scopedCheckHealthRecommendation?.dispose();
    _scopedSetNotification?.dispose();
    _scopedCheckSavedMedication = checkSavedMedication.forScope(
      patientHash: _medicationPatientHash,
      userHash: _medicationUserHash,
      role: _medicationRole,
    );
    _scopedCheckSchedule = checkSchedule.forScope(
      patientHash: _medicationPatientHash,
      userHash: _medicationUserHash,
      role: _medicationRole,
    );
    _scopedCheckTodayMedicationInfo = checkTodayMedicationInfo.forScope(
      patientHash: _medicationPatientHash,
      userHash: _medicationUserHash,
      role: _medicationRole,
    );
    _scopedCheckHealthRecommendation = checkHealthRecommendation.forScope(
      patientHash: _medicationPatientHash,
      userHash: _medicationUserHash,
      role: _medicationRole,
    );
    _scopedSetNotification = setNotification.forScope(
      patientHash: _medicationPatientHash,
      userHash: _medicationUserHash,
      role: _medicationRole,
    );
  }

  @override
  void dispose() {
    _cancelPrescriptionOperation();
    _scopedCheckSavedMedication?.dispose();
    _scopedCheckSchedule?.dispose();
    _scopedCheckTodayMedicationInfo?.dispose();
    _scopedCheckHealthRecommendation?.dispose();
    _scopedSetNotification?.dispose();
    prescriptionAnalysisControl.dispose();
    checkMedicationDetail.dispose();
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
