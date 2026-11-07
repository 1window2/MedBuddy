import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../controls/as_needed_check_reminder_control.dart';
import '../controls/set_notification_control.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/medication_slot_label.dart';
import '../entities/user_setting_entity.dart';
import '../services/notification_service.dart';
import '../services/medication_reminder_background_service.dart';
import 'medbuddy_schedule_slot_policy.dart';

// 파일명: medbuddy_reminder_view_model.dart
// 역할: 시간대별 복약 알림의 조회, 저장, 취소, 로컬 동기화를 관리한다.

// 클래스명: MedBuddyReminderViewModel
// 역할: 시간대별 서버 알림 설정과 로컬 예약 상태를 관리한다.
// 주요 책임: 캐시 복원·권한 확인·저장 롤백을 수행하고 세대 검사로 늦은 동기화를 차단한다.
// 속성: patientHash: 계정; 설정·알림 경계와 일정 읽기 콜백: 의존성; 설정 맵·쓰기 집합·동기화 Future·조회 세대: 상태.
class MedBuddyReminderViewModel {
  bool _lastReminderSettingsLoadSucceeded = false;
  final Map<String, MedicationAlarm> _medicationReminderSettings = {};
  // Function Name: medicationReminderSettings
  // Description: Exposes an unmodifiable slot-keyed map of the current medication alarm settings.
  // Parameters:
  // - None.
  // Returns:
  // - Map<String, MedicationAlarm>: An unmodifiable slot-keyed map of the current medication alarm settings.
  Map<String, MedicationAlarm> get medicationReminderSettings =>
      Map.unmodifiable(_medicationReminderSettings);
  final SetNotification setNotification;
  final NotificationService notificationService;
  final String patientHash;
  final UserSetting Function() _readUserSetting;
  final List<MedicationSchedule> Function() _readSchedules;
  final bool Function() _scheduleIsFresh;
  // 앞으로 14일 안에 복용 기간이 걸치는 약을 읽는다. 오늘 일정에는 오늘 복용하는 약만 있어, 주 1회·격일 약이
  // 쉬는 날에는 그 약이 보이지 않기 때문에 알림 날짜와 "빈 시간대" 판단은 이 목록으로 한다.
  final Future<List<MedicationSchedule>> Function()? _loadScheduleWindow;
  final void Function(String) _onChanged;
  bool _disposed = false;
  int _loadGeneration = 0;
  final Set<String> _writingSlots = {};
  Future<void>? _synchronization;
  int? _synchronizationGeneration;
  String _statusMessage = '';
  // Function Name: MedBuddyReminderViewModel
  // Description: Bind reminder settings to borrowed notification boundaries and read-only schedule snapshots.
  // Parameters: setNotification (SetNotification): server settings and registration; notificationService (NotificationService): platform alerts; patientHash (String): owner; readUserSetting (UserSetting Function()): preferences; readSchedules (List<MedicationSchedule> Function()): today's projection; scheduleIsFresh (bool Function()): freshness guard; loadScheduleWindow (Future<List<MedicationSchedule>> Function()?): course-window loader; onChanged (void Function(String)): feature updates.
  // Returns: MedBuddyReminderViewModel: reminder state owner.
  MedBuddyReminderViewModel({
    required this.setNotification,
    required this.notificationService,
    required this.patientHash,
    required UserSetting Function() readUserSetting,
    required List<MedicationSchedule> Function() readSchedules,
    required bool Function() scheduleIsFresh,
    Future<List<MedicationSchedule>> Function()? loadScheduleWindow,
    required void Function(String) onChanged,
  }) : _readUserSetting = readUserSetting,
       _readSchedules = readSchedules,
       _scheduleIsFresh = scheduleIsFresh,
       _loadScheduleWindow = loadScheduleWindow,
       _onChanged = onChanged;
  // Function Name: userSetting
  // Description: Reads current settings without owning them. Parameters: None. Returns: Settings.
  UserSetting get userSetting => _readUserSetting();
  // Function Name: _isEnglishSetting
  // Description: Resolves locale. Parameters: None. Returns: English selection.
  bool get _isEnglishSetting => userSetting.isEnglish;
  // Function Name: lastLoadSucceeded
  // Description: Exposes reminder-read freshness. Parameters: None. Returns: Freshness.
  bool get lastLoadSucceeded => _lastReminderSettingsLoadSucceeded;
  // Function Name: statusMessage
  // Description: Exposes reminder-only feedback. Parameters: None. Returns: Feedback.
  String get statusMessage => _statusMessage;
  // Function Name: _notifyViewModelListeners
  // Description: Publishes live feature state. Parameters: None. Returns: None.
  void _notifyViewModelListeners() {
    if (!_disposed) _onChanged(_statusMessage);
  }

