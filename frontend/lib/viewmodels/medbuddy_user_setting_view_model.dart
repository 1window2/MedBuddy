part of 'medbuddy_view_model.dart';

// 파일명: medbuddy_user_setting_view_model.dart
// 역할: 사용자 설정, 초기 화면 데이터와 계정 데이터 삭제 흐름을 관리한다.

// 클래스명: MedBuddyUserSettingViewModel
// 역할: 사용자 설정·초기 일정 및 계정 삭제 흐름을 확장한다.
// 주요 책임:
// - 알림 개인정보 정책을 설정 변경과 동기화하고 새로고침과 분석 상태 초기화 및 세션 데이터 정리를 조정한다.
extension MedBuddyUserSettingViewModel on MedBuddyViewModel {
  // 함수이름: loadUserSetting
  // 함수역할: 앱 시작 시 로컬 사용자 설정, 알림 설정, 오늘 복약 일정을 함께 불러온다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> loadUserSetting() async {
    try {
      _userSetting = await manageUserSetting.requestUserSetting();
      notificationService.setShowSensitiveDetails(
        _userSetting.showNotificationDetails,
      );
      await refreshMedicationOverview();
    } finally {
      _notifyViewModelListeners(MedBuddyFeature.userSetting);
    }
  }

  // 함수이름: refreshMedicationOverview
  // 함수역할: 알림 설정과 오늘 복약 요약을 함께 조회하고 일정 조회가 성공한 경우에만 로컬 예약을 동기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> refreshMedicationOverview() async {
    await Future.wait([
      loadMedicationReminderSettings(notifyAfterLoad: false),
      fetchTodayMedicationInfo(),
    ]);
    await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
  }

  // 함수이름: refreshMedicationSchedule
  // 함수역할: 알림 설정과 오늘 전체 일정을 함께 조회하고 최신 일정으로 알림 예약을 동기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> refreshMedicationSchedule() async {
    await Future.wait([
      loadMedicationReminderSettings(notifyAfterLoad: false),
      fetchTodayMedicationSchedule(),
    ]);
    await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
  }

  // 함수이름: clearAnalysisResult
  // 함수역할: 진행 중 처방 응답을 무효화하고 선택 파일·OCR·분석·저장 진행 상태를 초기화해 입력 대기 화면으로 돌아간다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void clearAnalysisResult() {
    _cancelPrescriptionOperation();
    inputPrescription.cancelPendingRequests();
    unawaited(inputPrescription.clearSelectedImage());
    _recognizedMedicationScheduleList = [];
    _recognizedTextRegionList = [];
    _prescriptionPreviewImagePath = '';
    _analyzedMedicationList = [];
    _analyzedMedicationByScheduleIndex.clear();
    _unverifiedMedicationScheduleIndexes.clear();
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

  // 함수이름: requestUserSettingSave
  // 함수역할: 사용자 설정을 저장하고 알림 허용·민감정보 표시·언어 변경에 맞춰 기존 예약을 취소하거나 새로고침한 뒤 설정 구독자를 갱신한다.
  // 매개변수:
  // - fontSizeOption (String): small·medium·large 글씨 크기 선택값
  // - readingSpeedOption (String): slow·medium·fast 읽기 속도 선택값
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // - languageMode (String?): system·ko·en 언어 선택 모드
  // - timeFormat (String?): 12h 또는 24h 시각 표시 방식
  // - medicationNotificationsEnabled (bool?): 본인 복약 시간 알림 허용 여부
  // - caregiverNotificationsEnabled (bool?): 보호자 복약 상태 알림 허용 여부
  // - chatNotificationsEnabled (bool?): 가족 채팅 알림 허용 여부
  // - notificationDetailMode (String?): full 또는 type_only 알림 세부 표시 모드
  // - defaultMorningTime (String?): 새 아침 알림의 HH:mm 기본 시각
  // - defaultLunchTime (String?): 새 점심 알림의 HH:mm 기본 시각
  // - defaultEveningTime (String?): 새 저녁 알림의 HH:mm 기본 시각
  // - defaultBedtime (String?): 새 취침 전 알림의 HH:mm 기본 시각
  // 반환값:
  // - Future<UserSettingSaveResult>: 사용자 설정을 저장하고 알림 허용·민감정보 표시·언어 변경에 맞춰 기존 예약을 취소하거나 새로고침한 뒤 설정 구독자를 갱신한다.
  Future<UserSettingSaveResult> requestUserSettingSave({
    required String fontSizeOption,
    required String readingSpeedOption,
    required String language,
    String? languageMode,
    String? timeFormat,
    bool? medicationNotificationsEnabled,
    bool? caregiverNotificationsEnabled,
    bool? chatNotificationsEnabled,
    String? notificationDetailMode,
    String? defaultMorningTime,
    String? defaultLunchTime,
    String? defaultEveningTime,
    String? defaultBedtime,
  }) async {
    final previousMedicationNotificationsEnabled =
        _userSetting.medicationNotificationsEnabled;
    final previousNotificationDetailMode = _userSetting.notificationDetailMode;
    final previousIsEnglishSetting = _isEnglishSetting;
    final saveResult = await manageUserSetting.saveUserSetting(
      currentSetting: _userSetting,
      fontSizeOption: fontSizeOption,
      readingSpeedOption: readingSpeedOption,
      language: language,
      languageMode: languageMode,
      timeFormat: timeFormat,
      medicationNotificationsEnabled: medicationNotificationsEnabled,
      caregiverNotificationsEnabled: caregiverNotificationsEnabled,
      chatNotificationsEnabled: chatNotificationsEnabled,
      notificationDetailMode: notificationDetailMode,
      defaultMorningTime: defaultMorningTime,
      defaultLunchTime: defaultLunchTime,
      defaultEveningTime: defaultEveningTime,
      defaultBedtime: defaultBedtime,
    );
    _userSetting = saveResult.setting;
    notificationService.setShowSensitiveDetails(
      _userSetting.showNotificationDetails,
    );
    final shouldRefreshScheduledMessages =
        previousMedicationNotificationsEnabled &&
        _userSetting.medicationNotificationsEnabled &&
        (previousNotificationDetailMode !=
                _userSetting.notificationDetailMode ||
            previousIsEnglishSetting != _isEnglishSetting);
    if (previousMedicationNotificationsEnabled &&
        !_userSetting.medicationNotificationsEnabled) {
      await notificationService.cancelAllScheduledMedicationReminders();
    } else if (!previousMedicationNotificationsEnabled &&
        _userSetting.medicationNotificationsEnabled) {
      await refreshMedicationSchedule();
    } else if (shouldRefreshScheduledMessages) {
      // 이미 예약된 알림에도 새 언어와 잠금 화면 공개 수준을 즉시 반영한다.
      await refreshMedicationSchedule();
    }
    _notifyViewModelListeners(MedBuddyFeature.userSetting);
    return saveResult;
  }

  // Function Name: requestAccountDataDeletion
  // Description: Cancels reminder work and session notifications, requests server and local account-data deletion, then clears analysis, saved-medication, and schedule state.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
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
