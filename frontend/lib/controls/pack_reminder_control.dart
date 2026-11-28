// 파일명: pack_reminder_control.dart
// 역할: 외출 전 약 챙기기 알림(점심·저녁 약이 있는 날 아침에 한 번)의 기기 설정과 예약 날짜를 정한다.
//   설정은 계정별로 기기에만 두고, 예약은 기존 날짜별 알림 예약(registerNotification)을 그대로 쓴다.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../entities/medication_reminder_text.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/medication_reminder_background_service.dart';

// 클래스명: PackReminderSetting
// 역할: 외출 전 약 챙기기 알림의 켜짐 여부, 시각, 요일(월=1 … 일=7).
class PackReminderSetting {
  static const defaultHour = 7;
  static const defaultMinute = 30;
  static const allWeekdays = {1, 2, 3, 4, 5, 6, 7};

  final bool enabled;
  final int hour;
  final int minute;
  final Set<int> weekdays;

  const PackReminderSetting({
    this.enabled = false,
    this.hour = defaultHour,
    this.minute = defaultMinute,
    this.weekdays = allWeekdays,
  });

  // 함수이름: fromJson
  // 함수역할: 저장한 설정을 읽는다. 값이 이상하면 그 항목만 기본값으로 둔다(요일이 비면 매일).
  // 매개변수: json: 저장 값. 반환값: 설정.
  factory PackReminderSetting.fromJson(Map<String, dynamic> json) {
    final time = '${json['time'] ?? ''}'.split(':');
    final hour = time.length == 2 ? int.tryParse(time[0]) : null;
    final minute = time.length == 2 ? int.tryParse(time[1]) : null;
    final days = <int>{
      if (json['days'] is List)
        for (final day in json['days'] as List)
          if (day is int && day >= 1 && day <= 7) day,
    };
    return PackReminderSetting(
      enabled: json['enabled'] == true,
      hour: hour != null && hour >= 0 && hour <= 23 ? hour : defaultHour,
      minute: minute != null && minute >= 0 && minute <= 59
          ? minute
          : defaultMinute,
      weekdays: days.isEmpty ? allWeekdays : days,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'time':
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
    'days': (weekdays.toList()..sort()),
  };

  // 함수이름: copyWith
  // 함수역할: 일부만 바꾼 설정을 만든다. 요일은 최소 하루가 남아야 한다.
  // 매개변수: enabled/hour/minute/weekdays: 바꿀 값. 반환값: 새 설정.
  PackReminderSetting copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    Set<int>? weekdays,
  }) => PackReminderSetting(
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    weekdays: weekdays == null || weekdays.isEmpty
        ? this.weekdays
        : Set.unmodifiable(weekdays),
  );

  @override
  bool operator ==(Object other) =>
      other is PackReminderSetting &&
      other.enabled == enabled &&
      other.hour == hour &&
      other.minute == minute &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays);

  @override
  int get hashCode =>
      Object.hash(enabled, hour, minute, Object.hashAllUnordered(weekdays));
}

// 함수이름: PackReminderRegistrar
// 함수역할: 날짜별 알림 예약 함수(SetNotification/NotificationService.registerNotification과 같은 모양).
typedef PackReminderRegistrar =
    Future<void> Function({
      required int id,
      required String slotKey,
      required String slotTitle,
      required int hour,
      required int minute,
      required List<DateTime> activeDates,
      String language,
    });

// 함수이름: PackReminderCanceler
// 함수역할: 기본 ID와 시간대 키로 날짜별 예약을 모두 지우는 함수.
typedef PackReminderCanceler = Future<void> Function(int id, {String? slotKey});

// 클래스명: PackReminderControl
// 역할: 설정 저장·조회와, 일정에서 알림 날짜를 정해 예약하거나 지우는 일을 맡는다(상태 없음).
class PackReminderControl {
  const PackReminderControl._();

  // 필요시 확인 알림(84005)과 시간대 알림 ID 범위(100000~1099999)와 겹치지 않는 기본 ID.
  static const notificationId = packReminderNotificationId;
  // 챙겨 갈 약으로 보는 시간대.
  static const packSlotKeys = {'lunch', 'evening'};

