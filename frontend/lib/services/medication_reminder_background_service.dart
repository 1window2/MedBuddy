// File Name: medication_reminder_background_service.dart
// Role: Replenishes dated patient reminders from server schedules and manages periodic Android refresh work.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../entities/calendar_days.dart';
import '../entities/json_value_reader.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/medication_slot_label.dart';
import '../entities/patient_hash_entity.dart';
import '../entities/user_setting_entity.dart';
import 'api_config.dart';
import 'app_language_resolver.dart';
import 'dose_sync_service.dart';

// Function Name: MedicationAlarmSettingsLoader
// Description: Loads the patient's enabled and disabled medication alarm settings for reminder-window refresh.
// Parameters:
// - None.
// Returns:
// - Future<List<MedicationAlarm>>: Loads the patient's enabled and disabled medication alarm settings for reminder-window refresh.
typedef MedicationAlarmSettingsLoader =
    Future<List<MedicationAlarm>> Function();
// Function Name: MedicationScheduleLoader
// Description: Loads medication courses needed to replenish the bounded reminder window.
// Parameters:
// - None.
// Returns:
// - Future<List<MedicationSchedule>>: Loads medication courses needed to replenish the bounded reminder window.
typedef MedicationScheduleLoader = Future<List<MedicationSchedule>> Function();
// 함수이름: ReminderUserSettingLoader
// 함수역할: 복약 알림 허용·개인정보 표시·언어를 결정할 현재 사용자 설정을 조회하는 계약이다.
// 매개변수:
// - 없음.
// 반환값:
// - Future<UserSetting>: 복약 알림 허용·개인정보 표시·언어를 결정할 현재 사용자 설정을 조회하는 계약이다.
typedef ReminderUserSettingLoader = Future<UserSetting> Function();
// Function Name: MedicationReminderRegistrar
// Description: Registers dated reminders for a slot with local time, localized title, and active dates.
// Parameters:
// - id (int): Platform identifier used to schedule, replace, or cancel an alert.
// - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
// - slotTitle (String): Localized medication slot name.
// - hour (int): Local hour in 24-hour time.
// - minute (int): Minute component of local time.
// - activeDates (List<DateTime>): Reminder dates within the medication course.
// - language (String): Language code used for display or speech guidance.
// Returns:
// - Future<void>: asynchronous completion without a result payload.
typedef MedicationReminderRegistrar =
    Future<void> Function({
      required int id,
      required String slotKey,
      required String slotTitle,
      required int hour,
      required int minute,
      required List<DateTime> activeDates,
      String language,
    });
// Function Name: MedicationReminderCanceler
// Description: Cancels a reminder by ID, optionally canceling every scheduled date for the supplied slot.
// Parameters:
// - id (int): Platform identifier used to schedule, replace, or cancel an alert.
// - slotKey (String?): Medication slot key: morning, lunch, evening, or bedtime.
// Returns:
// - Future<void>: asynchronous completion without a result payload.
typedef MedicationReminderCanceler =
    Future<void> Function(int id, {String? slotKey});
// Function Name: ReminderPreferencesLoader
// Description: Supplies the local preference store used while refreshing reminder settings and language.
// Parameters:
// - None.
// Returns:
// - Future<SharedPreferences>: Supplies the local preference store used while refreshing reminder settings and language.
typedef ReminderPreferencesLoader = Future<SharedPreferences> Function();
// 함수이름: ReminderPrivacySetter
// 함수역할: 이후 예약할 알림에 민감한 약명 등 세부 내용을 표시할지 적용하는 계약이다.
// 매개변수:
// - showSensitiveDetails (bool): 알림 본문에 민감한 세부 내용을 포함할지 여부
// 반환값:
// - 없음.
typedef ReminderPrivacySetter = void Function(bool showSensitiveDetails);

const String medicationReminderBackgroundTask =
    'medbuddy_medication_reminder_refresh';
const String _medicationReminderBackgroundTag = 'medbuddy_medication_reminder';
const String _reminderWorkerOwnerKey = 'medbuddy_reminder_worker_owner';

