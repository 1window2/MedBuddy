// File Name: medication_reminder_background_service.dart
// Role: Replenishes dated patient reminders from server schedules and manages periodic Android refresh work.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

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
// Description: Registers dated reminders for a slot with local time, localized title, active dates, and per-date medication names.
// Parameters:
// - id (int): Platform identifier used to schedule, replace, or cancel an alert.
// - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
// - slotTitle (String): Localized medication slot name.
// - hour (int): Local hour in 24-hour time.
// - minute (int): Minute component of local time.
// - medicationNames (List<String>): Medication display names used in reminders or recommendations.
// - activeDates (List<DateTime>): Reminder dates within the medication course.
// - medicationNamesByDate (Map<String, List<String>>): Active medication names grouped by calendar date.
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
      required List<String> medicationNames,
      required List<DateTime> activeDates,
      Map<String, List<String>> medicationNamesByDate,
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

// 함수이름: PendingDoseOperationsLoader
// 함수역할: 기기에 기록했지만 아직 서버에 올리지 못한 복용 기록을 오래된 순으로 읽는 계약이다.
// 매개변수:
// - 없음.
// 반환값:
// - Future<List<Map<String, dynamic>>>: 전송 대기 중인 복용 기록. 각 항목은 schedule_date, slot_key, medication_ids, completed를 담는다.
typedef PendingDoseOperationsLoader =
    Future<List<Map<String, dynamic>>> Function();

const String medicationReminderBackgroundTask =
    'medbuddy_medication_reminder_refresh';
const String _medicationReminderBackgroundTag = 'medbuddy_medication_reminder';
const String _reminderWorkerOwnerKey = 'medbuddy_reminder_worker_owner';

// 클래스명: MedicationReminderRefreshService
// 역할: 서버 상태를 기준으로 제한된 로컬 복약 알림 기간을 다시 구성한다.
// 주요 책임:
// - 현재 사용자의 활성 알림 설정과 복약 일정을 불러온다.
// - 복용 종료일을 넘지 않는 범위에서 다음 14일 알림을 예약한다.
// - 서버 설정을 끄지 않고 오래된 로컬 알림만 취소한다.
// 속성:
// - _loadSettings (MedicationAlarmSettingsLoader): 시간대별 알림 조건 조회 경계
// - _loadSchedules (MedicationScheduleLoader): 대상 환자의 복약 일정 조회 경계
// - _loadTodaySchedules (MedicationScheduleLoader?): 오늘 복용 완료 여부가 담긴 일정 조회 경계
// - _loadPendingDoses (PendingDoseOperationsLoader?): 아직 서버에 올리지 못한 기기의 복용 기록 조회 경계
// - _loadUserSetting (ReminderUserSettingLoader): 알림 허용·표시·언어를 정할 사용자 설정 조회
// - _registerReminder (MedicationReminderRegistrar): 날짜별 로컬 알림 예약 경계
// - _cancelReminder (MedicationReminderCanceler): ID 또는 시간대의 로컬 알림 취소 경계
// - _setPrivacy (ReminderPrivacySetter?): 알림의 민감정보 표시 정책 적용 경계
// - _now (DateTime Function()): 비교 기준 현재 시각 또는 주입할 시계
// - _onDispose (VoidCallback?): 소유한 의존성 정리 콜백
class MedicationReminderRefreshService {
  static const int maximumReminderDatesPerSlot = 14;

  final MedicationAlarmSettingsLoader _loadSettings;
  final MedicationScheduleLoader _loadSchedules;
  final MedicationScheduleLoader? _loadTodaySchedules;
  final PendingDoseOperationsLoader? _loadPendingDoses;
  final ReminderUserSettingLoader _loadUserSetting;
  final MedicationReminderRegistrar _registerReminder;
  final MedicationReminderCanceler _cancelReminder;
  final ReminderPreferencesLoader _loadPreferences;
  final ReminderPrivacySetter? _setPrivacy;
  final DateTime Function() _now;
  final VoidCallback? _onDispose;

  // 함수이름: MedicationReminderRefreshService
  // 함수역할: 알림 설정·일정·사용자 설정·저장소 조회와 예약·취소·개인정보 표시·시계 경계를 묶는다.
  // 매개변수:
  // - loadSettings (MedicationAlarmSettingsLoader): 시간대별 알림 조건 조회 경계
  // - loadSchedules (MedicationScheduleLoader): 대상 환자의 복약 일정 조회 경계
  // - loadTodaySchedules (MedicationScheduleLoader?): 오늘 복용 완료 여부가 담긴 일정 조회 경계. 기간 일정에는 완료 기록이 없으므로, 이미 복용한 시간대의 오늘 알림을 다시 예약하지 않으려면 필요하다.
  // - loadPendingDoses (PendingDoseOperationsLoader?): 아직 서버에 올리지 못한 기기의 복용 기록 조회 경계. 오프라인에서 복용을 기록한 시간대의 오늘 알림을 서버 응답만 보고 다시 예약하지 않으려면 필요하다.
  // - loadUserSetting (ReminderUserSettingLoader?): 알림 허용·표시·언어를 정할 사용자 설정 조회
  // - registerReminder (MedicationReminderRegistrar): 날짜별 로컬 알림 예약 경계
  // - cancelReminder (MedicationReminderCanceler): ID 또는 시간대의 로컬 알림 취소 경계
  // - preferencesLoader (ReminderPreferencesLoader): 기기 설정 저장소 제공 경계
  // - setPrivacy (ReminderPrivacySetter?): 알림의 민감정보 표시 정책 적용 경계
  // - now (DateTime Function()?): 현재 시각을 제공하는 주입 가능한 시계
  // - onDispose (VoidCallback?): 소유한 의존성 정리 콜백
  // 반환값:
  // - MedicationReminderRefreshService: 초기화된 인스턴스.
  MedicationReminderRefreshService({
    required MedicationAlarmSettingsLoader loadSettings,
    required MedicationScheduleLoader loadSchedules,
    MedicationScheduleLoader? loadTodaySchedules,
    PendingDoseOperationsLoader? loadPendingDoses,
    ReminderUserSettingLoader? loadUserSetting,
    required MedicationReminderRegistrar registerReminder,
    required MedicationReminderCanceler cancelReminder,
    ReminderPreferencesLoader preferencesLoader = SharedPreferences.getInstance,
    ReminderPrivacySetter? setPrivacy,
    DateTime Function()? now,
    VoidCallback? onDispose,
  }) : _loadSettings = loadSettings,
       _loadSchedules = loadSchedules,
       _loadTodaySchedules = loadTodaySchedules,
       _loadPendingDoses = loadPendingDoses,
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
       _onDispose = onDispose;

