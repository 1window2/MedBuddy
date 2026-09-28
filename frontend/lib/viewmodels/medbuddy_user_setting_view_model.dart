// File Name: medbuddy_user_setting_view_model.dart
// Role: Owns user settings without accessing sibling feature state.
import '../controls/manage_user_setting_control.dart';
import '../entities/user_setting_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../services/notification_service.dart';
import 'medbuddy_feature_updates.dart';

// Class Name: MedBuddyUserSettingViewModel
// Role: Settings state owner.
// Responsibilities: Persist settings and request explicit cross-feature refreshes.
class MedBuddyUserSettingViewModel {
  UserSetting _userSetting = const UserSetting();
  // Function Name: userSetting
  // 함수역할: 현재 환자 범위의 접근성·언어·알림 설정을 제공한다.
  // Parameters:
  // - None.
  // Returns:
  // - UserSetting: User settings including language, accessibility, and notification policy.
  UserSetting get userSetting => _userSetting;
  final ManageUserSetting manageUserSetting;
  final NotificationService notificationService;
  final Future<void> Function() refreshMedicationOverview;
  final Future<void> Function() refreshMedicationSchedule;
  final Future<void> Function({bool notifyAfterLoad})
  loadMedicationReminderSettings;
  final void Function() _onChanged;
  final bool Function() _readEnglish;
  bool _disposed = false;
  // Function Name: MedBuddyUserSettingViewModel
  // Description: Binds settings persistence and narrow refresh operations.
  // Parameters: Borrowed dependencies and callbacks. Returns: Settings state owner.
  MedBuddyUserSettingViewModel({
    required this.manageUserSetting,
    required this.notificationService,
    required this.refreshMedicationOverview,
    required this.refreshMedicationSchedule,
    required this.loadMedicationReminderSettings,
    required void Function() onChanged,
    required bool Function() readEnglish,
  }) : _onChanged = onChanged,
       _readEnglish = readEnglish;
  // Function Name: _isEnglishSetting
  // Description: Reads current display locale. Parameters: None. Returns: English selection.
  bool get _isEnglishSetting => _readEnglish();
  // Function Name: _notifyViewModelListeners
  // Description: Publishes settings-only changes. Parameters: feature: Tag. Returns: None.
  void _notifyViewModelListeners(MedBuddyFeature feature) {
    if (!_disposed) _onChanged();
  }

  // Function Name: dispose
  // Description: Stops subsequent publication. Parameters: None. Returns: None.
  void dispose() {
    _disposed = true;
  }

  // 함수이름: loadUserSetting
  // 함수역할: 앱 시작 시 로컬 사용자 설정, 알림 설정, 오늘 복약 일정을 함께 불러온다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> loadUserSetting() async {
    if (_disposed) return;
    try {
      final setting = await manageUserSetting.requestUserSetting();
      if (_disposed) return;
      _userSetting = setting;
      notificationService.setShowSensitiveDetails(
        _userSetting.showNotificationDetails,
      );
      await refreshMedicationOverview();
    } finally {
      _notifyViewModelListeners(MedBuddyFeature.userSetting);
    }
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
    String? homeScheduleSource,
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
    final previousDefaultTimes = {
      for (final slot in medicationScheduleSlotKeys)
        slot: _userSetting.defaultTimeForSlot(slot),
    };
    final saveResult = await manageUserSetting.saveUserSetting(
      currentSetting: _userSetting,
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
    if (_disposed) return saveResult;
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
    if (saveResult.synchronizedWithServer &&
        previousDefaultTimes.entries.any(
          (entry) => entry.value != _userSetting.defaultTimeForSlot(entry.key),
        )) {
      // Refresh unsaved defaults for the next schedule/configuration screen.
      // This read preserves explicit alarms and must not replace native snoozes.
      await loadMedicationReminderSettings();
    }
    _notifyViewModelListeners(MedBuddyFeature.userSetting);
    return saveResult;
  }
}