  // Function Name: dispose
  // Description: Stops notifications without disposing borrowed services. Parameters: None. Returns: None.
  void dispose() {
    _disposed = true;
    _loadGeneration++;
  }

  // 함수이름: restoreAfterAbortedSignOut
  // 함수역할: 실패한 로그아웃 뒤 서버 설정을 끄거나 새 시각을 추측하지 않고 저장된 알림을 복원한다.
  // 매개변수: isCurrent: 세션 유효성 검사; courses: 선택적 기간 일정; lastAllowedDate: 복원 예약의 마지막 허용일, 없으면 현재 날짜.
  // 반환값: 복원 시도 완료; 세션 변경·알림 비허용은 중단하고 개별 시간대 오류는 다른 복원을 막지 않는다.
  Future<void> restoreAfterAbortedSignOut({
    required bool Function() isCurrent,
    List<MedicationSchedule>? courses,
    DateTime? lastAllowedDate,
  }) async {
    // 함수이름: current
    // 함수역할: 복원 도중 모델 수명과 로그인 세션이 모두 유효한지 확인한다.
    // 매개변수: 없음.
    // 반환값: 종료되지 않았고 상위 isCurrent 검사가 참이면 true.
    bool current() => !_disposed && isCurrent();
    if (!current()) return;
    if (_synchronization != null) await _synchronization;
    if (!current()) return;
    if (_medicationReminderSettings.isEmpty) {
      await _loadMedicationReminderSettingsFromCache(_loadGeneration);
    }
    if (!current() || !userSetting.medicationNotificationsEnabled) return;
    notificationService.setShowSensitiveDetails(
      userSetting.showNotificationDetails,
    );
    await _restoreAsNeededCheckReminder(current);
    for (final setting in _medicationReminderSettings.values.toList()) {
      if (!current()) return;
      if (!setting.isEnabled) continue;
      try {
        await _scheduleMedicationReminder(
          setting: setting,
          slotTitle: _reminderSlotTitle(setting.slotKey),
          schedules: _schedulesForReminderSlot(setting.slotKey),
          courseSchedules: courses == null
              ? null
              : _schedulesForSlot(courses, setting.slotKey),
          isCurrent: current,
          lastAllowedDate: lastAllowedDate ?? DateTime.now(),
        );
      } catch (_) {
        // 한 시간대의 플러그인 오류 때문에 다른 시간대 복구를 건너뛰지 않는다.
      }
    }
  }

  // Function Name: loadMedicationReminderSettings
  // Description: Loads server reminder settings with slot defaults and persistent cache, falling back to cache on failure.
  // Parameters: notifyAfterLoad: Whether to publish the applied load.
  // Returns: Completion; writes/disposal suppress loading and obsolete generations do not publish state.
  Future<void> loadMedicationReminderSettings({
    bool notifyAfterLoad = true,
  }) async {
    if (_disposed || _writingSlots.isNotEmpty) return;
    final generation = ++_loadGeneration;
    _lastReminderSettingsLoadSucceeded = false;
    try {
      final settings = await setNotification.requestMedicationAlarm();
      if (_disposed || generation != _loadGeneration) return;
      final settingsBySlot = {
        for (final slotKey in medicationScheduleSlotKeys)
          slotKey: _defaultMedicationAlarm(slotKey),
      };
      for (final setting in settings) {
        if (medicationScheduleSlotKeys.contains(setting.slotKey)) {
          // 비활성 상태에서도 사용자가 마지막으로 지정한 시각을 보존한다.
          settingsBySlot[setting.slotKey] = setting;
        }
      }
      _medicationReminderSettings
        ..clear()
        ..addAll(settingsBySlot);

      final preferences = await SharedPreferences.getInstance();
      if (_disposed || generation != _loadGeneration) return;
      for (final setting in settingsBySlot.values) {
        if (_disposed || generation != _loadGeneration) return;
        await _cacheMedicationReminderSetting(preferences, setting);
      }
      if (!_disposed && generation == _loadGeneration) {
        _lastReminderSettingsLoadSucceeded = true;
      }
    } catch (_) {
      if (_disposed || generation != _loadGeneration) return;
      await _loadMedicationReminderSettingsFromCache(generation);
    }

    if (notifyAfterLoad && !_disposed && generation == _loadGeneration) {
      _notifyViewModelListeners();
    }
  }

