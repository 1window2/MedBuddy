import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controls/check_health_recommendation_control.dart';
import '../controls/check_medication_detail_control.dart';
import '../controls/check_schedule_control.dart';
import '../controls/check_saved_medication_control.dart';
import '../controls/input_prescription_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../entities/analyzed_medication_entity.dart';
import '../entities/health_recommendation_entity.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_reminder_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/medication_notification_service.dart';

// 열거형명: PrescriptionFlowState
// 역할: 처방전 촬영부터 결과 확인까지의 화면 상태를 표현한다.
enum PrescriptionFlowState {
  idle,
  recognizingPrescription,
  previewReady,
  analyzingMedication,
  analysisSucceeded,
  analysisFailed,
  resultReady,
}

// 열거형명: AnalysisProgressStep
// 역할: 분석중 화면에서 현재 처리 단계를 사용자에게 보여주기 위한 상태값이다.
enum AnalysisProgressStep {
  prescriptionRecognition,
  medicationAnalysis,
  scheduleGeneration,
}

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
  final InputPrescription inputPrescription;
  final CheckMedicationDetail checkMedicationDetail;
  final CheckSavedMedication checkSavedMedication;
  final CheckSchedule checkSchedule;
  final CheckHealthRecommendation checkHealthRecommendation;
  final ManageUserSetting manageUserSetting;
  final MedicationNotificationService notificationService;

  PrescriptionFlowState _prescriptionFlowState = PrescriptionFlowState.idle;
  PrescriptionFlowState get prescriptionFlowState => _prescriptionFlowState;

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

  bool _isHealthRecommendationLoading = false;
  bool get isHealthRecommendationLoading => _isHealthRecommendationLoading;

  bool _isUserSettingLoading = false;
  bool get isUserSettingLoading => _isUserSettingLoading;

  String _statusMessage = '처방전을 촬영하거나 이미지를 선택해주세요.';
  String get statusMessage => _statusMessage;

  String _analysisErrorMessage = '';
  String get analysisErrorMessage => _analysisErrorMessage;

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
    final slotKeys = ['morning', 'lunch', 'evening', 'bedtime'];
    var totalCount = 0;
    var completedCount = 0;

    for (final schedule in _todayMedicationScheduleList) {
      final scheduleSlotKeys = _slotKeysForSchedule(schedule);
      for (final slotKey in slotKeys) {
        if (!scheduleSlotKeys.contains(slotKey)) {
          continue;
        }
        totalCount += 1;
        if (isMedicationDoseCompleted(slotKey, schedule)) {
          completedCount += 1;
        }
      }
    }

    return TodayMedicationProgress(
      completedCount: completedCount,
      totalCount: totalCount,
    );
  }

  final Map<String, MedicationReminderSetting> _medicationReminderSettings = {};
  Map<String, MedicationReminderSetting> get medicationReminderSettings =>
      Map.unmodifiable(_medicationReminderSettings);

  final Set<String> _completedMedicationDoseKeys = {};

  MedBuddyViewModel({
    InputPrescription? inputPrescription,
    CheckMedicationDetail? checkMedicationDetail,
    CheckSavedMedication? checkSavedMedication,
    CheckSchedule? checkSchedule,
    CheckHealthRecommendation? checkHealthRecommendation,
    ManageUserSetting? manageUserSetting,
    MedicationNotificationService? notificationService,
  })  : inputPrescription = inputPrescription ?? InputPrescription(),
        checkMedicationDetail =
            checkMedicationDetail ?? CheckMedicationDetail(),
        checkSavedMedication = checkSavedMedication ?? CheckSavedMedication(),
        checkSchedule = checkSchedule ?? CheckSchedule(),
        checkHealthRecommendation =
            checkHealthRecommendation ?? CheckHealthRecommendation(),
        manageUserSetting = manageUserSetting ?? ManageUserSetting(),
        notificationService =
            notificationService ?? MedicationNotificationService.instance;

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
      await loadMedicationReminderSettings(notifyAfterLoad: false);
      await loadTodayMedicationDoseStatuses(notifyAfterLoad: false);
      await fetchTodayMedicationSchedule();
    } finally {
      _isUserSettingLoading = false;
      notifyListeners();
    }
  }

  // - 없음
  Future<void> requestPrescriptionImage() async {
    await _requestPrescriptionRecognition(
      imageRequest: inputPrescription.requestPrescriptionImage,
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
      imageRequest: inputPrescription.requestPrescriptionImageFromGallery,
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

    _analysisProgressStep = AnalysisProgressStep.medicationAnalysis;
    _prescriptionFlowState = PrescriptionFlowState.analyzingMedication;
    _statusMessage = '약물 정보를 분석 중입니다...';
    _analysisErrorMessage = '';
    _analyzedMedicationList = [];
    notifyListeners();

    try {
      final analysisResults = await Future.wait(
        _recognizedMedicationScheduleList.map((schedule) async {
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
      final analyzedMedicationList = analysisResults
          .whereType<AnalyzedMedication>()
          .toList(growable: false);

      _analysisProgressStep = AnalysisProgressStep.scheduleGeneration;
      notifyListeners();

      if (analyzedMedicationList.isEmpty) {
        _showAnalysisFailure('약물 상세 정보를 찾지 못했습니다.');
        return;
      }

      _analyzedMedicationList = analyzedMedicationList;
      _prescriptionFlowState = PrescriptionFlowState.analysisSucceeded;
      _statusMessage = '처방전 분석이 완료되었습니다.';
      notifyListeners();
    } on StateError catch (error) {
      _showAnalysisFailure(error.message);
    } catch (_) {
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
      if (result.isCompleted) {
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

    _isAllMedicationSaving = true;
    _statusMessage = '전체 복약 일정을 저장 중입니다...';
    notifyListeners();

    var savedCount = 0;
    var duplicateCount = 0;
    var failedCount = 0;

    try {
      for (var index = 0; index < _analyzedMedicationList.length; index += 1) {
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
    final drugName = medicationSchedule.displayName;
    _statusMessage = '$drugName 정보를 공공 API와 AI가 분석 중입니다...';
    _setSavingMedicationIndex(medicationIndex);

    try {
      final medicationInfo =
          await checkMedicationDetail.requestMedicationDetail(
        medicationSchedule,
      );
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
      _statusMessage = error.message;
      return false;
    } catch (_) {
      _statusMessage = '의약품 분석 중 오류가 발생했습니다.';
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
    _statusMessage = '${medicationInfo.itemName} 저장 중...';
    notifyListeners();

    final result = await checkSavedMedication.saveMedicationDetail(
      medicationInfo,
      medicationSchedule: medicationSchedule,
    );
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
    _isSavedMedicationLoading = true;
    notifyListeners();

    try {
      _savedMedicationInfoList =
          await checkSavedMedication.requestSavedMedicationInfo();
    } on StateError catch (error) {
      _statusMessage = error.message;
    } catch (_) {
      _statusMessage = '저장된 복약 정보를 불러오지 못했습니다.';
    } finally {
      _isSavedMedicationLoading = false;
      notifyListeners();
    }
  }

  Future<bool> requestDeleteSavedMedication(int savedMedicationId) async {
    final success = await checkSavedMedication.requestDelete(
      savedMedicationId,
    );

    if (success) {
      _savedMedicationInfoList = _savedMedicationInfoList
          .where((item) => item.id != savedMedicationId)
          .toList(growable: false);
      notifyListeners();
    }
    return success;
  }

  // 함수명: fetchTodayMedicationSchedule
  // 함수역할:
  // - 오늘 기준으로 복용해야 하는 약 일정을 서버에서 가져온다.
  // 반환값:
  // - 없음
  Future<void> fetchTodayMedicationSchedule() async {
    _isTodayScheduleLoading = true;
    notifyListeners();

    try {
      _todayMedicationScheduleList =
          await checkSchedule.requestTodayMedicationSchedule();
      await loadTodayMedicationDoseStatuses(notifyAfterLoad: false);
    } on StateError catch (error) {
      _statusMessage = error.message;
    } catch (_) {
      _statusMessage = '복약 일정을 불러오지 못했습니다.';
    } finally {
      _isTodayScheduleLoading = false;
      notifyListeners();
    }
  }

  // 함수명: fetchHealthRecommendation
  // 함수역할:
  // - 현재 복용 중인 약 조합을 바탕으로 건강 관리 추천을 서버에서 가져온다.
  // 반환값:
  // - 없음
  Future<void> fetchHealthRecommendation() async {
    _isHealthRecommendationLoading = true;
    _healthRecommendation = null;
    _statusMessage = _isEnglishSetting
        ? 'Loading health recommendations.'
        : '건강 관리 추천을 불러오는 중입니다.';
    notifyListeners();

    try {
      _healthRecommendation =
          await checkHealthRecommendation.requestHealthRecommendation(
        language: userSetting.language,
      );
      _statusMessage = _isEnglishSetting
          ? 'Health recommendations loaded.'
          : '건강 관리 추천을 불러왔습니다.';
    } on StateError catch (error) {
      _statusMessage = error.message;
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'Could not load health recommendations.'
          : '건강 관리 추천을 불러오지 못했습니다.';
    } finally {
      _isHealthRecommendationLoading = false;
      notifyListeners();
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
    final preferences = await SharedPreferences.getInstance();
    for (final slotKey in ['morning', 'lunch', 'evening', 'bedtime']) {
      final rawSetting = preferences.getString(_reminderStorageKey(slotKey));
      if (rawSetting == null || rawSetting.trim().isEmpty) {
        _medicationReminderSettings[slotKey] =
            MedicationReminderSetting.defaults(slotKey);
        continue;
      }

      try {
        final decodedSetting = jsonDecode(rawSetting);
        if (decodedSetting is Map<String, dynamic>) {
          _medicationReminderSettings[slotKey] =
              MedicationReminderSetting.fromJson(decodedSetting);
        }
      } catch (_) {
        _medicationReminderSettings[slotKey] =
            MedicationReminderSetting.defaults(slotKey);
      }
    }

    if (notifyAfterLoad) {
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
    final setting = MedicationReminderSetting(
      slotKey: slotKey,
      hour: hour,
      minute: minute,
      isEnabled: true,
    );

    final hasPermission = await notificationService.requestPermission();
    if (!hasPermission) {
      _statusMessage = _isEnglishSetting
          ? 'Notification permission was not allowed.'
          : '알림 권한이 허용되지 않았습니다.';
      notifyListeners();
      return false;
    }

    await notificationService.scheduleDailyReminder(
      id: setting.notificationId,
      slotTitle: slotTitle,
      hour: hour,
      minute: minute,
      medicationNames:
          schedules.map((schedule) => schedule.displayName).toList(),
      language: userSetting.language,
    );

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _reminderStorageKey(slotKey),
      jsonEncode(setting.toJson()),
    );
    _medicationReminderSettings[slotKey] = setting;
    _statusMessage = _isEnglishSetting
        ? '$slotTitle reminder is set for ${setting.timeLabel}.'
        : '$slotTitle 알림이 ${setting.timeLabel}에 설정되었습니다.';
    notifyListeners();
    return true;
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
    final currentSetting = _medicationReminderSettings[slotKey] ??
        MedicationReminderSetting.defaults(slotKey);
    final disabledSetting = currentSetting.copyWith(isEnabled: false);

    try {
      await notificationService.cancelReminder(currentSetting.notificationId);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _reminderStorageKey(slotKey),
        jsonEncode(disabledSetting.toJson()),
      );
      _medicationReminderSettings[slotKey] = disabledSetting;
      _statusMessage = _isEnglishSetting
          ? '$slotTitle reminder has been turned off.'
          : '$slotTitle 알림을 해제했습니다.';
      notifyListeners();
      return true;
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'Could not turn off the $slotTitle reminder.'
          : '$slotTitle 알림을 해제하지 못했습니다.';
      notifyListeners();
      return false;
    }
  }

  String _reminderStorageKey(String slotKey) {
    return 'medbuddy_medication_reminder_$slotKey';
  }

  // 함수명: loadTodayMedicationDoseStatuses
  // 함수역할:
  // - 오늘 날짜의 시간대별 복약 완료 상태를 로컬 저장소에서 불러온다.
  // 매개변수:
  // - notifyAfterLoad: 불러온 뒤 화면 갱신을 알릴지 여부
  // 반환값:
  // - 없음
  Future<void> loadTodayMedicationDoseStatuses({
    bool notifyAfterLoad = true,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final storedKeys =
        preferences.getStringList(_todayDoseStatusStorageKey()) ?? const [];
    _completedMedicationDoseKeys
      ..clear()
      ..addAll(storedKeys);

    if (notifyAfterLoad) {
      notifyListeners();
    }
  }

  // 함수명: isMedicationDoseCompleted
  // 함수역할:
  // - 특정 시간대에 표시된 약 한 줄이 오늘 완료 처리되었는지 확인한다.
  // 매개변수:
  // - slotKey: morning, lunch, evening, bedtime 중 하나
  // - schedule: 확인할 복약 일정
  // 반환값:
  // - 완료 처리되어 있으면 True
  bool isMedicationDoseCompleted(
    String slotKey,
    MedicationSchedule schedule,
  ) {
    return _completedMedicationDoseKeys.contains(
      _doseStatusKey(slotKey, schedule),
    );
  }

  List<String> slotKeysForSchedule(MedicationSchedule schedule) {
    return _slotKeysForSchedule(schedule);
  }

  // 함수명: requestMedicationDoseStatusUpdate
  // 함수역할:
  // - 특정 시간대의 복약 완료 상태를 오늘 날짜 기준 로컬 저장소에 저장한다.
  // 매개변수:
  // - slotKey: morning, lunch, evening, bedtime 중 하나
  // - schedule: 상태를 변경할 복약 일정
  // - medicationStatus: 새 완료 상태
  // 반환값:
  // - 저장 성공 여부
  Future<bool> requestMedicationDoseStatusUpdate(
    String slotKey,
    MedicationSchedule schedule,
    bool medicationStatus,
  ) async {
    final doseKey = _doseStatusKey(slotKey, schedule);
    if (medicationStatus) {
      _completedMedicationDoseKeys.add(doseKey);
    } else {
      _completedMedicationDoseKeys.remove(doseKey);
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(
        _todayDoseStatusStorageKey(),
        _completedMedicationDoseKeys.toList(growable: false),
      );
      notifyListeners();
      return true;
    } catch (_) {
      _statusMessage = '복약 완료 상태를 저장하지 못했습니다.';
      notifyListeners();
      return false;
    }
  }

  String _todayDoseStatusStorageKey() {
    final now = DateTime.now();
    return 'medbuddy_medication_dose_status_${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_${_todayScheduleStorageSignature()}';
  }

  String _doseStatusKey(String slotKey, MedicationSchedule schedule) {
    final medicationKey = [
      schedule.medicationID.trim(),
      _formatDateKey(schedule.scheduleStartDate),
      schedule.displayName,
      schedule.dosage,
      schedule.intakeTime,
      schedule.medicationTime.toString(),
    ].where((value) => value.trim().isNotEmpty).join('::');
    return '$slotKey::$medicationKey';
  }

  String _todayScheduleStorageSignature() {
    if (_todayMedicationScheduleList.isEmpty) {
      return 'empty';
    }

    final signatureSource = _todayMedicationScheduleList.map((schedule) {
      return [
        schedule.medicationID.trim(),
        _formatDateKey(schedule.scheduleStartDate),
        schedule.displayName,
        schedule.dosage,
        schedule.intakeTime,
        schedule.medicationTime.toString(),
      ].where((value) => value.trim().isNotEmpty).join('|');
    }).join('||');

    return _stableTextHash(signatureSource).toString();
  }

  String _formatDateKey(DateTime? value) {
    if (value == null) {
      return '';
    }
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  int _stableTextHash(String text) {
    var hash = 5381;
    for (final codeUnit in text.codeUnits) {
      hash = ((hash << 5) + hash + codeUnit) & 0x7fffffff;
    }
    return hash;
  }

  List<String> _slotKeysForSchedule(MedicationSchedule schedule) {
    final frequencyCount = schedule.dailyFrequencyCount;
    if (frequencyCount >= 4) {
      return const ['morning', 'lunch', 'evening', 'bedtime'];
    }
    if (frequencyCount == 3) {
      return const ['morning', 'lunch', 'evening'];
    }
    if (frequencyCount == 2) {
      return const ['morning', 'evening'];
    }
    return const ['morning'];
  }

  Future<bool> requestMedicationStatusUpdate(
    MedicationSchedule medicationSchedule,
    bool medicationStatus,
  ) async {
    if (medicationSchedule.medicationID.trim().isEmpty) {
      return false;
    }

    try {
      final updatedSchedule = await checkSchedule.updateMedicationStatus(
        medicationSchedule.medicationID,
        medicationStatus,
      );
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
      _statusMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _statusMessage = '복약 상태를 업데이트하지 못했습니다.';
      notifyListeners();
      return false;
    }
  }

  void clearAnalysisResult() {
    _recognizedMedicationScheduleList = [];
    _analyzedMedicationList = [];
    _completedMedicationSaveIndexes.clear();
    _isAllMedicationSaving = false;
    _savingMedicationIndex = null;
    _analysisErrorMessage = '';
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
    _recognizedMedicationScheduleList = [];
    _analyzedMedicationList = [];
    _analysisErrorMessage = '';
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;

    try {
      final result = await imageRequest(
        onImageSelected: _showPrescriptionRecognitionProgress,
      );
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
      _prescriptionFlowState = PrescriptionFlowState.previewReady;
      _statusMessage = '처방전 인식이 완료되었습니다.';
      notifyListeners();
    } on StateError catch (error) {
      _showAnalysisFailure(error.message);
    } catch (_) {
      _showAnalysisFailure('처방전 인식 중 오류가 발생했습니다.');
    }
  }

  void _showPrescriptionRecognitionProgress() {
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;
    _prescriptionFlowState = PrescriptionFlowState.recognizingPrescription;
    _statusMessage = '처방전을 인식 중입니다...';
    notifyListeners();
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

  @override
  void dispose() {
    inputPrescription.dispose();
    checkMedicationDetail.dispose();
    checkSavedMedication.dispose();
    checkSchedule.dispose();
    super.dispose();
  }
}
