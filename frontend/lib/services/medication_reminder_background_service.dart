// 파일명: medication_reminder_background_service.dart
// 역할: 백그라운드에서 로컬 복약 알림 예약 기간을 주기적으로 보충한다.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../controls/app_language_control.dart';
import '../controls/check_schedule_control.dart';
import '../controls/set_notification_control.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import 'api_config.dart';
import 'notification_service.dart';

typedef MedicationAlarmSettingsLoader =
    Future<List<MedicationAlarm>> Function();
typedef MedicationScheduleLoader = Future<List<MedicationSchedule>> Function();
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
typedef MedicationReminderCanceler =
    Future<void> Function(int id, {String? slotKey});
typedef ReminderPreferencesLoader = Future<SharedPreferences> Function();

const String medicationReminderBackgroundTask =
    'medbuddy_medication_reminder_refresh';
const String _medicationReminderBackgroundTag = 'medbuddy_medication_reminder';

// 클래스명: MedicationReminderRefreshService
// 역할: 서버 상태를 기준으로 제한된 로컬 복약 알림 기간을 다시 구성한다.
// 주요 책임:
// - 현재 사용자의 활성 알림 설정과 복약 일정을 불러온다.
// - 복용 종료일을 넘지 않는 범위에서 다음 14일 알림을 예약한다.
// - 서버 설정을 끄지 않고 오래된 로컬 알림만 취소한다.
class MedicationReminderRefreshService {
  static const int maximumReminderDatesPerSlot = 14;

  final MedicationAlarmSettingsLoader _loadSettings;
  final MedicationScheduleLoader _loadSchedules;
  final MedicationReminderRegistrar _registerReminder;
  final MedicationReminderCanceler _cancelReminder;
  final ReminderPreferencesLoader _loadPreferences;
  final DateTime Function() _now;
  final VoidCallback? _onDispose;

  MedicationReminderRefreshService({
    required MedicationAlarmSettingsLoader loadSettings,
    required MedicationScheduleLoader loadSchedules,
    required MedicationReminderRegistrar registerReminder,
    required MedicationReminderCanceler cancelReminder,
    ReminderPreferencesLoader preferencesLoader = SharedPreferences.getInstance,
    DateTime Function()? now,
    VoidCallback? onDispose,
  }) : _loadSettings = loadSettings,
       _loadSchedules = loadSchedules,
       _registerReminder = registerReminder,
       _cancelReminder = cancelReminder,
       _loadPreferences = preferencesLoader,
       _now = now ?? DateTime.now,
       _onDispose = onDispose;

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
    final resolvedNotificationService =
        notificationService ?? NotificationService.instance;
    return MedicationReminderRefreshService(
      loadSettings: alarmControl.requestMedicationAlarm,
      loadSchedules: scheduleControl.requestMedicationScheduleWindow,
      registerReminder: resolvedNotificationService.registerNotification,
      cancelReminder: resolvedNotificationService.cancelReminder,
      onDispose: () {
        alarmControl.dispose();
        scheduleControl.dispose();
      },
    );
  }

  // 함수이름: synchronize
  // 함수역할:
  // - 인증된 서버 상태를 기준으로 모든 로컬 시간대 알림을 갱신한다.
  // - 일시적 오류에서는 false를 반환해 Workmanager가 재시도하게 한다.
  // 반환값: 모든 시간대가 동기화되면 true, 아니면 false
  Future<bool> synchronize() async {
    try {
      final results = await Future.wait<Object>([
        _loadSettings(),
        _loadSchedules(),
        _loadPreferences(),
      ]);
      final settings = results[0] as List<MedicationAlarm>;
      final schedules = results[1] as List<MedicationSchedule>;
      final preferences = results[2] as SharedPreferences;
      final language = AppLanguageControl.normalizeLanguage(
        preferences.getString(AppLanguageControl.preferenceKey) ?? 'ko',
      );
      final settingsBySlot = {
        for (final setting in settings)
          setting.slotKey.trim().toLowerCase(): setting,
      };

      for (final slotKey in medicationScheduleSlotKeys) {
        final setting =
            settingsBySlot[slotKey] ?? MedicationAlarm.defaults(slotKey);
        final slotSchedules = schedules
            .where((schedule) => schedule.slotKeys.contains(slotKey))
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
              .map((schedule) => schedule.displayNameForLanguage(language))
              .where((name) => name.trim().isNotEmpty)
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

  // 함수이름: activeReminderDates
  // 함수역할: 복용 종료일을 넘지 않는 14일 단위 알림 날짜를 계산한다.
  // 매개변수:
  // - schedules: 한 알림 시간대의 활성 복약 일정
  // - now: 계산 기준이 되는 현재 지역 시각
  // 반환값: 정렬되고 중복 제거된 지역 달력 날짜 목록
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
  // - schedules: 한 알림 시간대에 배정된 복약 일정
  // - activeDates: 로컬 알림을 받을 제한된 날짜 목록
  // - now: 시작일이 없는 일정의 기준이 되는 현재 지역 시각
  // 반환값: 지역 ISO 달력 날짜별 약 표시 이름 목록
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
              (schedule) => _isScheduleActiveOnDate(
                schedule,
                activeDate,
                fallbackStartDate: today,
              ),
            )
            .map((schedule) => schedule.displayNameForLanguage(language).trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList(growable: false),
    };
  }

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

  static String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  void dispose() {
    _onDispose?.call();
  }
}

// 클래스명: MedicationReminderBackgroundScheduler
// 역할: 인증된 사용자의 복약 알림 보충 작업을 등록하고 취소한다.
class MedicationReminderBackgroundScheduler {
  MedicationReminderBackgroundScheduler._();

  static bool get _supportsBackgroundWork {
    return !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        Platform.isAndroid;
  }

  // 함수이름: register
  // 함수역할: 로그인 사용자를 위해 하루 두 번 네트워크 기반 갱신 작업을 등록한다.
  // 매개변수: patientHash - 백그라운드에서 복구할 서버 소유 사용자 범위
  // 반환값: Workmanager가 주기 작업을 등록하면 완료된다.
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

  // 함수이름: cancel
  // 함수역할: 로그아웃하거나 삭제된 계정의 알림 보충 작업을 중단한다.
  // 반환값: 모든 복약 알림 갱신 작업이 취소되면 완료된다.
  static Future<void> cancel() async {
    if (!_supportsBackgroundWork) {
      return;
    }
    await Workmanager().cancelByTag(_medicationReminderBackgroundTag);
  }
}