  // 함수이름: requestMedicationReminderSave
  // 함수역할: 사용자가 설정한 시간대별 복약 알림을 휴대폰 로컬 알림으로 예약한다.
  // 매개변수:
  // - slotKey (String): morning, lunch, evening, bedtime 중 하나
  // - slotTitle (String): 사용자에게 보여줄 시간대명
  // - hour (int): 24시간 기준 시
  // - minute (int): 분
  // - schedules (List<MedicationSchedule>): 해당 시간대에 복용할 약 목록
  // 반환값:
  // - 알림 예약 성공 여부
  Future<bool> requestMedicationReminderSave({
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<MedicationSchedule> schedules,
  }) => _runReminderWrite(
    slotKey,
    () => _saveMedicationReminder(
      slotKey: slotKey,
      slotTitle: slotTitle,
      hour: hour,
      minute: minute,
      schedules: schedules,
    ),
  );

  // 함수이름: _runReminderWrite
  // 함수역할: 같은 시간대 중복 쓰기를 거절하고 이전 조회·자동 동기화 이후에 최신 사용자 변경을 적용한다.
  // 매개변수: slotKey: 쓰기 잠금 대상; write: 실행할 저장 작업.
  // 반환값: 저장 결과 Future; 중복·종료는 false, 예외는 전파하되 잠금은 항상 해제한다.
  Future<bool> _runReminderWrite(
    String slotKey,
    Future<bool> Function() write,
  ) async {
    if (_disposed || !_writingSlots.add(slotKey)) return false;
    _loadGeneration++;
    try {
      // 이미 시작된 서버·기기·캐시 작업을 마친 뒤 최신 사용자 설정을 적용한다.
      final synchronization = _synchronization;
      if (synchronization != null) await synchronization;
      if (_disposed) return false;
      return await write();
    } finally {
      _writingSlots.remove(slotKey);
    }
  }

  // Function Name: _saveMedicationReminder
  // Description: Saves an enabled reminder after checking notification permission and eligible current/future courses.
  // Parameters: slotKey/slotTitle: Slot identity and label; hour/minute: Requested time; schedules: Current-day medications.
  // Returns: True after server, native and cache updates; refusal/failure returns false with feedback and attempts rollback after a persisted setting fails locally.
  Future<bool> _saveMedicationReminder({
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<MedicationSchedule> schedules,
  }) async {
    final storageKey = _reminderStorageKey(slotKey);
    if (!userSetting.medicationNotificationsEnabled) {
      _statusMessage = _isEnglishSetting
          ? 'Turn on medication notifications in Settings first.'
          : '환경설정에서 내 복약 알림을 먼저 켜주세요.';
      _notifyViewModelListeners();
      return false;
    }
    // 오늘 복용할 약이 없는 시간대라도 앞으로 14일 안에 복용하는 날이 있으면(주 1회 약의 쉬는 날 등)
    // 알림을 켤 수 있어야 한다. 그렇지 않으면 복용하는 날에 앱을 열어야만 알림을 설정할 수 있다.
    List<MedicationSchedule>? window;
    if (schedules.isEmpty) {
      window = await _loadScheduleWindowOrNull();
      if (_disposed) return false;
      if (window == null || _schedulesForSlot(window, slotKey).isEmpty) {
        _statusMessage = _isEnglishSetting
            ? 'There is no medication in this time slot.'
            : '이 시간대에 복용할 약이 없습니다.';
        _notifyViewModelListeners();
        return false;
      }
    }

    bool hasPermission;
    try {
      hasPermission = await notificationService.requestPermission();
    } catch (_) {
      if (_disposed) return false;
      _statusMessage = _isEnglishSetting
          ? 'Could not request notification permission.'
          : '알림 권한을 요청하지 못했습니다.';
      _notifyViewModelListeners();
      return false;
    }
    if (_disposed) return false;
    if (!hasPermission) {
      _statusMessage = _isEnglishSetting
          ? 'Notification permission was not allowed.'
          : '알림 권한이 허용되지 않았습니다.';
      _notifyViewModelListeners();
      return false;
    }

    MedicationAlarm? persistedSetting;
    try {
      final setting = await setNotification.saveNotificationSetting(
        slotKey: slotKey,
        hour: hour,
        minute: minute,
      );
      if (_disposed) return false;
      persistedSetting = setting;

      window ??= await _loadScheduleWindowOrNull();
      await _scheduleMedicationReminder(
        setting: setting,
        slotTitle: slotTitle,
        schedules: schedules,
        courseSchedules: window == null
            ? null
            : _schedulesForSlot(window, setting.slotKey),
      );
      if (_disposed) return false;

      final preferences = await SharedPreferences.getInstance();
      if (_disposed) return false;
      await _cacheMedicationReminderSetting(
        preferences,
        setting,
        storageKey: storageKey,
      );
      if (_disposed) return false;
      _medicationReminderSettings[setting.slotKey] = setting;
      final displayTime = userSetting.formatTime(setting.hour, setting.minute);
      _statusMessage = _isEnglishSetting
          ? '$slotTitle reminder is set for $displayTime.'
          : '$slotTitle 알림이 $displayTime으로 설정되었습니다.';
      _notifyViewModelListeners();
      return true;
    } on StateError {
      if (_disposed) return false;
      await _rollbackMedicationReminderSave(
        alarmControl: setNotification,
        setting: persistedSetting,
        storageKey: storageKey,
      );
      _statusMessage = _isEnglishSetting
          ? 'Could not set the $slotTitle reminder.'
          : '$slotTitle 알림을 설정하지 못했습니다.';
      _notifyViewModelListeners();
      return false;
    } catch (_) {
      if (_disposed) return false;
      await _rollbackMedicationReminderSave(
        alarmControl: setNotification,
        setting: persistedSetting,
        storageKey: storageKey,
      );
      _statusMessage = _isEnglishSetting
          ? 'Could not set the $slotTitle reminder.'
          : '$slotTitle 알림을 설정하지 못했습니다.';
      _notifyViewModelListeners();
      return false;
    }
  }

