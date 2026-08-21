part of 'medbuddy_view_model.dart';

const int _maximumReminderDatesPerSlot = 14;

// 파일명: medbuddy_reminder_view_model.dart
// 역할: 시간대별 복약 알림의 조회, 저장, 취소, 로컬 동기화를 관리한다.

// 확장명: MedBuddyReminderViewModel
// 역할: MedBuddyViewModel의 해당 기능 상태 전이와 Control 호출을 한곳에 모은다.
extension MedBuddyReminderViewModel on MedBuddyViewModel {
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
    try {
      final settings = await setNotification.requestMedicationAlarm();
      final settingsBySlot = {
        for (final slotKey in MedBuddyViewModel._reminderSlotKeys)
          slotKey: MedicationAlarm.defaults(slotKey),
      };
      for (final setting in settings) {
        if (MedBuddyViewModel._reminderSlotKeys.contains(setting.slotKey)) {
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
    final storageKey = _reminderStorageKey(slotKey);
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
      _statusMessage = _isEnglishSetting
          ? '$slotTitle reminder is set for ${setting.timeLabel}.'
          : '$slotTitle 알림이 ${setting.timeLabel}으로 설정되었습니다.';
      _notifyViewModelListeners(MedBuddyFeature.reminder);
      return true;
    } on StateError catch (error) {
      await _rollbackMedicationReminderSave(
        alarmControl: setNotification,
        setting: persistedSetting,
        storageKey: storageKey,
      );
      _statusMessage = error.message;
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

  String _reminderStorageKey(String slotKey) {
    return 'medbuddy_medication_reminder_'
        'patient_${patientHash}_'
        '${patientHash}_$slotKey';
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

  Future<void> _loadMedicationReminderSettingsFromCache() async {
    final preferences = await SharedPreferences.getInstance();
    for (final slotKey in MedBuddyViewModel._reminderSlotKeys) {
      final rawSetting =
          preferences.getString(_reminderStorageKey(slotKey)) ??
          preferences.getString(_legacyReminderStorageKey(slotKey));
      if (rawSetting == null || rawSetting.trim().isEmpty) {
        _medicationReminderSettings[slotKey] = MedicationAlarm.defaults(
          slotKey,
        );
        continue;
      }

      try {
        final decodedSetting = jsonDecode(rawSetting);
        if (decodedSetting is Map<String, dynamic>) {
          _medicationReminderSettings[slotKey] = MedicationAlarm.fromJson(
            decodedSetting,
          );
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

    final preferences = await SharedPreferences.getInstance();
    for (final slotKey in MedBuddyViewModel._reminderSlotKeys) {
      final setting =
          _medicationReminderSettings[slotKey] ??
          MedicationAlarm.defaults(slotKey);
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
    await setNotification.registerNotification(
      id: setting.notificationId,
      slotKey: setting.slotKey,
      slotTitle: slotTitle,
      hour: setting.hour,
      minute: setting.minute,
      medicationNames: schedules
          .map((schedule) => schedule.displayName)
          .where((name) => name.trim().isNotEmpty)
          .toList(growable: false),
      activeDates: _activeReminderDates(schedules),
      language: userSetting.language,
    );
  }

  // 함수명: _activeReminderDates
  // 함수역할:
  // - 복용 시작일과 총 투약일을 기준으로 알림을 예약할 날짜를 계산한다.
  // - 플랫폼의 대기 알림 개수 제한을 고려해 앱 실행 시점부터 최대 14일만 예약한다.
  List<DateTime> _activeReminderDates(List<MedicationSchedule> schedules) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastReservableDate = today.add(
      const Duration(days: _maximumReminderDatesPerSlot - 1),
    );
    final activeDateKeys = <String, DateTime>{};

    for (final schedule in schedules) {
      final rawStartDate =
          schedule.prescriptionDate ?? schedule.createdDate ?? today;
      final startDate = DateTime(
        rawStartDate.year,
        rawStartDate.month,
        rawStartDate.day,
      );
      final courseDays = schedule.medicationTime;
      final endDate = courseDays > 0
          ? startDate.add(Duration(days: courseDays - 1))
          : today;
      var candidateDate = startDate.isAfter(today) ? startDate : today;
      final boundedEndDate = endDate.isBefore(lastReservableDate)
          ? endDate
          : lastReservableDate;

      while (!candidateDate.isAfter(boundedEndDate)) {
        final dateKey =
            '${candidateDate.year.toString().padLeft(4, '0')}-'
            '${candidateDate.month.toString().padLeft(2, '0')}-'
            '${candidateDate.day.toString().padLeft(2, '0')}';
        activeDateKeys[dateKey] = candidateDate;
        candidateDate = candidateDate.add(const Duration(days: 1));
      }
    }

    final activeDates = activeDateKeys.values.toList(growable: false)..sort();
    return activeDates;
  }

  Future<void> _cancelMedicationReminder(MedicationAlarm setting) async {
    await notificationService.cancelReminder(
      setting.notificationId,
      slotKey: setting.slotKey,
    );
    await _cancelLegacyMedicationReminder(setting);
  }

  Future<void> _cancelLegacyMedicationReminder(MedicationAlarm setting) async {
    final legacyId = setting.legacyNotificationId;
    if (legacyId != setting.notificationId) {
      await notificationService.cancelReminder(legacyId);
    }
  }

  List<MedicationSchedule> _schedulesForReminderSlot(String slotKey) {
    return _todayMedicationScheduleList
        .where((schedule) {
          return _slotKeysForSchedule(schedule).contains(slotKey);
        })
        .toList(growable: false);
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
}
