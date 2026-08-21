// 파일명: caregiver_notification_entity.dart
// 역할: 보호자별 환자 복약 시간대의 알림 조건과 마감 시각을 표현한다.

const List<String> caregiverNotificationSlotKeys = [
  'morning',
  'lunch',
  'evening',
  'bedtime',
];

enum CaregiverNotificationMode {
  disabled('disabled'),
  doseCompleted('dose_completed'),
  missedDeadline('missed_deadline');

  final String wireValue;

  const CaregiverNotificationMode(this.wireValue);

  static CaregiverNotificationMode fromValue(dynamic value) {
    final normalizedValue = value?.toString().trim().toLowerCase() ?? '';
    return switch (normalizedValue) {
      'enable' ||
      'enabled' ||
      'on' ||
      'true' ||
      '1' => CaregiverNotificationMode.doseCompleted,
      'dose_completed' => CaregiverNotificationMode.doseCompleted,
      'missed_deadline' => CaregiverNotificationMode.missedDeadline,
      _ => CaregiverNotificationMode.disabled,
    };
  }
}

// 클래스명: CaregiverNotification
// 역할: 한 보호자와 환자의 특정 복약 시간대에 적용되는 알림 조건을 보관한다.
class CaregiverNotification {
  final int? notificationId;
  final String caregiverHash;
  final String patientHash;
  final String slotKey;
  final CaregiverNotificationMode mode;
  final int? deadlineHour;
  final int? deadlineMinute;

  const CaregiverNotification({
    this.notificationId,
    this.caregiverHash = '',
    this.patientHash = '',
    this.slotKey = 'morning',
    this.mode = CaregiverNotificationMode.disabled,
    this.deadlineHour,
    this.deadlineMinute,
  });

  bool get notificationEnabled => mode != CaregiverNotificationMode.disabled;

  String get notificationType => mode.wireValue;

  bool get hasValidDeadline {
    return deadlineHour != null &&
        deadlineMinute != null &&
        deadlineHour! >= 0 &&
        deadlineHour! <= 23 &&
        deadlineMinute! >= 0 &&
        deadlineMinute! <= 59;
  }

  factory CaregiverNotification.fromJson(Map<String, dynamic> json) {
    final rawMode =
        json['notification_type'] ??
        json['notificationType'] ??
        json['alert_option'] ??
        json['alertOption'];
    final rawEnabled =
        json['notification_enabled'] ??
        json['notificationEnabled'] ??
        json['is_enabled'] ??
        json['enabled'];
    final mode = rawMode == null
        ? CaregiverNotificationMode.fromValue(rawEnabled)
        : CaregiverNotificationMode.fromValue(rawMode);

    return CaregiverNotification(
      notificationId: _readInt(
        json['notification_id'] ??
            json['notificationId'] ??
            json['setting_id'] ??
            json['id'],
      ),
      caregiverHash: _readString(
        json['caregiver_hash'] ??
            json['guardian_hash'] ??
            json['caregiver_id'] ??
            json['caregiverID'] ??
            json['guardian_id'] ??
            json['guardianID'],
      ),
      patientHash: _readString(
        json['patient_hash'] ?? json['patient_id'] ?? json['patientID'],
      ),
      slotKey: _readString(json['slot_key'] ?? json['slotKey']).isEmpty
          ? 'morning'
          : _readString(json['slot_key'] ?? json['slotKey']),
      mode: mode,
      deadlineHour: _readInt(json['deadline_hour'] ?? json['deadlineHour']),
      deadlineMinute: _readInt(
        json['deadline_minute'] ?? json['deadlineMinute'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notification_id': notificationId,
      'caregiver_hash': caregiverHash,
      'patient_hash': patientHash,
      'slot_key': slotKey,
      'notification_enabled': notificationEnabled,
      'notification_type': notificationType,
      'deadline_hour': deadlineHour,
      'deadline_minute': deadlineMinute,
    };
  }

  CaregiverNotification updateNotificationSetting(
    CaregiverNotificationMode nextMode, {
    int? deadlineHour,
    int? deadlineMinute,
  }) {
    final keepsDeadline = nextMode == CaregiverNotificationMode.missedDeadline;
    return copyWith(
      mode: nextMode,
      deadlineHour: keepsDeadline ? deadlineHour : null,
      deadlineMinute: keepsDeadline ? deadlineMinute : null,
      clearDeadline: !keepsDeadline,
    );
  }

  CaregiverNotification copyWith({
    int? notificationId,
    String? caregiverHash,
    String? patientHash,
    String? slotKey,
    CaregiverNotificationMode? mode,
    int? deadlineHour,
    int? deadlineMinute,
    bool clearDeadline = false,
  }) {
    return CaregiverNotification(
      notificationId: notificationId ?? this.notificationId,
      caregiverHash: caregiverHash ?? this.caregiverHash,
      patientHash: patientHash ?? this.patientHash,
      slotKey: slotKey ?? this.slotKey,
      mode: mode ?? this.mode,
      deadlineHour: clearDeadline ? null : deadlineHour ?? this.deadlineHour,
      deadlineMinute: clearDeadline
          ? null
          : deadlineMinute ?? this.deadlineMinute,
    );
  }

  static String _readString(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