  // 함수이름: requestMedicationReminderCancel
  // 함수역할: 이미 활성화된 시간대별 복약 알림을 취소하고 로컬 설정을 비활성화한다. 같은 저장에서 시각도
  //   바꿨다면 그 시각을 꺼진 알림과 함께 저장한다.
  // 매개변수:
  // - slotKey (String): morning, lunch, evening, bedtime 중 하나
  // - slotTitle (String): 사용자에게 보여줄 시간대명
  // - hour (int?): 함께 저장할 새 알림 시; 생략하면 저장된 시각을 유지한다
  // - minute (int?): 함께 저장할 새 알림 분
  // 반환값:
  // - 알림 취소 성공 여부
  Future<bool> requestMedicationReminderCancel({
    required String slotKey,
    required String slotTitle,
    int? hour,
    int? minute,
  }) => _runReminderWrite(
    slotKey,
    () => _disableMedicationReminder(
      slotKey: slotKey,
      slotTitle: slotTitle,
      hour: hour,
      minute: minute,
    ),
  );

  // Function Name: _disableMedicationReminder
  // Description: Disables the server reminder, cancels native reservations and caches the returned setting.
  // Parameters: slotKey/slotTitle: Target slot and label; hour/minute: Optional disabled-time change.
  // Returns: True when all requested effects are confirmed; false on failure or when an older server disables the alarm but ignores the requested time.
  Future<bool> _disableMedicationReminder({
    required String slotKey,
    required String slotTitle,
    int? hour,
    int? minute,
  }) async {
    final storageKey = _reminderStorageKey(slotKey);
    try {
      final disabledSetting = await setNotification.disableAlarmSetting(
        slotKey,
        hour: hour,
        minute: minute,
      );
      if (_disposed) return false;
      await _cancelMedicationReminder(disabledSetting);
      if (_disposed) return false;
      final preferences = await SharedPreferences.getInstance();
      if (_disposed) return false;
      await _cacheMedicationReminderSetting(
        preferences,
        disabledSetting,
        storageKey: storageKey,
      );
      if (_disposed) return false;
      _medicationReminderSettings[disabledSetting.slotKey] = disabledSetting;
      // 구형 서버가 시각을 무시해도 알림은 끄고, 시각 저장 성공으로 표시하지 않는다.
      if (hour != null &&
          (disabledSetting.hour != hour ||
              disabledSetting.minute != (minute ?? 0))) {
        _statusMessage = _isEnglishSetting
            ? 'The reminder is off, but its time could not be updated.'
            : '알림은 꺼졌지만 시각을 변경하지 못했습니다.';
        _notifyViewModelListeners();
        return false;
      }
      _statusMessage = _isEnglishSetting
          ? '$slotTitle reminder has been turned off.'
          : '$slotTitle 알림이 해제되었습니다.';
      _notifyViewModelListeners();
      return true;
    } catch (_) {
      if (_disposed) return false;
      _statusMessage = _isEnglishSetting
          ? 'Could not turn off the $slotTitle reminder.'
          : '$slotTitle 알림을 해제하지 못했습니다.';
      _notifyViewModelListeners();
      return false;
    }
  }

  // 함수이름: _reminderStorageKey
  // 함수역할: 현재 환자 해시와 시간대를 포함한 알림 설정 캐시 키를 만든다.
  // 매개변수:
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - String: 현재 환자 해시와 시간대를 포함한 알림 설정 캐시 키를 만든다.
  String _reminderStorageKey(String slotKey) {
    return 'medbuddy_medication_reminder_'
        'patient_${patientHash}_'
        '${patientHash}_$slotKey';
  }

