// File Name: medbuddy_user_setting_view_model.dart
// Role: Owns user settings without accessing sibling feature state.
import '../controls/app_language_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../entities/user_setting_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../services/notification_service.dart';

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
  bool _settingLoaded = false;
  bool _hasUnsynchronizedSetting = false;
  Future<void> _settingOperations = Future<void>.value();
  Future<bool>? _deviceLanguageSynchronization;
  bool _deviceLanguageRetryRequested = false;
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
  // Description: Publishes settings-only changes. Parameters: None. Returns: None.
  void _notifyViewModelListeners() {
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
  Future<void> loadUserSetting() => _enqueueSettingOperation(_loadUserSetting);

  // 조회와 저장을 순서대로 처리해 늦은 응답이 새 선택이나 실패 후의 로컬 저장을 지우지 않게 한다.
  Future<T> _enqueueSettingOperation<T>(Future<T> Function() operation) {
    final result = _settingOperations.then((_) => operation());
    _settingOperations = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<void> _loadUserSetting() async {
    if (_disposed || _hasUnsynchronizedSetting) return;
    try {
      final setting = await manageUserSetting.requestUserSetting();
      if (_disposed) return;
      _userSetting = setting;
      _settingLoaded = true;
      // A save left pending by an earlier run is kept on the device; resume
      // retries must resend it instead of treating the cache as server state.
      _hasUnsynchronizedSetting =
          manageUserSetting.useRemotePersistence &&
          manageUserSetting.hasPendingSave;
      notificationService.setShowSensitiveDetails(
        _userSetting.showNotificationDetails,
      );
      await refreshMedicationOverview();
    } finally {
      _notifyViewModelListeners();
    }
  }

  // 함수이름: saveUserSetting
  // 함수역할: 설정 화면이 편집한 설정 전체를 값 변환 없이 저장하고, 선택지별 저장과 같은 알림·일정 후속 처리를 수행한다.
  // 매개변수:
  // - setting (UserSetting): 저장할 설정 전체
  // 반환값:
  // - Future<UserSettingSaveResult>: 저장된 설정과 서버 동기화 여부.
  Future<UserSettingSaveResult> saveUserSetting(UserSetting setting) {
    return _enqueueSettingOperation(
      () => _saveAndApply(() => manageUserSetting.saveUserSetting(setting)),
    );
  }

  // 함수이름: synchronizeDeviceLanguage
  // 함수역할: 기기 설정 따르기의 표시 언어를 갱신하고, 앱 복귀 때는 고정 언어에서도 실패한 설정 저장을 한 번 재시도한다.
  // 매개변수:
  // - retryRemoteLookup (bool): 앱 복귀 시 실패했던 조회와 서버 저장을 재시도할지 여부.
  // 반환값:
  // - Future<bool>: 언어 갱신이나 실패한 설정 저장을 시도했으면 true. 저장할 변경·재시도가 없거나 안전한 서버 기준값이 없으면 false.
  Future<bool> synchronizeDeviceLanguage({bool retryRemoteLookup = false}) {
    _deviceLanguageRetryRequested |= retryRemoteLookup;
    return _deviceLanguageSynchronization ??= _enqueueSettingOperation(() async {
      try {
        // 실행 전 합쳐진 복귀 요청은 첫 시도부터 반영한다.
        final retryAtStart = _deviceLanguageRetryRequested;
        var saved = await _synchronizeDeviceLanguage(
          retryRemoteLookup: retryAtStart,
        );
        // 실행 중 강화된 요청만 한 번 더 처리하고, 대기한 수동 저장보다 먼저 끝낸다.
        if (!retryAtStart && _deviceLanguageRetryRequested && !_disposed) {
          final retried = await _synchronizeDeviceLanguage(
            retryRemoteLookup: true,
          );
          saved = saved || retried;
        }
        return saved;
      } finally {
        _deviceLanguageRetryRequested = false;
        _deviceLanguageSynchronization = null;
      }
    });
  }

  // 함수이름: _synchronizeDeviceLanguage
  // 함수역할: 복귀 시 고정 언어의 미동기화 설정을 한 번 재전송하고, 기기 설정 따르기는 요청 중 바뀐 최신 언어까지 반영한다.
  // 매개변수:
  // - retryRemoteLookup (bool): 실패한 조회와 서버 저장을 재시도할지 여부.
  // 반환값:
  // - Future<bool>: 언어 갱신이나 실패한 설정 저장을 시도했으면 true.
  Future<bool> _synchronizeDeviceLanguage({
    required bool retryRemoteLookup,
  }) async {
    if (_disposed) return false;
    // 복귀 시 실패했던 조회만 재시도한다. 서버에 아직 반영하지 못한 사용자 설정은 재조회로 덮지 않는다.
    if (retryRemoteLookup &&
        !_hasUnsynchronizedSetting &&
        (!_settingLoaded ||
            (manageUserSetting.useRemotePersistence &&
                !manageUserSetting.lastLookupReachedServer))) {
      await _loadUserSetting();
    }
    if (_disposed || !_settingLoaded) {
      return false;
    }
    if (_userSetting.languageMode != 'system') {
      if (!retryRemoteLookup || !_hasUnsynchronizedSetting) return false;
      // 고정 언어는 기기 언어로 바꾸지 않고 복귀마다 미동기화 설정 전체만 한 번 보낸다.
      await _saveAndApply(
        () => manageUserSetting.saveUserSetting(_userSetting),
      );
      return true;
    }
    // 캐시로 대체한 설정을 자동으로 올리면 다른 기기에서 바꾼 서버 값을 덮어쓸 수 있다.
    if (manageUserSetting.useRemotePersistence &&
        !manageUserSetting.lastLookupReachedServer &&
        !_hasUnsynchronizedSetting) {
      return false;
    }
    var saved = false;
    while (!_disposed && _userSetting.languageMode == 'system') {
      final deviceLanguage = AppLanguageControl.resolveLanguage('system');
      if (deviceLanguage == _userSetting.language &&
          !(retryRemoteLookup && _hasUnsynchronizedSetting)) {
        break;
      }
      await _saveAndApply(
        () => manageUserSetting.saveUserSetting(
          _userSetting.copyWith(language: deviceLanguage),
        ),
      );
      saved = true;
      // 같은 기기 언어의 실패는 다음 복귀 때 재시도하고, 요청 중 바뀐 언어만 이어서 반영한다.
      if (deviceLanguage == AppLanguageControl.resolveLanguage('system')) break;
    }
    return saved;
  }

  // 함수이름: _saveAndApply
  // 함수역할: 설정을 저장한 뒤 알림 허용·민감정보 표시·언어·기본 시각 변경에 맞춰 예약을 취소하거나 새로고침하고 설정 구독자를 갱신한다.
  // 매개변수:
  // - save (Future<UserSettingSaveResult> Function()): 실제 저장을 수행하는 함수
  // 반환값:
  // - Future<UserSettingSaveResult>: 저장된 설정과 서버 동기화 여부.
  Future<UserSettingSaveResult> _saveAndApply(
    Future<UserSettingSaveResult> Function() save,
  ) async {
    if (_disposed) throw StateError('Settings state has been disposed.');
    final previousMedicationNotificationsEnabled =
        _userSetting.medicationNotificationsEnabled;
    final previousNotificationDetailMode = _userSetting.notificationDetailMode;
    final previousIsEnglishSetting = _isEnglishSetting;
    final previousDefaultTimes = {
      for (final slot in medicationScheduleSlotKeys)
        slot: _userSetting.defaultTimeForSlot(slot),
    };
    final saveResult = await save();
    if (_disposed) return saveResult;
    _userSetting = saveResult.setting;
    _settingLoaded = true;
    _hasUnsynchronizedSetting =
        manageUserSetting.useRemotePersistence &&
        !saveResult.synchronizedWithServer;
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
    _notifyViewModelListeners();
    return saveResult;
  }
}