// Class Name: MedicationReminderRefreshService
// Role: Rebuilds a bounded local reminder window from the owning patient's server state.
// Responsibilities:
// - Respect course dates, dose rhythms, completed slots, privacy settings, and reminder ownership.
// - Cancel obsolete local reminders without changing the server's alarm settings.
// Attributes:
// - _loadSettings, _loadSchedules, _loadTodaySchedules, _loadUserSetting: Alarm, course, completion, and preference loaders.
// - _registerReminder, _cancelReminder: Asynchronous platform scheduling callbacks.
// - _loadPreferences (ReminderPreferencesLoader): Local language fallback store.
// - _setPrivacy (ReminderPrivacySetter?): Optional notification-content policy setter.
// - _now (DateTime Function()): Clock for date and completion guards.
// - _ownsReminders (Future<bool> Function()?): Account-ownership guard across asynchronous work.
// - _onDispose (VoidCallback?): Caller-provided dependency cleanup.
class MedicationReminderRefreshService {
  static const int maximumReminderDatesPerSlot = 14;

  final MedicationAlarmSettingsLoader _loadSettings;
  final MedicationScheduleLoader _loadSchedules;
  final MedicationScheduleLoader? _loadTodaySchedules;
  final ReminderUserSettingLoader _loadUserSetting;
  final MedicationReminderRegistrar _registerReminder;
  final MedicationReminderCanceler _cancelReminder;
  final ReminderPreferencesLoader _loadPreferences;
  final ReminderPrivacySetter? _setPrivacy;
  final DateTime Function() _now;
  final VoidCallback? _onDispose;
  final Future<bool> Function()? _ownsReminders;

  // Function Name: MedicationReminderRefreshService
  // Description: Binds data loaders and platform callbacks without reading or scheduling anything yet.
  // Parameters:
  // - loadSettings, loadSchedules: Required alarm settings and medication-course loaders.
  // - loadTodaySchedules (MedicationScheduleLoader?): Optional completion snapshot; course windows alone cannot suppress completed slots.
  // - loadUserSetting (ReminderUserSettingLoader?): Notification/privacy/language settings; defaults to UserSetting().
  // - registerReminder, cancelReminder: Required asynchronous reminder writers.
  // - preferencesLoader (ReminderPreferencesLoader): Local fallback settings; defaults to SharedPreferences.getInstance.
  // - setPrivacy (ReminderPrivacySetter?): Optional detail-visibility setter.
  // - now (DateTime Function()?): Clock, defaulting to DateTime.now.
  // - onDispose (VoidCallback?): Dependency cleanup invoked by dispose.
  // - ownsReminders (Future<bool> Function()?): Whether this account still owns local reminders; absent means allowed.
  // Returns: A configured MedicationReminderRefreshService.
  MedicationReminderRefreshService({
    required MedicationAlarmSettingsLoader loadSettings,
    required MedicationScheduleLoader loadSchedules,
    MedicationScheduleLoader? loadTodaySchedules,
    ReminderUserSettingLoader? loadUserSetting,
    required MedicationReminderRegistrar registerReminder,
    required MedicationReminderCanceler cancelReminder,
    ReminderPreferencesLoader preferencesLoader = SharedPreferences.getInstance,
    ReminderPrivacySetter? setPrivacy,
    DateTime Function()? now,
    VoidCallback? onDispose,
    Future<bool> Function()? ownsReminders,
  }) : _loadSettings = loadSettings,
       _loadSchedules = loadSchedules,
       _loadTodaySchedules = loadTodaySchedules,
       _loadUserSetting = loadUserSetting ?? (/* 함수이름: callback 콜백
        * 함수역할: 사용자 설정 로더가 주입되지 않았을 때 기본 사용자 설정을 제공한다.
        * 매개변수:
        * - 없음.
        * 반환값:
        * - 기본 사용자 설정으로 완료하는 Future.
        */() async => const UserSetting()),
       _registerReminder = registerReminder,
       _cancelReminder = cancelReminder,
       _loadPreferences = preferencesLoader,
       _setPrivacy = setPrivacy,
       _now = now ?? DateTime.now,
       _onDispose = onDispose,
       _ownsReminders = ownsReminders;