  // 함수이름: _legacyReminderStorageKey
  // 함수역할: 사용자 범위가 분리되기 전의 시간대 전용 캐시 키를 제공해 기존 설정을 복원한다.
  // 매개변수:
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - String: 사용자 범위가 분리되기 전의 시간대 전용 캐시 키를 제공해 기존 설정을 복원한다.
  String _legacyReminderStorageKey(String slotKey) {
    return 'medbuddy_medication_reminder_$slotKey';
  }

  // 함수이름: _cacheMedicationReminderSetting
  // 함수역할: 알림 설정을 JSON으로 직렬화해 지정된 키 또는 현재 환자·시간대 캐시 키로 저장한다.
  // 매개변수:
  // - preferences (SharedPreferences): 사용자별 설정·알림 기록을 읽고 쓸 기기 저장소
  // - setting (MedicationAlarm): 해당 복약 시간대의 알림 설정
  // - storageKey (String?): 사용자·시간대 설정을 저장할 기기 키
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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

  // 함수이름: _rollbackMedicationReminderSave
  // 함수역할: 로컬 예약 실패 후 이미 저장된 알림을 취소하고 서버 비활성화를 시도하며 실패하더라도 비활성 캐시를 남긴다.
  // 매개변수:
  // - alarmControl (SetNotification): 알림 설정 저장·비활성화를 담당하는 Control
  // - setting (MedicationAlarm?): 해당 복약 시간대의 알림 설정
  // - storageKey (String): 사용자·시간대 설정을 저장할 기기 키
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _rollbackMedicationReminderSave({
    required SetNotification alarmControl,
    required MedicationAlarm? setting,
    required String storageKey,
  }) async {
    if (_disposed || setting == null) {
      return;
    }

    try {
      await _cancelMedicationReminder(setting);
    } catch (_) {
      // Local cancellation is best-effort while restoring cross-system state.
    }
    if (_disposed) return;

    MedicationAlarm disabledSetting = setting.copyWith(enabled: false);
    try {
      disabledSetting = await alarmControl.disableAlarmSetting(setting.slotKey);
    } catch (_) {
      // The disabled cache state prevents an offline reload from rescheduling it.
    }
    if (_disposed) return;

    try {
      final preferences = await SharedPreferences.getInstance();
      if (_disposed) return;
      await _cacheMedicationReminderSetting(
        preferences,
        disabledSetting,
        storageKey: storageKey,
      );
    } catch (_) {
      // Cache rollback is best-effort after backend or plugin failure.
    }
  }

  // Function Name: _loadMedicationReminderSettingsFromCache
  // Description: Restores account cache before legacy slot cache, replacing absent or malformed entries with disabled user-default alarms.
  // Parameters: generation: Reminder-load generation allowed to receive the cache.
  // Returns: Completion; disposal or a changed generation prevents applying the read.
  Future<void> _loadMedicationReminderSettingsFromCache(int generation) async {
    final preferences = await SharedPreferences.getInstance();
    if (_disposed || generation != _loadGeneration) return;
    for (final slotKey in medicationScheduleSlotKeys) {
      final rawSetting =
          preferences.getString(_reminderStorageKey(slotKey)) ??
          preferences.getString(_legacyReminderStorageKey(slotKey));
      if (rawSetting == null || rawSetting.trim().isEmpty) {
        _medicationReminderSettings[slotKey] = _defaultMedicationAlarm(slotKey);
        continue;
      }

      try {
        final decodedSetting = jsonDecode(rawSetting);
        if (decodedSetting is Map<String, dynamic>) {
          final cachedSetting = MedicationAlarm.fromJson(decodedSetting);
          // 서버 연결이 끊겨도 기존 알림 시각을 기본값으로 덮어쓰지 않는다.
          _medicationReminderSettings[slotKey] = cachedSetting;
          continue;
        }
      } catch (_) {
        // Invalid cache entries are ignored and replaced with defaults.
      }
      _medicationReminderSettings[slotKey] = _defaultMedicationAlarm(slotKey);
    }
  }

