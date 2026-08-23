part of 'medbuddy_view_model.dart';

// 파일명: medbuddy_user_setting_view_model.dart
// 역할: 사용자 설정, 초기 화면 데이터와 계정 데이터 삭제 흐름을 관리한다.

// 확장명: MedBuddyUserSettingViewModel
// 역할: MedBuddyViewModel의 해당 기능 상태 전이와 Control 호출을 한곳에 모은다.
extension MedBuddyUserSettingViewModel on MedBuddyViewModel {
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
    try {
      _userSetting = await manageUserSetting.requestUserSetting();
      await refreshMedicationOverview();
    } finally {
      _notifyViewModelListeners(MedBuddyFeature.userSetting);
    }
  }

  Future<void> refreshMedicationOverview() async {
    await Future.wait([
      loadMedicationReminderSettings(notifyAfterLoad: false),
      fetchTodayMedicationInfo(),
    ]);
    await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
  }

  Future<void> refreshMedicationSchedule() async {
    await Future.wait([
      loadMedicationReminderSettings(notifyAfterLoad: false),
      fetchTodayMedicationSchedule(),
    ]);
    await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
  }

  void clearAnalysisResult() {
    _cancelPrescriptionOperation();
    unawaited(inputPrescription.clearSelectedImage());
    _recognizedMedicationScheduleList = [];
    _recognizedTextRegionList = [];
    _prescriptionPreviewImagePath = '';
    _analyzedMedicationList = [];
    _prescriptionChangeRadar = null;
    _isPrescriptionChangeLoading = false;
    _completedMedicationSaveIndexes.clear();
    _isAllMedicationSaving = false;
    _savingMedicationIndex = null;
    _analysisErrorMessage = '';
    _clearPrescriptionRecognitionCounts();
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;
    _prescriptionFlowState = PrescriptionFlowState.idle;
    _statusMessage = _isEnglishSetting
        ? 'Take a prescription photo or choose an image.'
        : '처방전을 촬영하거나 이미지를 선택해주세요.';
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  Future<UserSettingSaveResult> requestUserSettingSave({
    required String fontSizeOption,
    required String readingSpeedOption,
    required String language,
  }) async {
    final saveResult = await manageUserSetting.saveUserSetting(
      currentSetting: _userSetting,
      fontSizeOption: fontSizeOption,
      readingSpeedOption: readingSpeedOption,
      language: language,
    );
    _userSetting = saveResult.setting;
    _notifyViewModelListeners(MedBuddyFeature.userSetting);
    return saveResult;
  }

  // 함수명: requestNearbyPharmacyLabSettingSave
  // 함수역할:
  // - 근처 운영 약국 실험 기능의 노출 설정을 기기에 저장하고 홈 화면에 반영한다.
  // 반환값:
  // - 없음
  Future<void> requestNearbyPharmacyLabSettingSave(bool enabled) async {
    _userSetting = await manageUserSetting.saveNearbyPharmacyLabSetting(
      currentSetting: _userSetting,
      enabled: enabled,
    );
    _notifyViewModelListeners(MedBuddyFeature.userSetting);
  }

  // 함수명: requestLinkedMedicationChatLabSettingSave
  // 함수역할:
  // - 복약 맥락 채팅 실험 기능의 노출 설정을 기기에 저장하고 연동 화면에 반영한다.
  // 반환값:
  // - 없음
  Future<void> requestLinkedMedicationChatLabSettingSave(bool enabled) async {
    _userSetting = await manageUserSetting.saveLinkedMedicationChatLabSetting(
      currentSetting: _userSetting,
      enabled: enabled,
    );
    _notifyViewModelListeners(MedBuddyFeature.userSetting);
  }

  // 함수명: requestAccountDataDeletion
  // 역할:
  // - 현재 사용자에게 연결된 서버 데이터와 기기 캐시의 전체 삭제를 요청한다.
  Future<void> requestAccountDataDeletion() async {
    await MedicationReminderBackgroundScheduler.cancel();
    await notificationService.cancelAllMedicationReminders();
    await manageAccount.deleteAccountData();
    clearAnalysisResult();
    _savedMedicationInfoList = [];
    _todayMedicationScheduleList = [];
    _notifyViewModelListeners();
  }
}