  // 함수이름: storageKeyFor
  // 함수역할: 계정별 설정 키. 계정 삭제가 이 키를 지운다.
  // 매개변수: patientHash: 계정. 반환값: 설정 키.
  static String storageKeyFor(String patientHash) =>
      'medbuddy_pack_reminder_$patientHash';

  // 함수이름: load
  // 함수역할: 계정의 설정을 읽는다. 없거나 손상됐으면 기본값(꺼짐, 07:30, 매일).
  // 매개변수: preferences: 저장소; patientHash: 계정. 반환값: 설정.
  static PackReminderSetting load(
    SharedPreferences preferences,
    String patientHash,
  ) {
    final raw = preferences.getString(storageKeyFor(patientHash));
    if (raw == null) return const PackReminderSetting();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? PackReminderSetting.fromJson(decoded)
          : const PackReminderSetting();
    } catch (_) {
      return const PackReminderSetting();
    }
  }

  // 함수이름: save
  // 함수역할: 계정의 설정을 저장한다.
  // 매개변수: preferences: 저장소; patientHash: 계정; setting: 설정. 반환값: 저장 성공 여부.
  static Future<bool> save(
    SharedPreferences preferences,
    String patientHash,
    PackReminderSetting setting,
  ) => preferences.setString(
    storageKeyFor(patientHash),
    jsonEncode(setting.toJson()),
  );

  // 함수이름: activeDates
  // 함수역할: 14일 창 안에서 점심·저녁 약 가운데 하나라도 먹는 날이고, 고른 요일인 날짜를 고른다.
  //   먹는 날 판단은 시간대 알림과 같은 activeReminderDates를 쓴다(격일·주 1회 약, 기간 끝 반영).
  // 매개변수: schedules: 오늘·기간 일정; setting: 설정; now: 현재 시각. 반환값: 정렬된 날짜.
  static List<DateTime> activeDates({
    required List<MedicationSchedule> schedules,
    required PackReminderSetting setting,
    required DateTime now,
  }) {
    final packSchedules = [
      for (final schedule in schedules)
        if (schedule.slotKeys.any(packSlotKeys.contains)) schedule,
    ];
    if (packSchedules.isEmpty) return const [];
    return MedicationReminderRefreshService.activeReminderDates(
      packSchedules,
      now: now,
    ).where((date) => setting.weekdays.contains(date.weekday)).toList();
  }

  // 함수이름: synchronize
  // 함수역할: 설정과 일정에 맞춰 외출 전 약 챙기기 알림을 다시 예약하거나 지운다. 알림이 꺼졌거나 설정이
  //   꺼졌거나 챙길 날이 없으면 지운다.
  // 매개변수: setting: 설정; schedules: 오늘·기간 일정; notificationsEnabled: 앱 복약 알림 허용;
  //   language: 알림 언어; register/cancel: 예약·취소 함수; now: 현재 시각;
  //   lastAllowedDate: 이 날짜 뒤는 예약하지 않는 상한(없으면 제한 없음).
  // 반환값: 완료 Future. 예약 오류는 호출자에게 전파한다.
  static Future<void> synchronize({
    required PackReminderSetting setting,
    required List<MedicationSchedule> schedules,
    required bool notificationsEnabled,
    required String language,
    required PackReminderRegistrar register,
    required PackReminderCanceler cancel,
    required DateTime now,
    DateTime? lastAllowedDate,
  }) async {
    final dates = notificationsEnabled && setting.enabled
        ? [
            for (final date in activeDates(
              schedules: schedules,
              setting: setting,
              now: now,
            ))
              if (lastAllowedDate == null || !date.isAfter(lastAllowedDate))
                date,
          ]
        : const <DateTime>[];
    if (dates.isEmpty) {
      await cancel(notificationId, slotKey: packReminderSlotKey);
      return;
    }
    await register(
      id: notificationId,
      slotKey: packReminderSlotKey,
      slotTitle: medicationReminderTitle(
        packReminderSlotKey,
        slotTitle: '',
        isEnglish: isEnglishLanguage(language),
      ),
      hour: setting.hour,
      minute: setting.minute,
      activeDates: dates,
      language: language,
    );
  }
}