  // Function Name: _synchronizeMedicationReminderSchedules
  // Description: Reconciles reminders under a current-generation guard using present schedules and an optional future window.
  // Parameters: isCurrent: Ownership predicate checked across asynchronous steps.
  // Returns: Completion; confirmed empty slots are disabled, unavailable future windows do not disable off-day courses, and errors propagate.
  Future<void> _synchronizeMedicationReminderSchedules(
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return;
    if (!userSetting.medicationNotificationsEnabled) {
      await notificationService.cancelAllScheduledMedicationReminders();
      return;
    }
    await _restoreAsNeededCheckReminder(isCurrent);
    if (!isCurrent()) return;
    if (_medicationReminderSettings.isEmpty) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    // 켜진 알림이 있을 때만 한 번 읽는다. 읽지 못하면 null로 두고 오늘 일정만으로 판단한다.
    List<MedicationSchedule>? window;
    var windowRequested = false;
    for (final slotKey in medicationScheduleSlotKeys) {
      if (!isCurrent()) return;
      final setting =
          _medicationReminderSettings[slotKey] ??
          _defaultMedicationAlarm(slotKey);
      if (!setting.isEnabled) {
        await _cancelMedicationReminder(setting, isCurrent: isCurrent);
        continue;
      }

      if (!windowRequested) {
        windowRequested = true;
        window = await _loadScheduleWindowOrNull();
        if (!isCurrent()) return;
      }
      final schedules = _schedulesForReminderSlot(slotKey);
      final courseSchedules = window == null
          ? null
          : _schedulesForSlot(window, slotKey);
      if (schedules.isEmpty && (courseSchedules?.isNotEmpty ?? false)) {
        // 오늘은 쉬는 날인 약만 있는 시간대다. 알림 설정은 그대로 두고 복용하는 날짜에만 예약한다.
        await _scheduleMedicationReminder(
          setting: setting,
          slotTitle: _reminderSlotTitle(slotKey),
          schedules: schedules,
          courseSchedules: courseSchedules,
          isCurrent: isCurrent,
        );
        continue;
      }
      if (schedules.isEmpty) {
        // 기간 일정을 읽지 못했으면 오늘 일정이 비었다는 것만으로 알림을 끄지 않는다. 매일 먹지 않는 약만
        // 있는 시간대일 수 있고, 꺼진 설정은 복용하는 날에도 알림이 오지 않게 만든다.
        if (_loadScheduleWindow != null && window == null) {
          continue;
        }
        final disabledSetting = await _disableReminderSettingForEmptySlot(
          setNotification,
          slotKey,
          setting,
        );
        if (!isCurrent()) return;
        await _cacheMedicationReminderSetting(preferences, disabledSetting);
        if (!isCurrent()) return;
        _medicationReminderSettings[disabledSetting.slotKey] = disabledSetting;
        await _cancelMedicationReminder(disabledSetting, isCurrent: isCurrent);
        continue;
      }

      await _scheduleMedicationReminder(
        setting: setting,
        slotTitle: _reminderSlotTitle(slotKey),
        schedules: schedules,
        courseSchedules: courseSchedules,
        isCurrent: isCurrent,
      );
    }
  }

  // Function Name: _restoreAsNeededCheckReminder
  // Description: Restores the account's persisted one-time as-needed check without blocking regular reminder synchronization.
  // Parameters: isCurrent: Predicate used to reject account changes.
  // Returns: Completion after restore or ignored failure; the temporary controller is always disposed.
  Future<void> _restoreAsNeededCheckReminder(bool Function() isCurrent) async {
    final reminder = AsNeededCheckReminderControl(
      patientHash: patientHash,
      notifications: notificationService,
      ensureSession: () {
        if (!isCurrent()) throw StateError('Account changed.');
      },
    );
    try {
      await reminder.restore(allowed: true, isEnglish: _isEnglishSetting);
    } catch (_) {
      // 알림 기능을 읽지 못해도 정기 알림 동기화는 계속한다.
    } finally {
      reminder.dispose();
    }
  }

  // Function Name: _loadScheduleWindowOrNull
  // Description: Reads the injected future schedule window when available.
  // Parameters: None.
  // Returns: The course list, or null when no loader is supplied or the lookup fails.
  Future<List<MedicationSchedule>?> _loadScheduleWindowOrNull() async {
    final loadScheduleWindow = _loadScheduleWindow;
    if (loadScheduleWindow == null) return null;
    try {
      return await loadScheduleWindow();
    } catch (_) {
      return null;
    }
  }

  // Function Name: _schedulesForSlot
  // Description: Filters a course list to schedules whose resolved slots include the target.
  // Parameters: schedules: Candidate courses; slotKey: Reminder slot.
  // Returns: A fixed-length list of matching schedules.
  List<MedicationSchedule> _schedulesForSlot(
    List<MedicationSchedule> schedules,
    String slotKey,
  ) {
    return schedules
        .where(
          (schedule) => resolveScheduleSlotKeys(schedule).contains(slotKey),
        )
        .toList(growable: false);
  }

