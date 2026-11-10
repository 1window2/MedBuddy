// File Name: caregiver_alert_context_entity.dart
// Role: Validates versioned missed-dose alert context and derives stable notification payloads.
// Role: Versioned, non-secret context for an original missed case and its delivery.
import 'dart:convert';

import 'medication_schedule_entity.dart';

// Function Name: fnv1a31
// Description: Folds a string with 32-bit FNV-1a masked to 31 bits, so notification IDs derived from it stay the same across isolates and app restarts. Callers map the result into their own ID range.
// Parameters:
// - source (String): Text that identifies the notification.
// Returns:
// - int: Non-negative hash below 2^31.
int fnv1a31(String source) {
  var hash = 0x811C9DC5;
  for (final unit in source.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7FFFFFFF;
  }
  return hash;
}

// Class Name: CaregiverAlertContext
// Role: Carries the validated link between a missed-dose case and one delivery event.
// Responsibilities: Serialize versioned action context and derive a stable recipient/event notification ID.
// Attributes: payloadPrefix (String): Versioned notification payload prefix; alertId/sourceAlertId/linkId (int): Delivery/source/link IDs; eventId/sourceEventId: Event hashes; patientHash/recipientHash: Account scope; slotKey/scheduleDate: Dose slot/day.
class CaregiverAlertContext {
  static const String payloadPrefix = 'caregiver-v1:';

  final int alertId;
  final int sourceAlertId;
  final int linkId;
  final String eventId;
  final String sourceEventId;
  final String patientHash;
  final String recipientHash;
  final String slotKey;
  final String scheduleDate;

  // Function Name: CaregiverAlertContext
  // Description: Captures delivery and source identifiers without validating them; external payloads should use fromData.
  // Parameters: alertId/sourceAlertId/linkId (int): IDs; eventId/sourceEventId (String): Hashes; patientHash/recipientHash (String): Accounts; slotKey/scheduleDate (String): Dose identity.
  // Returns: An immutable alert context.
  const CaregiverAlertContext({
    required this.alertId, required this.sourceAlertId, required this.linkId,
    required this.eventId, required this.sourceEventId, required this.patientHash,
    required this.recipientHash, required this.slotKey, required this.scheduleDate,
  });

  // Function Name: fromData
  // Description: Validates action version/type, positive IDs, canonical date, known slot, nonempty accounts, and lowercase 64-hex event hashes.
  // Parameters: data (Map<String, dynamic>): String-like notification data values.
  // Returns: Parsed context, or null for a missing/invalid field; this validates shape, not server authorization.
  static CaregiverAlertContext? fromData(Map<String, dynamic> data) {
    // Function Name: value
    // Description: Normalizes a single payload value for structural validation.
    // Parameters: key (String): Data field to inspect.
    // Returns: Trimmed string representation, or empty string for a missing/null field.
    String value(String key) => data[key]?.toString().trim() ?? '';
    // Function Name: positive
    // Description: Parses an identifier while rejecting zero, negative, and non-numeric payload values.
    // Parameters: key (String): Identifier field in the captured data map.
    // Returns: Strictly positive integer, otherwise null.
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
        !medicationScheduleSlotKeys.contains(value('slot_key')) ||
        value('patient_hash').isEmpty || value('recipient_hash').isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value('event_id')) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value('source_event_id'))) {
      return null;
    }
    return CaregiverAlertContext(
      alertId: alert, sourceAlertId: source, linkId: link,
      eventId: value('event_id'), sourceEventId: value('source_event_id'),
      patientHash: value('patient_hash'), recipientHash: value('recipient_hash'),
      slotKey: value('slot_key'), scheduleDate: value('schedule_date'),
    );
  }

  // Function Name: toData
  // Description: Serializes the context into version-1 notification data with string values.
  // Parameters: None.
  // Returns: Fresh map including the fixed caregiver_slot_missed type and action_version.
  Map<String, String> toData() => {
    'type': 'caregiver_slot_missed', 'action_version': '1',
    'alert_id': '$alertId', 'source_alert_id': '$sourceAlertId', 'link_id': '$linkId',
    'event_id': eventId, 'source_event_id': sourceEventId,
    'patient_hash': patientHash, 'recipient_hash': recipientHash,
    'slot_key': slotKey, 'schedule_date': scheduleDate,
  };

  // Function Name: payload
  // Description: Encodes versioned context for a notification tap without introducing raw JSON delimiters into the payload.
  // Parameters: None.
  // Returns: caregiver-v1 prefix followed by URI-encoded JSON; the payload is not secret or authenticated.
  String get payload => '$payloadPrefix${Uri.encodeComponent(jsonEncode(toData()))}';

  // Function Name: fromPayload
  // Description: Checks the prefix, decodes URI/JSON content, and applies the same field validation as server data.
  // Parameters: payload (String): Notification tap payload.
  // Returns: Validated context or null for another prefix, malformed encoding/JSON, non-object data, or invalid fields.
  static CaregiverAlertContext? fromPayload(String payload) {
    if (!payload.startsWith(payloadPrefix)) return null;
    try {
      final decoded = jsonDecode(Uri.decodeComponent(payload.substring(payloadPrefix.length)));
      return decoded is Map<String, dynamic> ? fromData(decoded) : null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  // Stable across isolates and FCM retries, but different for each snooze cycle.
  // Function Name: notificationId
  // Description: Derives the same platform ID for retries of one recipient/event and a different input for later snooze cycles.
  // Parameters: None.
  // Returns: Nonnegative 31-bit hash; hash collisions are possible.
  int get notificationId => fnv1a31('$recipientHash:$eventId');
}
