import 'medication_reminder_entity.dart';

// File Name: medication_alarm_entity.dart
// Role: Defines a patient-scoped medication alarm model.

// Class Name: MedicationAlarm
// Role: Represents one medication alarm setting for a patient and schedule slot.
// Responsibilities:
// - Preserve the patient scope, slot key, local alarm time, and enabled state.
// - Convert backend medication alarm JSON into the reminder model used by UI.
class MedicationAlarm {
  final String patientHash;
  final String slotKey;
  final int hour;
  final int minute;
  final bool enabled;

  const MedicationAlarm({
    required this.patientHash,
    required this.slotKey,
    required this.hour,
    required this.minute,
    required this.enabled,
  });

  factory MedicationAlarm.fromJson(Map<String, dynamic> json) {
    final slotKey = json['slot_key']?.toString() ?? 'morning';
    return MedicationAlarm(
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

  // Function Name: saveMedicationAlarm
  // Description:
  // - Class diagram compatible operation that returns the current payload.
  // Returns:
  // - JSON-compatible medication alarm dictionary.
  Map<String, dynamic> saveMedicationAlarm() {
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
