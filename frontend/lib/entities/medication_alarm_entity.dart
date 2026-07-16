// File Name: medication_alarm_entity.dart
// Role: Defines a patient-scoped medication alarm model.

// Class Name: MedicationAlarm
// Role: Represents one medication alarm setting for a patient and schedule slot.
// Responsibilities:
// - Preserve the patient scope, slot key, local alarm time, and enabled state.
// - Convert backend medication alarm JSON into the UI alarm state.
class MedicationAlarm {
  final String patientHash;
  final String slotKey;
  final int hour;
  final int minute;
  final bool enabled;

  const MedicationAlarm({
    this.patientHash = '',
    required this.slotKey,
    required this.hour,
    required this.minute,
    required this.enabled,
  });

  factory MedicationAlarm.defaults(String slotKey) {
    return MedicationAlarm(
      slotKey: slotKey,
      hour: defaultHourFor(slotKey),
      minute: 0,
      enabled: false,
    );
  }

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

  Map<String, dynamic> toJson() {
    return {
      'patient_hash': patientHash,
      'slot_key': slotKey,
      'hour': hour,
      'minute': minute,
      'is_enabled': enabled,
    };
  }

  bool get isEnabled => enabled;

  int get notificationId {
    final normalizedPatientHash = patientHash.trim();
    if (normalizedPatientHash.isEmpty) {
      return legacyNotificationId;
    }

    return 100000 +
        (_stablePatientHash(normalizedPatientHash) % 100000) * 10 +
        _slotNotificationOffset(slotKey);
  }

  int get legacyNotificationId {
    return legacyNotificationIdForSlot(slotKey);
  }

  String get timeLabel {
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

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

  static int defaultHourFor(String slotKey) {
    return switch (slotKey) {
      'morning' => 8,
      'lunch' => 12,
      'evening' => 18,
      'bedtime' => 22,
      _ => 8,
    };
  }

  static int legacyNotificationIdForSlot(String slotKey) {
    return switch (slotKey) {
      'morning' => 1001,
      'lunch' => 1002,
      'evening' => 1003,
      'bedtime' => 1004,
      _ => 1099,
    };
  }

  static int _slotNotificationOffset(String slotKey) {
    return switch (slotKey) {
      'morning' => 1,
      'lunch' => 2,
      'evening' => 3,
      'bedtime' => 4,
      _ => 9,
    };
  }

  static int _stablePatientHash(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash;
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
