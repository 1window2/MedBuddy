// File Name: medication_reminder_background_service.dart
// Role: Replenishes dated patient reminders from server schedules and manages periodic Android refresh work.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../controls/app_language_control.dart';
import '../controls/check_schedule_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../controls/set_notification_control.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../entities/user_setting_entity.dart';
import 'api_config.dart';
import 'notification_service.dart';

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

const String medicationReminderBackgroundTask =
    'medbuddy_medication_reminder_refresh';
const String _medicationReminderBackgroundTag = 'medbuddy_medication_reminder';

// 클래스명: MedicationReminderRefreshService
// 역할: 서버 상태를 기준으로 제한된 로컬 복약 알림 기간을 다시 구성한다.
// 주요 책임:
// - 현재 사용자의 활성 알림 설정과 복약 일정을 불러온다.
// - 복용 종료일을 넘지 않는 범위에서 다음 14일 알림을 예약한다.
// - 서버 설정을 끄지 않고 오래된 로컬 알림만 취소한다.
// 속성:
// - _loadSettings (MedicationAlarmSettingsLoader): 시간대별 알림 조건 조회 경계
// - _loadSchedules (MedicationScheduleLoader): 대상 환자의 복약 일정 조회 경계
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
    ReminderUserSettingLoader? loadUserSetting,
    required MedicationReminderRegistrar registerReminder,
    required MedicationReminderCanceler cancelReminder,
    ReminderPreferencesLoader preferencesLoader = SharedPreferences.getInstance,
    ReminderPrivacySetter? setPrivacy,
    DateTime Function()? now,
    VoidCallback? onDispose,
  }) : _loadSettings = loadSettings,
       _loadSchedules = loadSchedules,
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

  // 함수이름: MedicationReminderRefreshService.live
  // 함수역할: 환자 범위의 설정·일정 Control을 만들고 로컬 알림 예약·취소 및 민감정보 정책과 함께 갱신 서비스에 연결한다.
  // 매개변수:
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - baseUrl (String): 복약 API 기본 주소
  // - client (http.Client?): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
  // - notificationService (NotificationService?): 플랫폼 로컬 알림 서비스
  // 반환값:
  // - MedicationReminderRefreshService: 초기화된 인스턴스.
  factory MedicationReminderRefreshService.live({
    required String patientHash,
    String baseUrl = ApiConfig.baseUrl,
    http.Client? client,
    NotificationService? notificationService,
  }) {
    final normalizedPatientHash = PatientHash.normalizePatientHash(patientHash);
    final alarmControl = SetNotification(
      baseUrl: baseUrl,
      patientHash: normalizedPatientHash,
      client: client,
    );
    final scheduleControl = CheckSchedule(
      baseUrl: baseUrl,
      patientHash: normalizedPatientHash,
      client: client,
    );
    final userSettingControl = ManageUserSetting(
      baseUrl: baseUrl,
      userHash: normalizedPatientHash,
      client: client,
      useRemotePersistence: false,
    );
    final resolvedNotificationService =
        notificationService ?? NotificationService.instance;
    return MedicationReminderRefreshService(
      loadSettings: alarmControl.requestMedicationAlarm,
      loadSchedules: scheduleControl.requestMedicationScheduleWindow,
      loadUserSetting: userSettingControl.requestUserSetting,
      registerReminder: resolvedNotificationService.registerNotification,
      cancelReminder: resolvedNotificationService.cancelReminder,
      setPrivacy: resolvedNotificationService.setShowSensitiveDetails,
      onDispose: /* 함수이름: onDispose 콜백
       * 함수역할: 갱신 서비스가 생성한 알림·일정·사용자 설정 제어기를 해제한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 없음.
       */() {
        alarmControl.dispose();
        scheduleControl.dispose();
        userSettingControl.dispose();
      },
    );
  }

  // 함수이름: synchronize
  // 함수역할: 인증된 서버 상태를 기준으로 모든 로컬 시간대 알림을 갱신한다. 일시적 오류에서는 false를 반환해 Workmanager가 재시도하게 한다.
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
      final language = AppLanguageControl.resolveLanguage(
        userSetting.languageMode.isEmpty
            ? preferences.getString(AppLanguageControl.preferenceKey) ?? 'ko'
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
        final now = _now();
        final activeDates = activeReminderDates(slotSchedules, now: now);
        await _registerReminder(
          id: setting.notificationId,
          slotKey: setting.slotKey,
          slotTitle: slotTitle(slotKey, language),
          hour: setting.hour,
          minute: setting.minute,
          medicationNames: slotSchedules
              .map(/* 함수이름: map 콜백
               * 함수역할: 알림 언어에 맞는 약 표시 이름을 추출한다.
               * 매개변수:
               * - schedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
               * 반환값:
               * - 해당 언어의 약 표시 이름.
               */(schedule) => schedule.displayNameForLanguage(language))
              .where(/* Function Name: where callback
               * Description: Excludes medication names that contain only whitespace.
               * Parameters:
               * - name (String): Medication name being matched or selected for display.
               * Returns:
               * - Whether the name has non-whitespace content.
               */(name) => name.trim().isNotEmpty)
              .toSet()
              .toList(growable: false),
          activeDates: activeDates,
          medicationNamesByDate: medicationNamesForDates(
            slotSchedules,
            activeDates: activeDates,
            now: now,
            language: language,
          ),
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

  // Function Name: activeReminderDates
  // Description: Returns sorted unique local dates in the next 14-day window without extending beyond course end; missing start dates use today and unknown durations do not extend beyond today.
  // Parameters:
  // - schedules (List<MedicationSchedule>): Medication schedules used for lookup, comparison, or reminders.
  // - now (DateTime): Reference timestamp for comparisons and calendar calculations.
  // Returns:
  // - List<DateTime>: Sorted unique local dates in the next 14-day window without extending beyond course end; missing start dates use today and unknown durations do not extend beyond today.
  static List<DateTime> activeReminderDates(
    List<MedicationSchedule> schedules, {
    required DateTime now,
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
          : today;
      var candidateDate = startDate.isAfter(today) ? startDate : today;
      final boundedEndDate = endDate.isBefore(lastReservableDate)
          ? endDate
          : lastReservableDate;

      while (!candidateDate.isAfter(boundedEndDate)) {
        activeDateKeys[_dateKey(candidateDate)] = candidateDate;
        candidateDate = candidateDate.add(const Duration(days: 1));
      }
    }

    return activeDateKeys.values.toList(growable: false)..sort();
  }

  // 함수이름: medicationNamesForDates
  // 함수역할: 각 알림 날짜에 실제 복용 중인 약 이름만 구성한다.
  // 매개변수:
  // - schedules (List<MedicationSchedule>): 한 알림 시간대에 배정된 복약 일정
  // - activeDates (List<DateTime>): 로컬 알림을 받을 제한된 날짜 목록
  // - now (DateTime): 시작일이 없는 일정의 기준이 되는 현재 지역 시각
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - 지역 ISO 달력 날짜별 약 표시 이름 목록
  static Map<String, List<String>> medicationNamesForDates(
    List<MedicationSchedule> schedules, {
    required List<DateTime> activeDates,
    required DateTime now,
    required String language,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    return {
      for (final activeDate in activeDates)
        _dateKey(activeDate): schedules
            .where(
              // Function Name: where callback
              // Description: Includes schedules active on the reminder date, using today when their start date is absent.
              // Parameters:
              // - schedule (MedicationSchedule): Medication course with name, dose, duration, and slots.
              // Returns:
              // - Whether this schedule is active on the target date.
              (schedule) => _isScheduleActiveOnDate(
                schedule,
                activeDate,
                fallbackStartDate: today,
              ),
            )
            .map(/* 함수이름: map 콜백
             * 함수역할: 날짜별 알림 언어에 맞춘 약 표시 이름의 앞뒤 공백을 제거한다.
             * 매개변수:
             * - schedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
             * 반환값:
             * - 공백 정리된 번역 약 이름.
             */(schedule) => schedule.displayNameForLanguage(language).trim())
            .where(/* Function Name: where callback
             * Description: Keeps nonempty medication names for the reminder body.
             * Parameters:
             * - name (String): Medication name being matched or selected for display.
             * Returns:
             * - Whether the name is nonempty.
             */(name) => name.isNotEmpty)
            .toSet()
            .toList(growable: false),
    };
  }

  // Function Name: _isScheduleActiveOnDate
  // Description: Tests inclusive course boundaries using prescription date, creation date, or the supplied fallback, with unknown duration ending at the fallback date.
  // Parameters:
  // - schedule (MedicationSchedule): Medication course with name, dose, duration, and slots.
  // - date (DateTime): Timestamp used for calendar-date calculation or comparison.
  // - fallbackStartDate (DateTime): Start-date fallback when prescription and creation dates are absent.
  // Returns:
  // - bool: Tests inclusive course boundaries using prescription date, creation date, or the supplied fallback, with unknown duration ending at the fallback date.
  static bool _isScheduleActiveOnDate(
    MedicationSchedule schedule,
    DateTime date, {
    required DateTime fallbackStartDate,
  }) {
    final rawStartDate =
        schedule.prescriptionDate ?? schedule.createdDate ?? fallbackStartDate;
    final startDate = DateTime(
      rawStartDate.year,
      rawStartDate.month,
      rawStartDate.day,
    );
    final targetDate = DateTime(date.year, date.month, date.day);
    final courseDays = schedule.medicationTime;
    final endDate = courseDays > 0
        ? startDate.add(Duration(days: courseDays - 1))
        : fallbackStartDate;
    return !targetDate.isBefore(startDate) && !targetDate.isAfter(endDate);
  }

  // Function Name: slotTitle
  // Description: Selects a localized medication slot title, using a general schedule label for unknown keys.
  // Parameters:
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // - language (String): Language code used for display or speech guidance.
  // Returns:
  // - String: Selects a localized medication slot title, using a general schedule label for unknown keys.
  static String slotTitle(String slotKey, String language) {
    final isEnglish = language == 'en';
    return switch (slotKey) {
      'morning' => isEnglish ? 'Morning' : '아침',
      'lunch' => isEnglish ? 'Lunch' : '점심',
      'evening' => isEnglish ? 'Evening' : '저녁',
      'bedtime' => isEnglish ? 'Bedtime' : '취침 전',
      _ => isEnglish ? 'Schedule' : '일정',
    };
  }

  // Function Name: _dateKey
  // Description: Formats a local calendar date as a zero-padded YYYY-MM-DD key for dated reminder names.
  // Parameters:
  // - date (DateTime): Timestamp used for calendar-date calculation or comparison.
  // Returns:
  // - String: Formats a local calendar date as a zero-padded YYYY-MM-DD key for dated reminder names.
  static String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
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
    await Workmanager().cancelByTag(_medicationReminderBackgroundTag);
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
  }
}