  // Function Name: synchronizeIfFresh
  // Description: Synchronizes only after fresh schedule and reminder-setting loads, sharing work within a generation.
  // Parameters: None.
  // Returns: Completion of the shared/queued synchronization; current-generation failures become reminder feedback without changing schedule-load success.
  Future<void> synchronizeIfFresh() {
    if (_disposed ||
        _writingSlots.isNotEmpty ||
        !_scheduleIsFresh() ||
        !_lastReminderSettingsLoadSucceeded) {
      return Future<void>.value();
    }
    final pending = _synchronization;
    final generation = _loadGeneration;
    if (pending != null && _synchronizationGeneration == generation) {
      return pending;
    }
    _synchronizationGeneration = generation;
    // 함수이름: isCurrent
    // 함수역할: 동기화 시작 시의 조회 세대와 모델 수명이 유지되는지 검사한다.
    // 매개변수: 없음.
    // 반환값: 종료되지 않았고 현재 조회 세대와 같으면 true.
    bool isCurrent() => !_disposed && generation == _loadGeneration;
    late final Future<void> synchronization;
    // 같은 세대는 합치되, 새 조회의 동기화는 이전 작업 뒤에서 다시 검사한다.
    synchronization = (pending ?? Future<void>.value())
        .then((_) => _synchronizeMedicationReminderSchedules(isCurrent))
        .catchError((Object _) {
          if (!isCurrent()) return;
          _statusMessage = _isEnglishSetting
              ? 'The schedule loaded, but reminders could not be synchronized.'
              : '복약 일정은 불러왔지만 알림을 동기화하지 못했습니다.';
          _notifyViewModelListeners();
        })
        .whenComplete(() {
          if (identical(_synchronization, synchronization)) {
            _synchronization = null;
          }
        });
    return _synchronization = synchronization;
  }

  // 함수이름: _canContinueReminder
  // 함수역할: 수동 예약은 모델 수명을, 자동 예약은 추가 작업 소유권까지 확인한다.
  // 매개변수: isCurrent: 선택적 세대·세션 검사 함수.
  // 반환값: 모델이 살아 있고 제공된 검사가 통과하면 true.
  bool _canContinueReminder(bool Function()? isCurrent) =>
      !_disposed && (isCurrent?.call() ?? true);

  // 함수이름: _disableReminderSettingForEmptySlot
  // 함수역할: 빈 시간대의 서버 알림 비활성화를 시도하고 실패하면 기존 설정의 비활성 사본으로 대체한다.
  // 매개변수:
  // - alarmControl (SetNotification): 알림 설정 저장·비활성화를 담당하는 Control
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // - fallbackSetting (MedicationAlarm): 서버 비활성화 실패 시 보존할 알림 설정
  // 반환값:
  // - Future<MedicationAlarm>: 빈 시간대의 서버 알림 비활성화를 시도하고 실패하면 기존 설정의 비활성 사본으로 대체한다.
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

