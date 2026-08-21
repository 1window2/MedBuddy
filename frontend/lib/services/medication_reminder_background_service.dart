// File Name: medication_reminder_background_service.dart
// Role: Replenishes the rolling local medication-reminder window in background.

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

// Class Name: MedicationReminderRefreshService
// Role: Rebuilds the bounded local reminder window from server-owned state.
// Responsibilities:
// - Load the current user's enabled reminder settings and active schedules.
// - Schedule the next 14 days while respecting each medication course end.
// - Cancel stale local slots without disabling the user's server preference.
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

  // Function Name: synchronize
  // Description:
  // - Refreshes every local reminder slot from authenticated server state.
  // - Returns false on transient failure so Workmanager can retry later.
  // Returns:
  // - True when every slot was synchronized; otherwise false.
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
              .map((schedule) => schedule.displayName)
              .where((name) => name.trim().isNotEmpty)
              .toSet()
              .toList(growable: false),
          activeDates: activeDates,
          medicationNamesByDate: medicationNamesForDates(
            slotSchedules,
            activeDates: activeDates,
            now: now,
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
  // Description:
  // - Calculates a rolling 14-day reminder window bounded by course end dates.
  // Parameters:
  // - schedules: Active medication schedules for one reminder slot.
  // - now: Current local time used as the rolling-window anchor.
  // Returns:
  // - Sorted unique local calendar dates that should have reminders.
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

  // Function Name: medicationNamesForDates
  // Description:
  // - Builds each reminder date from only the medication courses active on
  //   that calendar date.
  // Parameters:
  // - schedules: Medication courses assigned to one reminder slot.
  // - activeDates: Bounded dates that will receive local notifications.
  // - now: Current local time used for schedules missing a persisted start.
  // Returns:
  // - Medication display names keyed by local ISO calendar date.
  static Map<String, List<String>> medicationNamesForDates(
    List<MedicationSchedule> schedules, {
    required List<DateTime> activeDates,
    required DateTime now,
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
            .map((schedule) => schedule.displayName.trim())
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

// Class Name: MedicationReminderBackgroundScheduler
// Role: Registers and cancels the authenticated rolling reminder refresh task.
class MedicationReminderBackgroundScheduler {
  MedicationReminderBackgroundScheduler._();

  static bool get _supportsBackgroundWork {
    return !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        Platform.isAndroid;
  }

  // Function Name: register
  // Description:
  // - Registers a twice-daily network-backed refresh for the signed-in user.
  // Parameters:
  // - patientHash: Server-owned user scope restored by Firebase in background.
  // Returns:
  // - Completes after Workmanager accepts the periodic task.
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
  // Description:
  // - Prevents a signed-out or deleted account from replenishing reminders.
  // Returns:
  // - Completes after all medication reminder refresh work is canceled.
  static Future<void> cancel() async {
    if (!_supportsBackgroundWork) {
      return;
    }
    await Workmanager().cancelByTag(_medicationReminderBackgroundTag);
  }
}