  // 함수이름: synchronize
  // 함수역할: 인증된 서버 상태를 기준으로 모든 로컬 시간대 알림을 갱신한다. 일시적 오류에서는 false를 반환해 Workmanager가 재시도하게 한다.
  //   오늘 이미 모두 복용한 시간대는 오늘 알림을 다시 예약하지 않는다.
  // - 비동기 조회 뒤와 알림 쓰기 전후에 소유 계정을 확인하고, 소유권을 잃으면 추가 작업을 중단한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 동기화 완료 또는 소유권 상실로 중단하면 true. 조회·예약·취소 오류는 기록하고 false를 반환한다.
  Future<bool> synchronize() async {
    try {
      final results = await Future.wait<Object>([
        _loadSettings(),
        _loadSchedules(),
        _loadPreferences(),
        _loadUserSetting(),
      ]);
      final settings = results[0] as List<MedicationAlarm>;
      final schedules = results[1] as List<MedicationSchedule>;
      final preferences = results[2] as SharedPreferences;
      final userSetting = results[3] as UserSetting;
      // 이전 계정의 늦은 조회는 현재 계정의 개인정보 설정과 알림을 변경하지 않는다.
      if (!await _stillOwnsReminders()) return true;
      final language = resolveAppLanguage(
        userSetting.languageMode.isEmpty
            ? preferences.getString(appLanguagePreferenceKey) ?? 'ko'
            : userSetting.languageMode,
      );
      _setPrivacy?.call(userSetting.showNotificationDetails);
      final settingsBySlot = {
        for (final setting in settings)
          setting.slotKey.trim().toLowerCase(): setting,
      };

      if (!userSetting.medicationNotificationsEnabled) {
        for (final slotKey in medicationScheduleSlotKeys) {
          if (!await _stillOwnsReminders()) return true;
          final setting =
              settingsBySlot[slotKey] ?? MedicationAlarm.defaults(slotKey);
          await _cancelReminder(
            setting.notificationId,
            slotKey: setting.slotKey,
          );
        }
        return true;
      }

      final loadTodaySchedules = _loadTodaySchedules;
      List<MedicationSchedule>? todaySchedules;
      var todayRequestDay = '';
      for (final slotKey in medicationScheduleSlotKeys) {
        final setting =
            settingsBySlot[slotKey] ?? MedicationAlarm.defaults(slotKey);
        final slotSchedules = schedules
            .where(/* Function Name: where callback
             * Description: Selects medications belonging to the reminder's time slot.
             * Parameters:
             * - schedule (MedicationSchedule): Medication course with name, dose, duration, and slots.
             * Returns:
             * - Whether the schedule contains the requested slot.
             */(schedule) => schedule.slotKeys.contains(slotKey))
            .toList(growable: false);
        if (!setting.isEnabled || slotSchedules.isEmpty) {
          if (!await _stillOwnsReminders()) return true;
          await _cancelReminder(
            setting.notificationId,
            slotKey: setting.slotKey,
          );
          continue;
        }
        // 오늘 일정은 예약할 시간대가 있을 때 한 번만 읽는다. 읽지 못하면 전체를 실패로 돌려
        // 기존 예약을 그대로 두고 재시도하게 한다.
        if (loadTodaySchedules != null && todaySchedules == null) {
          todayRequestDay = doseScheduleDay(_now());
          todaySchedules = await loadTodaySchedules();
        }
        final now = _now();
        final activeDates = activeReminderDates(
          slotSchedules,
          now: now,
          slotCompletedToday:
              todaySchedules != null &&
              _isSlotCompletedToday(
                todaySchedules,
                slotKey,
                requestDay: todayRequestDay,
                now: now,
              ),
        );
        // 조회 도중 로그아웃했으면 이전 계정의 알림을 다시 걸지 않는다.
        if (!await _stillOwnsReminders()) return true;
        await _registerReminder(
          id: setting.notificationId,
          slotKey: setting.slotKey,
          slotTitle: slotTitle(slotKey, language),
          hour: setting.hour,
          minute: setting.minute,
          activeDates: activeDates,
          language: language,
        );
        // 예약하는 사이에 로그아웃의 알림 정리가 끝났으면 방금 건 알림을 직접 지운다.
        if (!await _stillOwnsReminders()) {
          await _cancelReminder(
            setting.notificationId,
            slotKey: setting.slotKey,
          );
          return true;
        }
      }
      return true;
    } catch (error, stackTrace) {
      developer.log(
        'Medication reminder background refresh failed.',
        name: 'MedicationReminderRefreshService',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  // Function Name: _stillOwnsReminders
  // Description: Rechecks the worker's account ownership through the injected guard.
  // Parameters: None.
  // Returns: Guard result, or true when no guard is supplied; guard errors propagate to synchronize.
  Future<bool> _stillOwnsReminders() async =>
      await _ownsReminders?.call() ?? true;

  // Function Name: _isSlotCompletedToday
  // Description: Suppresses today's reminder only for a nonempty fully completed slot on the same local/server day.
  // Parameters: todaySchedules (List<MedicationSchedule>) - completion snapshot; slotKey (String) - target slot;
  // - requestDay (String): Dose day captured before retrieval; now (DateTime): clock after retrieval.
  // Returns: False across midnight/timezone disagreement or for an empty/incomplete slot; otherwise true.
  static bool _isSlotCompletedToday(
    List<MedicationSchedule> todaySchedules,
    String slotKey, {
    required String requestDay,
    required DateTime now,
  }) {
    if (doseScheduleDay(now) != requestDay ||
        formatJsonDate(now)! != requestDay) {
      return false;
    }
    final slotSchedules = todaySchedules.where(
      (schedule) => schedule.slotKeys.contains(slotKey),
    );
    return slotSchedules.isNotEmpty &&
        slotSchedules.every((schedule) => schedule.isSlotCompleted(slotKey));
  }

  // Function Name: activeReminderDates
  // Description: Returns sorted unique local dates in the next 14-day window without extending beyond course end; missing start dates use today. Dates on which a medication is not due (a weekly or every-other-day medication between its dose days) are left out, so a slot gets no reminder on a day when none of its medications is due. A course without a readable duration has no end date on the server and stays in every day's schedule, so it fills the whole window instead of today only; otherwise tomorrow's reminder would exist only if the app or the 12-hour worker happened to run after midnight and before the reminder time. Today is left out when the slot is already completed, so foreground and background refreshes follow one rule and neither re-arms a reminder for a dose already taken.
  // Parameters:
  // - schedules (List<MedicationSchedule>): Medication schedules used for lookup, comparison, or reminders.
  // - now (DateTime): Reference timestamp for comparisons and calendar calculations.
  // - slotCompletedToday (bool): Whether every medication of this slot is recorded as taken today.
  // Returns:
  // - List<DateTime>: Sorted unique local dates in the next 14-day window without extending beyond course end; missing start dates use today and unknown durations fill the window.
  static List<DateTime> activeReminderDates(
    List<MedicationSchedule> schedules, {
    required DateTime now,
    bool slotCompletedToday = false,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    // Calendar days, so a daylight-saving change cannot move the window or the
    // course end to 23:00 of the previous day and drop the last reminder date.
    final lastReservableDate = addCalendarDays(
      today,
      maximumReminderDatesPerSlot - 1,
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
          ? addCalendarDays(startDate, courseDays - 1)
          : lastReservableDate;
      var candidateDate = startDate.isAfter(today) ? startDate : today;
      final boundedEndDate = endDate.isBefore(lastReservableDate)
          ? endDate
          : lastReservableDate;

      while (!candidateDate.isAfter(boundedEndDate)) {
        // A medication that is not taken every day ("주 1회", "격일") is reminded on its dose days only.
        if (schedule.isDoseDay(candidateDate)) {
          activeDateKeys[formatJsonDate(candidateDate)!] = candidateDate;
        }
        // Calendar arithmetic, so a daylight-saving change cannot repeat or skip a date.
        candidateDate = addCalendarDays(candidateDate, 1);
      }
    }

    if (slotCompletedToday) {
      activeDateKeys.remove(formatJsonDate(today)!);
    }
    return activeDateKeys.values.toList(growable: false)..sort();
  }

  // Function Name: slotTitle
  // Description: Selects a localized medication slot title, using a general schedule label for unknown keys.
  // Parameters:
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // - language (String): Language code used for display or speech guidance.
  // Returns:
  // - String: Selects a localized medication slot title, using a general schedule label for unknown keys.
  static String slotTitle(String slotKey, String language) {
    final isEnglish = isEnglishLanguage(language);
    return medicationSlotLabel(
      slotKey,
      isEnglish: isEnglish,
      fallback: isEnglish ? 'Schedule' : '일정',
    );
  }

  // Function Name: dispose
  // Description: Releases the control resources owned by the live composition through its injected cleanup callback.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  void dispose() {
    _onDispose?.call();
  }
}

// Class Name: MedicationReminderBackgroundScheduler
// Role: Registers reminder-window replenishment for the authenticated patient.
// Responsibilities:
// - Replace previous patient work and schedule network-constrained Android refreshes every 12 hours; cancel them at session end.
// Attributes:
// - None; static operations use Workmanager and the persisted reminder-owner preference.
class MedicationReminderBackgroundScheduler {
  // Function Name: MedicationReminderBackgroundScheduler._
  // Description: Restricts periodic medication-reminder scheduling to the static registration and cancellation API.
  // Parameters:
  // - None.
  // Returns:
  // - MedicationReminderBackgroundScheduler: the initialized instance.
  MedicationReminderBackgroundScheduler._();

  // Function Name: _supportsBackgroundWork
  // Description: Allows background registration only on nonweb Android targets running on Android.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Allows background registration only on nonweb Android targets running on Android.
  static bool get _supportsBackgroundWork {
    return !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        Platform.isAndroid;
  }

  // Function Name: register
  // Description: Cancels prior reminder-tag work when ownership changes, then creates or updates the patient's network-constrained 12-hour task.
  // Parameters:
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  static Future<void> register(String patientHash) async {
    if (!_supportsBackgroundWork) {
      return;
    }
    final normalizedHash = PatientHash.normalizePatientHash(patientHash);
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    if (preferences.getString(_reminderWorkerOwnerKey) != normalizedHash) {
      await Workmanager().cancelByTag(_medicationReminderBackgroundTag);
      await preferences.setString(_reminderWorkerOwnerKey, normalizedHash);
    }
    await Workmanager().registerPeriodicTask(
      '$_medicationReminderBackgroundTag.$normalizedHash',
      medicationReminderBackgroundTask,
      frequency: const Duration(hours: 12),
      inputData: {
        'patient_hash': normalizedHash,
        'base_url': ApiConfig.baseUrl,
      },
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
      tag: _medicationReminderBackgroundTag,
    );
  }

  // Function Name: ownsReminders
  // Description: Reloads the persisted worker owner so a running refresh can detect cancellation or another account around each reminder write.
  // Parameters:
  // - patientHash (String): Account of the running worker.
  // Returns:
  // - Future<bool>: true while that account is the registered owner, and always off Android.
  static Future<bool> ownsReminders(String patientHash) async {
    if (!_supportsBackgroundWork) {
      return true;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(_reminderWorkerOwnerKey) ==
        PatientHash.normalizePatientHash(patientHash);
  }

  // Function Name: cancel
  // Description: Cancels all reminder-replenishment tasks for sign-out or account deletion on supported Android platforms.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  static Future<void> cancel() async {
    if (!_supportsBackgroundWork) {
      return;
    }
    await Workmanager().cancelByTag(_medicationReminderBackgroundTag);
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_reminderWorkerOwnerKey);
  }
}
