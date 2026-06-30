import 'medication_reminder_entity.dart';

// File Name: notification_setting_entity.dart
// Role: Defines a patient-scoped medication notification setting model.

// Class Name: NotificationSetting
// Role: Represents one medication alarm setting for a patient and schedule slot.
// Responsibilities:
// - Preserve the patient scope, slot key, local alarm time, and enabled state.
// - Convert backend notification setting JSON into the reminder model used by UI.
class NotificationSetting {
  final String patientHash;
  final String slotKey;
  final int hour;
  final int minute;
  final bool enabled;

  const NotificationSetting({
    required this.patientHash,
    required this.slotKey,
    required this.hour,
    required this.minute,
    required this.enabled,
  });

  factory NotificationSetting.fromJson(Map<String, dynamic> json) {
    final slotKey = json['slot_key']?.toString() ?? 'morning';
    return NotificationSetting(
      patientHash: json['patient_hash']?.toString() ?? '',
      slotKey: slotKey,
      hour: _readInt(
        json['hour'],
        MedicationReminderSetting.defaultHourFor(slotKey),
      ),
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

  // Function Name: saveNotificationSetting
  // Description:
  // - Class diagram compatible operation that returns the current payload.
  // Returns:
  // - JSON-compatible notification setting dictionary.
  Map<String, dynamic> saveNotificationSetting() {
    return toJson();
  }

  MedicationReminderSetting toMedicationReminderSetting() {
    return MedicationReminderSetting(
      slotKey: slotKey,
      hour: hour,
      minute: minute,
      isEnabled: enabled,
    );
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
