// File Name: medication_alarm_entity.dart
// Role: Defines a patient-scoped medication alarm model.

// 클래스명: MedicationAlarm
// 역할: 환자와 복약 시간대에 속한 알림 시각 및 활성화 상태를 표현한다.
// 주요 책임:
// - 서버 설정을 변환하고 환자별 안정 ID와 구형 시간대 ID를 제공한다.
// 속성:
// - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
// - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
// - hour (int): 24시간제 지역 시각의 시
// - minute (int): 지역 시각의 분
// - enabled (bool): 적용하거나 보존할 기능·알림 활성 상태
class MedicationAlarm {
  final String patientHash;
  final String slotKey;
  final int hour;
  final int minute;
  final bool enabled;

  // Function Name: MedicationAlarm
  // Description: Captures the patient scope, schedule slot, local hour and minute, and enabled flag for one medication reminder.
  // Parameters:
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // - hour (int): Local hour in 24-hour time.
  // - minute (int): Minute component of local time.
  // - enabled (bool): Feature or alarm enabled state to apply or retain.
  // Returns:
  // - MedicationAlarm: the initialized instance.
  const MedicationAlarm({
    this.patientHash = '',
    required this.slotKey,
    required this.hour,
    required this.minute,
    required this.enabled,
  });

  // 함수이름: MedicationAlarm.defaults
  // 함수역할: 시간대별 기본 시각 또는 지정한 시각을 사용해 비활성 상태의 새 알림 설정을 만든다.
  // 매개변수:
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // - hour (int?): 24시간제 지역 시각의 시
  // - minute (int?): 지역 시각의 분
  // 반환값:
  // - MedicationAlarm: 초기화된 인스턴스.
  factory MedicationAlarm.defaults(String slotKey, {int? hour, int? minute}) {
    return MedicationAlarm(
      slotKey: slotKey,
      hour: hour ?? defaultHourFor(slotKey),
      minute: minute ?? 0,
      enabled: false,
    );
  }

  // Function Name: MedicationAlarm.fromJson
  // Description: Decodes patient and slot alarm fields, using per-slot default hours and supporting both enabled-field spellings.
  // Parameters:
  // - json (Map<String, dynamic>): Backend response or stored JSON object for this model.
  // Returns:
  // - MedicationAlarm: the decoded record after field validation and default handling.
  factory MedicationAlarm.fromJson(Map<String, dynamic> json) {
    final slotKey = json['slot_key']?.toString() ?? 'morning';
    return MedicationAlarm(
      patientHash: json['patient_hash']?.toString() ?? '',
      slotKey: slotKey,
      hour: _readInt(json['hour'], defaultHourFor(slotKey)),
      minute: _readInt(json['minute'], 0),
      enabled: json['is_enabled'] == true || json['enabled'] == true,
    );
  }

  // Function Name: toJson
  // Description: Serializes patient scope, slot, local time, and enabled state using the backend alarm-setting keys.
  // Parameters:
  // - None.
  // Returns:
  // - Map<String, dynamic>: Serializes patient scope, slot, local time, and enabled state using the backend alarm-setting keys.
  Map<String, dynamic> toJson() {
    return {
      'patient_hash': patientHash,
      'slot_key': slotKey,
      'hour': hour,
      'minute': minute,
      'is_enabled': enabled,
    };
  }

  // Function Name: isEnabled
  // Description: Exposes whether this schedule-slot alarm is enabled for registration.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Feature or alarm enabled state to apply or retain.
  bool get isEnabled => enabled;

  // Function Name: notificationId
  // Description: Derives a stable patient-scoped notification ID and falls back to the legacy slot ID when no patient hash is present.
  // Parameters:
  // - None.
  // Returns:
  // - int: Derives a stable patient-scoped notification ID and falls back to the legacy slot ID when no patient hash is present.
  int get notificationId {
    final normalizedPatientHash = patientHash.trim();
    if (normalizedPatientHash.isEmpty) {
      return legacyNotificationId;
    }

    return 100000 +
        (_stablePatientHash(normalizedPatientHash) % 100000) * 10 +
        _slotNotificationOffset(slotKey);
  }

