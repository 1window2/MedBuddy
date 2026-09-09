part of 'medbuddy_view_model.dart';

// 파일명: medbuddy_reminder_view_model.dart
// 역할: 시간대별 복약 알림의 조회, 저장, 취소, 로컬 동기화를 관리한다.

// 클래스명: MedBuddyReminderViewModel
// 역할: 시간대별 복약 알림의 서버 설정과 로컬 예약 상태를 확장한다.
// 주요 책임:
// - 캐시 복원·권한 확인·저장 실패 롤백을 수행하고 최신 일정과 개인정보 설정으로 알림을 동기화한다.
extension MedBuddyReminderViewModel on MedBuddyViewModel {
  // 함수이름: loadMedicationReminderSettings
  // 함수역할: 서버에서 시간대별 알림을 읽어 기본값과 캐시에 반영하고 조회 실패 시 사용자별 또는 구형 캐시로 복원한다.
  // 매개변수:
  // - notifyAfterLoad (bool): 불러온 뒤 화면 갱신 여부
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> loadMedicationReminderSettings({
    bool notifyAfterLoad = true,
  }) async {
    try {
      final settings = await setNotification.requestMedicationAlarm();
      final settingsBySlot = {
        for (final slotKey in MedBuddyViewModel._reminderSlotKeys)
          slotKey: _defaultMedicationAlarm(slotKey),
      };
      for (final setting in settings) {
        if (MedBuddyViewModel._reminderSlotKeys.contains(setting.slotKey)) {
          // 비활성 상태에서도 사용자가 마지막으로 지정한 시각을 보존한다.
          settingsBySlot[setting.slotKey] = setting;
        }
      }
      _medicationReminderSettings
        ..clear()
        ..addAll(settingsBySlot);

      final preferences = await SharedPreferences.getInstance();
      for (final setting in settingsBySlot.values) {
        await _cacheMedicationReminderSetting(preferences, setting);
      }
    } catch (_) {
      await _loadMedicationReminderSettingsFromCache();
    }

    if (notifyAfterLoad) {
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
  }) async {
    final storageKey = _reminderStorageKey(slotKey);
    if (!userSetting.medicationNotificationsEnabled) {
      _statusMessage = _isEnglishSetting
          ? 'Turn on medication notifications in Settings first.'
          : '환경설정에서 내 복약 알림을 먼저 켜주세요.';
      _notifyViewModelListeners(MedBuddyFeature.reminder);
      return false;
    }
    if (schedules.isEmpty) {
      _statusMessage = _isEnglishSetting
          ? 'There is no medication in this time slot.'
          : '이 시간대에 복용할 약이 없습니다.';
      _notifyViewModelListeners(MedBuddyFeature.reminder);
      return false;
    }

    bool hasPermission;
    try {
      hasPermission = await notificationService.requestPermission();
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'Could not request notification permission.'
          : '알림 권한을 요청하지 못했습니다.';
      _notifyViewModelListeners(MedBuddyFeature.reminder);
      return false;
    }
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
      persistedSetting = setting;

      await _scheduleMedicationReminder(
        setting: setting,
        slotTitle: slotTitle,
        schedules: schedules,
      );

      final preferences = await SharedPreferences.getInstance();
      await _cacheMedicationReminderSetting(
        preferences,
        setting,
        storageKey: storageKey,
      );
      _medicationReminderSettings[setting.slotKey] = setting;
      final displayTime = userSetting.formatTime(setting.hour, setting.minute);
      _statusMessage = _isEnglishSetting
          ? '$slotTitle reminder is set for $displayTime.'
          : '$slotTitle 알림이 $displayTime으로 설정되었습니다.';
      _notifyViewModelListeners(MedBuddyFeature.reminder);
      return true;
    } on StateError {
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
  // 함수역할: 이미 활성화된 시간대별 복약 알림을 취소하고 로컬 설정을 비활성화한다.
  // 매개변수:
  // - slotKey (String): morning, lunch, evening, bedtime 중 하나
  // - slotTitle (String): 사용자에게 보여줄 시간대명
  // 반환값:
  // - 알림 취소 성공 여부
  Future<bool> requestMedicationReminderCancel({
    required String slotKey,
    required String slotTitle,
  }) async {
    final storageKey = _reminderStorageKey(slotKey);
    try {
      final disabledSetting = await setNotification.disableAlarmSetting(
        slotKey,
      );
      await _cancelMedicationReminder(disabledSetting);
      final preferences = await SharedPreferences.getInstance();
      await _cacheMedicationReminderSetting(
        preferences,
        disabledSetting,
        storageKey: storageKey,
      );
      _medicationReminderSettings[disabledSetting.slotKey] = disabledSetting;
      _statusMessage = _isEnglishSetting
          ? '$slotTitle reminder has been turned off.'
          : '$slotTitle 알림이 해제되었습니다.';
      _notifyViewModelListeners(MedBuddyFeature.reminder);
      return true;
    } catch (_) {
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

  // 함수이름: _loadMedicationReminderSettingsFromCache
  // 함수역할: 사용자별 캐시를 우선하고 구형 시간대 캐시를 보완하며 없거나 손상된 설정은 사용자 기본 시각의 비활성 알림으로 대체한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _loadMedicationReminderSettingsFromCache() async {
    final preferences = await SharedPreferences.getInstance();
    for (final slotKey in MedBuddyViewModel._reminderSlotKeys) {
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
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _synchronizeMedicationReminderSchedules() async {
    if (!userSetting.medicationNotificationsEnabled) {
      await notificationService.cancelAllScheduledMedicationReminders();
      return;
    }
    if (_medicationReminderSettings.isEmpty) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    for (final slotKey in MedBuddyViewModel._reminderSlotKeys) {
      final setting =
          _medicationReminderSettings[slotKey] ??
          _defaultMedicationAlarm(slotKey);
      if (!setting.isEnabled) {
        await _cancelMedicationReminder(setting);
        continue;
      }

      final schedules = _schedulesForReminderSlot(slotKey);
      if (schedules.isEmpty) {
        final disabledSetting = await _disableReminderSettingForEmptySlot(
          setNotification,
          slotKey,
          setting,
        );
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
    }
  }

  // 함수이름: _synchronizeMedicationReminderSchedulesIfScheduleIsFresh
  // 함수역할: 최근 일정 조회 성공 시에만 알림 예약을 동기화하고 예약 실패를 일정 조회 성공과 구분해 안내한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void>
  _synchronizeMedicationReminderSchedulesIfScheduleIsFresh() async {
    if (!_lastTodayScheduleLoadSucceeded) {
      return;
    }
    try {
      await _synchronizeMedicationReminderSchedules();
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'The schedule loaded, but reminders could not be synchronized.'
          : '복약 일정은 불러왔지만 알림을 동기화하지 못했습니다.';
      _notifyViewModelListeners(MedBuddyFeature.reminder);
    }
  }

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
  // 함수역할: 민감정보 표시 정책을 적용하고 구형 예약을 제거한 뒤 복용 기간 안의 날짜와 날짜별 약명으로 알림을 등록한다.
  // 매개변수:
  // - setting (MedicationAlarm): 해당 복약 시간대의 알림 설정
  // - slotTitle (String): 현재 언어로 표시할 복약 시간대 이름
  // - schedules (List<MedicationSchedule>): 조회·비교·예약에 사용할 복약 일정 목록
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _scheduleMedicationReminder({
    required MedicationAlarm setting,
    required String slotTitle,
    required List<MedicationSchedule> schedules,
  }) async {
    notificationService.setShowSensitiveDetails(
      userSetting.showNotificationDetails,
    );
    await _cancelLegacyMedicationReminder(setting);
    final now = DateTime.now();
    final activeDates = MedicationReminderRefreshService.activeReminderDates(
      schedules,
      now: now,
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
          .where(/* 함수이름: where 콜백
           * 함수역할: 복약 알림에서 공백뿐인 약 이름을 제외한다.
           * 매개변수:
           * - name (String): 표시·일치 여부를 검사할 약 이름
           * 반환값:
           * - 공백 외 내용이 있으면 true.
           */(name) => name.trim().isNotEmpty)
          .toList(growable: false),
      activeDates: activeDates,
      medicationNamesByDate:
          MedicationReminderRefreshService.medicationNamesForDates(
            schedules,
            activeDates: activeDates,
            now: now,
            language: userSetting.language,
          ),
      language: userSetting.language,
    );
  }

  // 함수이름: _cancelMedicationReminder
  // 함수역할: 시간대별 현재 예약과 구형 고정 ID 예약을 함께 취소한다.
  // 매개변수:
  // - setting (MedicationAlarm): 해당 복약 시간대의 알림 설정
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _cancelMedicationReminder(MedicationAlarm setting) async {
    await notificationService.cancelReminder(
      setting.notificationId,
      slotKey: setting.slotKey,
    );
    await _cancelLegacyMedicationReminder(setting);
  }

  // 함수이름: _cancelLegacyMedicationReminder
  // 함수역할: 현재 환자별 알림 ID와 다른 구형 시간대 고정 ID의 예약만 취소한다.
  // 매개변수:
  // - setting (MedicationAlarm): 해당 복약 시간대의 알림 설정
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _cancelLegacyMedicationReminder(MedicationAlarm setting) async {
    final legacyId = setting.legacyNotificationId;
    if (legacyId != setting.notificationId) {
      await notificationService.cancelReminder(legacyId);
    }
  }

  // 함수이름: _schedulesForReminderSlot
  // 함수역할: 현재 오늘 일정 중 명시·추론된 시간대가 선택한 알림 시간대를 포함하는 약만 모은다.
  // 매개변수:
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - List<MedicationSchedule>: 현재 오늘 일정 중 명시·추론된 시간대가 선택한 알림 시간대를 포함하는 약만 모은다.
  List<MedicationSchedule> _schedulesForReminderSlot(String slotKey) {
    return _todayMedicationScheduleList
        .where(/* 함수이름: where 콜백
         * 함수역할: 정규화된 일정 시간대에 대상 알림 시간대가 포함되는지 검사한다.
         * 매개변수:
         * - schedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
         * 반환값:
         * - 대상 시간대의 일정이면 true.
         */(schedule) {
          return _slotKeysForSchedule(schedule).contains(slotKey);
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
    return switch (slotKey) {
      'morning' => isEnglish ? 'Morning' : '아침',
      'lunch' => isEnglish ? 'Lunch' : '점심',
      'evening' => isEnglish ? 'Evening' : '저녁',
      'bedtime' => isEnglish ? 'Bedtime' : '취침 전',
      _ => isEnglish ? 'Schedule' : '일정',
    };
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