  // 함수이름: synchronize
  // 함수역할: 인증된 서버 상태를 기준으로 모든 로컬 시간대 알림을 갱신한다. 일시적 오류에서는 false를 반환해 Workmanager가 재시도하게 한다.
  //   오늘 이미 모두 복용한 시간대는 오늘 알림을 다시 예약하지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 모든 시간대가 동기화되면 true, 아니면 false
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
          // 오프라인에서 기록해 아직 서버에 없는 복용도 복용한 것으로 본다. 서버 응답만 보면 이미 복용한
          // 시간대의 오늘 알림을 다시 예약하게 된다.
          final pendingDoses = await _readPendingDoses();
          if (pendingDoses.isNotEmpty) {
            todaySchedules = projectDoseOperations(
              todaySchedules,
              pendingDoses,
              todayRequestDay,
            );
          }
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
        // 알림 문구는 약 이름을 쓰지 않으므로 이름 목록은 만들지 않는다.
        await _registerReminder(
          id: setting.notificationId,
          slotKey: setting.slotKey,
          slotTitle: slotTitle(slotKey, language),
          hour: setting.hour,
          minute: setting.minute,
          medicationNames: const [],
          activeDates: activeDates,
          language: language,
        );
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

  // 함수이름: _readPendingDoses
  // 함수역할: 서버에 아직 올라가지 않은 기기의 복용 기록을 읽는다. 저장소를 열지 못하면 빈 목록으로 보아
  //   서버 상태만으로 알림을 갱신한다. 기록을 읽지 못한다고 알림 갱신 전체를 멈추지는 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<List<Map<String, dynamic>>>: 전송 대기 중인 복용 기록, 없거나 읽지 못하면 빈 목록.
  Future<List<Map<String, dynamic>>> _readPendingDoses() async {
    final loadPendingDoses = _loadPendingDoses;
    if (loadPendingDoses == null) return const [];
    try {
      return await loadPendingDoses();
    } catch (error, stackTrace) {
      developer.log(
        'Pending dose records could not be read for the reminder refresh.',
        name: 'MedicationReminderRefreshService',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  // 함수이름: _isSlotCompletedToday
  // 함수역할: 오늘 일정에서 한 시간대의 약을 모두 복용했는지 판정한다. 조회 도중 날짜가 바뀌었거나 서버의 오늘과
  //   기기의 오늘이 다르면 완료로 보지 않아, 복용하지 않은 날의 알림이 빠지지 않게 한다.
  // 매개변수:
  // - todaySchedules (List<MedicationSchedule>): 완료 여부가 담긴 오늘 일정
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // - requestDay (String): 조회를 시작할 때의 서버 기준 날짜
  // - now (DateTime): 조회를 마친 뒤의 현재 시각
  // 반환값:
  // - bool: 오늘 그 시간대에 약이 있고 모두 복용했으면 true.
  static bool _isSlotCompletedToday(
    List<MedicationSchedule> todaySchedules,
    String slotKey, {
    required String requestDay,
    required DateTime now,
  }) {
    if (doseScheduleDay(now) != requestDay || _dateKey(now) != requestDay) {
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
    final lastReservableDate = today.add(
      const Duration(days: maximumReminderDatesPerSlot - 1),
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
          : lastReservableDate;
      var candidateDate = startDate.isAfter(today) ? startDate : today;
      final boundedEndDate = endDate.isBefore(lastReservableDate)
          ? endDate
          : lastReservableDate;

      while (!candidateDate.isAfter(boundedEndDate)) {
        // A medication that is not taken every day ("주 1회", "격일") is reminded on its dose days only.
        if (schedule.isDoseDay(candidateDate)) {
          activeDateKeys[_dateKey(candidateDate)] = candidateDate;
        }
        // Calendar arithmetic, so a daylight-saving change cannot repeat or skip a date.
        candidateDate = DateTime(
          candidateDate.year,
          candidateDate.month,
          candidateDate.day + 1,
        );
      }
    }

    if (slotCompletedToday) {
      activeDateKeys.remove(_dateKey(today));
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

  // Function Name: _dateKey
  // Description: Formats a local calendar date as a zero-padded YYYY-MM-DD key for dated reminder names.
  // Parameters:
  // - date (DateTime): Timestamp used for calendar-date calculation or comparison.
  // Returns:
  // - String: Formats a local calendar date as a zero-padded YYYY-MM-DD key for dated reminder names.
  static String _dateKey(DateTime date) => formatJsonDate(date)!;

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
  // Description: Cancels prior reminder-tag work and registers a network-constrained 12-hour refresh task for the normalized patient hash.
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
