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
import 'medbuddy_feature_updates.dart';
import 'medbuddy_schedule_slot_policy.dart';

// 파일명: medbuddy_reminder_view_model.dart
// 역할: 시간대별 복약 알림의 조회, 저장, 취소, 로컬 동기화를 관리한다.

// 클래스명: MedBuddyReminderViewModel
// 역할: 시간대별 복약 알림의 서버 설정과 로컬 예약 상태를 확장한다.
// 주요 책임:
// - 캐시 복원·권한 확인·저장 실패 롤백을 수행하고 최신 일정과 개인정보 설정으로 알림을 동기화한다.
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
  // Description: Binds reminder dependencies and read-only feature snapshots.
  // Parameters: Controls, patient, snapshot providers, the optional 14-day course loader and change callback. Returns: State owner.
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
  // Description: Publishes live feature state. Parameters: feature: Tag. Returns: None.
  void _notifyViewModelListeners(MedBuddyFeature feature) {
    if (!_disposed) _onChanged(_statusMessage);
  }

  // Function Name: dispose
  // Description: Stops notifications without disposing borrowed services. Parameters: None. Returns: None.
  void dispose() {
    _disposed = true;
    _loadGeneration++;
  }

  // 함수이름: loadMedicationReminderSettings
  // 함수역할: 서버에서 시간대별 알림을 읽어 기본값과 캐시에 반영하고 조회 실패 시 사용자별 또는 구형 캐시로 복원한다.
  // 매개변수:
  // - notifyAfterLoad (bool): 불러온 뒤 화면 갱신 여부
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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
      _notifyViewModelListeners(MedBuddyFeature.reminder);
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

  // 같은 시간대의 중복 쓰기와 저장 이전에 시작한 조회의 뒤늦은 덮어쓰기를 막는다.
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
      _notifyViewModelListeners(MedBuddyFeature.reminder);
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
        _notifyViewModelListeners(MedBuddyFeature.reminder);
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
      _notifyViewModelListeners(MedBuddyFeature.reminder);
      return false;
    }
    if (_disposed) return false;
    if (!hasPermission) {
      _statusMessage = _isEnglishSetting
          ? 'Notification permission was not allowed.'
          : '알림 권한이 허용되지 않았습니다.';
      _notifyViewModelListeners(MedBuddyFeature.reminder);
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
      _notifyViewModelListeners(MedBuddyFeature.reminder);
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
      _notifyViewModelListeners(MedBuddyFeature.reminder);
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
      _notifyViewModelListeners(MedBuddyFeature.reminder);
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
        _notifyViewModelListeners(MedBuddyFeature.reminder);
        return false;
      }
      _statusMessage = _isEnglishSetting
          ? '$slotTitle reminder has been turned off.'
          : '$slotTitle 알림이 해제되었습니다.';
      _notifyViewModelListeners(MedBuddyFeature.reminder);
      return true;
    } catch (_) {
      if (_disposed) return false;
      _statusMessage = _isEnglishSetting
          ? 'Could not turn off the $slotTitle reminder.'
          : '$slotTitle 알림을 해제하지 못했습니다.';
      _notifyViewModelListeners(MedBuddyFeature.reminder);
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

  // 함수이름: _loadMedicationReminderSettingsFromCache
  // 함수역할: 사용자별 캐시를 우선하고 구형 시간대 캐시를 보완하며 없거나 손상된 설정은 사용자 기본 시각의 비활성 알림으로 대체한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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

  // 함수이름: _synchronizeMedicationReminderSchedules
  // 함수역할: 사용자 알림 허용과 시간대 활성·약 존재 여부에 따라 예약을 재구성하고 빈 시간대 설정을 비활성화한다.
  //   오늘 일정이 비어 있어도 앞으로 14일 안에 그 시간대에 복용하는 약이 있으면 빈 시간대로 보지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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

  // 함수이름: _restoreAsNeededCheckReminder
  // 함수역할: 저장된 필요시 복용 확인 알림을 다시 예약한다. 일정 화면을 열지 않아도 강제 종료·전체 취소
  //   뒤 앱 시작이나 일정 갱신 때 되살아나게 한다. 지난 시각이면 아무것도 예약하지 않는다.
  // 매개변수:
  // - isCurrent (bool Function()): 계정이 바뀌면 중단할지 확인하는 함수.
  // 반환값:
  // - Future<void>: 실패해도 정기 알림 동기화는 계속한다.
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

  // 함수이름: _loadScheduleWindowOrNull
  // 함수역할: 앞으로 14일의 복약 기간 일정을 읽는다. 조회 경계가 없거나 조회에 실패하면 null을 돌려
  //   호출자가 오늘 일정으로 대신 판단하게 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<List<MedicationSchedule>?>: 기간 일정, 읽지 못하면 null.
  Future<List<MedicationSchedule>?> _loadScheduleWindowOrNull() async {
    final loadScheduleWindow = _loadScheduleWindow;
    if (loadScheduleWindow == null) return null;
    try {
      return await loadScheduleWindow();
    } catch (_) {
      return null;
    }
  }

  // 함수이름: _schedulesForSlot
  // 함수역할: 주어진 일정 중 명시·추론된 시간대가 대상 알림 시간대를 포함하는 약만 모은다.
  // 매개변수:
  // - schedules (List<MedicationSchedule>): 분류할 복약 일정 목록
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - List<MedicationSchedule>: 대상 시간대에 속한 일정.
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

  // 함수이름: synchronizeIfFresh
  // 함수역할: 최근 일정 조회 성공 시에만 알림 예약을 동기화하고 예약 실패를 일정 조회 성공과 구분해 안내한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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
          _notifyViewModelListeners(MedBuddyFeature.reminder);
        })
        .whenComplete(() {
          if (identical(_synchronization, synchronization)) {
            _synchronization = null;
          }
        });
    return _synchronization = synchronization;
  }

  // 수동 저장은 생명주기만, 자동 동기화는 시작 당시 세대도 함께 검사한다.
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
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _scheduleMedicationReminder({
    required MedicationAlarm setting,
    required String slotTitle,
    required List<MedicationSchedule> schedules,
    List<MedicationSchedule>? courseSchedules,
    bool Function()? isCurrent,
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
      medicationNames: schedules
          .map(
            // 함수이름: map 콜백
            // 함수역할: 사용자 언어에 맞는 약 이름을 복약 알림 본문에 제공한다.
            // 매개변수:
            // - schedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
            // 반환값:
            // - 현재 언어의 약 표시 이름.
            (schedule) => schedule.displayNameForLanguage(userSetting.language),
          )
          .where(
            /* 함수이름: where 콜백
           * 함수역할: 복약 알림에서 공백뿐인 약 이름을 제외한다.
           * 매개변수:
           * - name (String): 표시·일치 여부를 검사할 약 이름
           * 반환값:
           * - 공백 외 내용이 있으면 true.
           */
            (name) => name.trim().isNotEmpty,
          )
          .toList(growable: false),
      activeDates: activeDates,
      language: userSetting.language,
    );
  }

  // 함수이름: _cancelMedicationReminder
  // 함수역할: 시간대별 현재 예약과 구형 고정 ID 예약을 함께 취소한다.
  // 매개변수:
  // - setting (MedicationAlarm): 해당 복약 시간대의 알림 설정
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

  // 함수이름: _schedulesForReminderSlot
  // 함수역할: 현재 오늘 일정 중 명시·추론된 시간대가 선택한 알림 시간대를 포함하는 약만 모은다.
  // 매개변수:
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - List<MedicationSchedule>: 현재 오늘 일정 중 명시·추론된 시간대가 선택한 알림 시간대를 포함하는 약만 모은다.
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

  // 함수이름: _reminderSlotTitle
  // 함수역할: 현재 사용자 언어로 시간대 제목을 제공하고 알 수 없는 키에는 일반 일정 이름을 사용한다.
  // 매개변수:
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - String: 현재 사용자 언어로 시간대 제목을 제공하고 알 수 없는 키에는 일반 일정 이름을 사용한다.
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
