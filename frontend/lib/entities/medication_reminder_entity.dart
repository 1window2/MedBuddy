// 파일명: medication_reminder_entity.dart
// 역할: 오늘 복약 일정의 시간대별 알림 설정 모델을 정의한다.

// 클래스명: MedicationReminderSetting
// 역할: 아침, 점심, 저녁, 취침 전 알림의 시간과 활성화 상태를 보관한다.
// 주요 책임:
// - 로컬 저장소 JSON과 Dart 모델을 상호 변환한다.
// - 알림 플러그인에 사용할 안정적인 notification id를 제공한다.
class MedicationReminderSetting {
  final String slotKey;
  final int hour;
  final int minute;
  final bool isEnabled;

  const MedicationReminderSetting({
    required this.slotKey,
    required this.hour,
    required this.minute,
    required this.isEnabled,
  });

  factory MedicationReminderSetting.defaults(String slotKey) {
    return MedicationReminderSetting(
      slotKey: slotKey,
      hour: defaultHourFor(slotKey),
      minute: 0,
      isEnabled: false,
    );
  }

  factory MedicationReminderSetting.fromJson(Map<String, dynamic> json) {
    final slotKey = json['slot_key']?.toString() ?? 'morning';
    return MedicationReminderSetting(
      slotKey: slotKey,
      hour: _readInt(json['hour'], defaultHourFor(slotKey)),
      minute: _readInt(json['minute'], 0),
      isEnabled: json['is_enabled'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slot_key': slotKey,
      'hour': hour,
      'minute': minute,
      'is_enabled': isEnabled,
    };
  }

  int get notificationId {
    return switch (slotKey) {
      'morning' => 1001,
      'lunch' => 1002,
      'evening' => 1003,
      'bedtime' => 1004,
      _ => 1099,
    };
  }

  String get timeLabel {
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  MedicationReminderSetting copyWith({
    int? hour,
    int? minute,
    bool? isEnabled,
  }) {
    return MedicationReminderSetting(
      slotKey: slotKey,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  static int defaultHourFor(String slotKey) {
    return switch (slotKey) {
      'morning' => 8,
      'lunch' => 12,
      'evening' => 18,
      'bedtime' => 22,
      _ => 8,
    };
  }

  static int _readInt(dynamic value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