  // 함수이름: _scheduleMedicationReminder
  // 함수역할: 민감정보 표시 정책을 적용하고 구형 예약을 제거한 뒤 복용 기간 안의 복용하는 날짜로 알림을 등록한다. 알림 문구는 약 이름을 쓰지 않으므로 날짜별 약명은 만들지 않는다.
  // 매개변수:
  // - setting (MedicationAlarm): 해당 복약 시간대의 알림 설정
  // - slotTitle (String): 현재 언어로 표시할 복약 시간대 이름
  // - schedules (List<MedicationSchedule>): 이 시간대에 오늘 복용하는 약; 오늘 복용 완료 여부를 판단한다
  // - courseSchedules (List<MedicationSchedule>?): 이 시간대에 앞으로 14일 안에 복용 기간이 걸치는 약; 없으면 오늘 일정으로 날짜를 정한다
  // - isCurrent (bool Function()? ): 비동기 경계마다 작업 세대·세션 유효성을 추가 확인하는 함수.
  // - lastAllowedDate (DateTime?): 이 날짜 이후의 예약을 제외하는 상한; null이면 추가 제한 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _scheduleMedicationReminder({
    required MedicationAlarm setting,
    required String slotTitle,
    required List<MedicationSchedule> schedules,
    List<MedicationSchedule>? courseSchedules,
    bool Function()? isCurrent,
    DateTime? lastAllowedDate,
  }) async {
    if (!_canContinueReminder(isCurrent)) return;
    notificationService.setShowSensitiveDetails(
      userSetting.showNotificationDetails,
    );
    await _cancelLegacyMedicationReminder(setting, isCurrent: isCurrent);
    if (!_canContinueReminder(isCurrent)) return;
    final now = DateTime.now();
    // 이 시간대의 약을 오늘 모두 복용했다면 오늘 알림은 다시 예약하지 않는다.
    final slotCompletedToday =
        schedules.isNotEmpty &&
        schedules.every(
          (schedule) => schedule.isSlotCompleted(setting.slotKey),
        );
    final activeDates = MedicationReminderRefreshService.activeReminderDates(
      // 기간 일정이 늦게 반영되어도 오늘 복용하는 약의 날짜는 빠지지 않게 함께 넘긴다.
      courseSchedules == null ? schedules : [...courseSchedules, ...schedules],
      now: now,
      slotCompletedToday: slotCompletedToday,
    );
    await setNotification.registerNotification(
      id: setting.notificationId,
      slotKey: setting.slotKey,
      slotTitle: slotTitle,
      hour: setting.hour,
      minute: setting.minute,
      activeDates: lastAllowedDate == null
          ? activeDates
          : activeDates
                .where((date) => !date.isAfter(lastAllowedDate))
                .toList(),
      language: userSetting.language,
    );
  }

  // 함수이름: _cancelMedicationReminder
  // 함수역할: 시간대별 현재 예약과 구형 고정 ID 예약을 함께 취소한다.
  // 매개변수:
  // - setting (MedicationAlarm): 해당 복약 시간대의 알림 설정
  // - isCurrent (bool Function()? ): 취소 전·대기 후 현재 작업인지 확인할 선택적 경계.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _cancelMedicationReminder(
    MedicationAlarm setting, {
    bool Function()? isCurrent,
  }) async {
    if (!_canContinueReminder(isCurrent)) return;
    await notificationService.cancelReminder(
      setting.notificationId,
      slotKey: setting.slotKey,
    );
    if (!_canContinueReminder(isCurrent)) return;
    await _cancelLegacyMedicationReminder(setting, isCurrent: isCurrent);
  }

  // 함수이름: _cancelLegacyMedicationReminder
  // 함수역할: 현재 환자별 알림 ID와 다른 구형 시간대 고정 ID의 예약만 취소한다. 이 설치에서 구형 예약을
  //   이미 모두 지웠다고 기록되어 있으면 같은 취소를 반복하지 않는다.
  // 매개변수:
  // - setting (MedicationAlarm): 해당 복약 시간대의 알림 설정
  // - isCurrent (bool Function()? ): 저장소 조회 후에도 현재 세션·작업인지 확인할 선택적 경계.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _cancelLegacyMedicationReminder(
    MedicationAlarm setting, {
    bool Function()? isCurrent,
  }) async {
    if (!_canContinueReminder(isCurrent)) return;
    final legacyId = setting.legacyNotificationId;
    if (legacyId == setting.notificationId) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    if (!_canContinueReminder(isCurrent)) return;
    if (preferences.getBool(
          NotificationService.legacyReminderIdsCancelledKey,
        ) ==
        true) {
      return;
    }
    await notificationService.cancelReminder(legacyId);
  }

  // Function Name: _schedulesForReminderSlot
  // Description: Reads current-day schedules and selects those matching a resolved reminder slot.
  // Parameters: slotKey: Target reminder slot.
  // Returns: A fixed-length list of matching current schedules.
  List<MedicationSchedule> _schedulesForReminderSlot(String slotKey) {
    return _readSchedules()
        .where(/* 함수이름: where 콜백
         * 함수역할: 정규화된 일정 시간대에 대상 알림 시간대가 포함되는지 검사한다.
         * 매개변수:
         * - schedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
         * 반환값:
         * - 대상 시간대의 일정이면 true.
         */ (schedule) {
          return resolveScheduleSlotKeys(schedule).contains(slotKey);
        })
        .toList(growable: false);
  }

  // Function Name: _reminderSlotTitle
  // Description: Localizes a reminder slot title with a general schedule fallback.
  // Parameters: slotKey: Slot to label.
  // Returns: The localized slot name, or Schedule/일정 for an unknown key.
  String _reminderSlotTitle(String slotKey) {
    final isEnglish = _isEnglishSetting;
    return medicationSlotLabel(
      slotKey,
      isEnglish: isEnglish,
      fallback: isEnglish ? 'Schedule' : '일정',
    );
  }

  // 함수이름: _defaultMedicationAlarm
  // 함수역할: 사용자 환경설정의 기본 시각으로 비활성 복약 알림을 만든다.
  // 매개변수:
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - MedicationAlarm: 사용자 환경설정의 기본 시각으로 비활성 복약 알림을 만든다.
  MedicationAlarm _defaultMedicationAlarm(String slotKey) {
    final timeParts = userSetting.defaultTimeForSlot(slotKey).split(':');
    final hour = timeParts.isNotEmpty ? int.tryParse(timeParts[0]) : null;
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) : null;
    return MedicationAlarm.defaults(slotKey, hour: hour, minute: minute);
  }
}
