// Role: Versioned, non-secret context for an original missed case and its delivery.
import 'dart:convert';

class CaregiverAlertContext {
  final int alertId;
  final int sourceAlertId;
  final int linkId;
  final String eventId;
  final String sourceEventId;
  final String patientHash;
  final String recipientHash;
  final String slotKey;
  final String scheduleDate;

  const CaregiverAlertContext({
    required this.alertId, required this.sourceAlertId, required this.linkId,
    required this.eventId, required this.sourceEventId, required this.patientHash,
    required this.recipientHash, required this.slotKey, required this.scheduleDate,
  });

  static CaregiverAlertContext? fromData(Map<String, dynamic> data) {
    String value(String key) => data[key]?.toString().trim() ?? '';
    int? positive(String key) {
      final parsed = int.tryParse(value(key));
      return parsed != null && parsed > 0 ? parsed : null;
    }
    final alert = positive('alert_id');
    final source = positive('source_alert_id');
    final link = positive('link_id');
    final date = DateTime.tryParse(value('schedule_date'));
    if (value('type') != 'caregiver_slot_missed' || value('action_version') != '1' ||
        alert == null || source == null || link == null || date == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value('schedule_date')) ||
        date.toIso8601String().split('T').first != value('schedule_date') ||
        !const {'morning', 'lunch', 'evening', 'bedtime'}.contains(value('slot_key')) ||
        value('patient_hash').isEmpty || value('recipient_hash').isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value('event_id')) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value('source_event_id'))) return null;
    return CaregiverAlertContext(
      alertId: alert, sourceAlertId: source, linkId: link,
      eventId: value('event_id'), sourceEventId: value('source_event_id'),
      patientHash: value('patient_hash'), recipientHash: value('recipient_hash'),
      slotKey: value('slot_key'), scheduleDate: value('schedule_date'),
    );
  }

  Map<String, String> toData() => {
    'type': 'caregiver_slot_missed', 'action_version': '1',
    'alert_id': '$alertId', 'source_alert_id': '$sourceAlertId', 'link_id': '$linkId',
    'event_id': eventId, 'source_event_id': sourceEventId,
    'patient_hash': patientHash, 'recipient_hash': recipientHash,
    'slot_key': slotKey, 'schedule_date': scheduleDate,
  };

  String get payload => 'caregiver-v1:${Uri.encodeComponent(jsonEncode(toData()))}';

  static CaregiverAlertContext? fromPayload(String payload) {
    if (!payload.startsWith('caregiver-v1:')) return null;
    try {
      final decoded = jsonDecode(Uri.decodeComponent(payload.substring('caregiver-v1:'.length)));
      return decoded is Map<String, dynamic> ? fromData(decoded) : null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  // Stable across isolates and FCM retries, but different for each snooze cycle.
  int get notificationId {
    var hash = 2166136261;
    for (final unit in '$recipientHash:$eventId'.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0x7fffffff;
    }
    return hash;
  }
}