  // Function Name: legacyNotificationId
  // Description: Exposes the old slot-only notification ID so previously scheduled alarms can be canceled during migration.
  // Parameters:
  // - None.
  // Returns:
  // - int: The old slot-only notification ID so previously scheduled alarms can be canceled during migration.
  int get legacyNotificationId {
    return legacyNotificationIdForSlot(slotKey);
  }

  // Function Name: timeLabel
  // Description: Formats the stored local alarm hour and minute as zero-padded HH:mm text.
  // Parameters:
  // - None.
  // Returns:
  // - String: Formats the stored local alarm hour and minute as zero-padded HH:mm text.
  String get timeLabel {
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  // Function Name: copyWith
  // Description: Creates an alarm with supplied scope, time, or enabled changes while retaining all unspecified settings.
  // Parameters:
  // - patientHash (String?): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - slotKey (String?): Medication slot key: morning, lunch, evening, or bedtime.
  // - hour (int?): Local hour in 24-hour time.
  // - minute (int?): Minute component of local time.
  // - enabled (bool?): Feature or alarm enabled state to apply or retain.
  // Returns:
  // - MedicationAlarm: a copy with supplied replacements and all other fields preserved.
  MedicationAlarm copyWith({
    String? patientHash,
    String? slotKey,
    int? hour,
    int? minute,
    bool? enabled,
  }) {
    return MedicationAlarm(
      patientHash: patientHash ?? this.patientHash,
      slotKey: slotKey ?? this.slotKey,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      enabled: enabled ?? this.enabled,
    );
  }

  // Function Name: defaultHourFor
  // Description: Selects 08:00, 12:00, 18:00, or 22:00 by medication slot, defaulting to the morning hour for an unknown key.
  // Parameters:
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // Returns:
  // - int: Selects 08:00, 12:00, 18:00, or 22:00 by medication slot, defaulting to the morning hour for an unknown key.
  static int defaultHourFor(String slotKey) {
    return switch (slotKey) {
      'morning' => 8,
      'lunch' => 12,
      'evening' => 18,
      'bedtime' => 22,
      _ => 8,
    };
  }

  // Function Name: legacyNotificationIdForSlot
  // Description: Maps known slots to legacy IDs 1001 through 1004 and uses 1099 for an unknown slot.
  // Parameters:
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // Returns:
  // - int: Maps known slots to legacy IDs 1001 through 1004 and uses 1099 for an unknown slot.
  static int legacyNotificationIdForSlot(String slotKey) {
    return switch (slotKey) {
      'morning' => 1001,
      'lunch' => 1002,
      'evening' => 1003,
      'bedtime' => 1004,
      _ => 1099,
    };
  }

  // Function Name: _slotNotificationOffset
  // Description: Maps supported slots to offsets 1 through 4 in a patient's notification-ID range, with 9 as the unknown-slot offset.
  // Parameters:
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // Returns:
  // - int: Maps supported slots to offsets 1 through 4 in a patient's notification-ID range, with 9 as the unknown-slot offset.
  static int _slotNotificationOffset(String slotKey) {
    return switch (slotKey) {
      'morning' => 1,
      'lunch' => 2,
      'evening' => 3,
      'bedtime' => 4,
      _ => 9,
    };
  }

  // Function Name: _stablePatientHash
  // Description: Folds patient-key code units with multiplier 31 into a deterministic nonnegative 31-bit notification hash.
  // Parameters:
  // - value (String): Patient hash used to partition notification identifiers.
  // Returns:
  // - int: Folds patient-key code units with multiplier 31 into a deterministic nonnegative 31-bit notification hash.
  static int _stablePatientHash(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash;
  }

  // Function Name: _readInt
  // Description: Reads an integer or numeric string, truncating other numeric inputs, and uses the supplied fallback when parsing fails.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // - fallback (int): Fallback for absent or unparseable input.
  // Returns:
  // - int: Reads an integer or numeric string, truncating other numeric inputs, and uses the supplied fallback when parsing fails.
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
