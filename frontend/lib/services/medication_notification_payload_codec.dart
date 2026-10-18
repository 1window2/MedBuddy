// File Name: medication_notification_payload_codec.dart
// Role: Validates notification wire payloads without initializing a platform plugin.

import '../entities/caregiver_alert_context_entity.dart';
import '../entities/caregiver_notification_entity.dart';
import '../entities/medication_notification_selection_entity.dart';

// Class Name: MedicationNotificationPayloadCodec
// Role: Owns the shared notification payload and action-identifier protocol.
// Responsibilities:
// - Decode personal schedules, legacy caregiver routes, versioned caregiver actions, and linked chats.
// - Reject malformed destinations while keeping cleanup classification prefix-based.
// Attributes:
// - Action identifier constants retain the Android notification button contract.
class MedicationNotificationPayloadCodec {
  // Function Name: MedicationNotificationPayloadCodec._
  // Description: Prevents instances of the stateless notification protocol utility.
  // Parameters: None.
  // Returns: A private codec instance, not exposed to callers.
  const MedicationNotificationPayloadCodec._();

  static const String markSlotTakenActionId = 'medbuddy_mark_slot_taken';
  static const String snoozeTenMinutesActionId = 'medbuddy_snooze_10_minutes';
  static const String caregiverSnoozeActionId = 'medbuddy_caregiver_snooze';
  static const String caregiverChatActionId = 'medbuddy_caregiver_chat';
  static const String caregiverPayloadPrefix = 'caregiver:';

  // Function Name: caregiverPayload
  // Description: Builds the legacy caregiver route that opens a linked patient's schedule; the caller trims the hash first where it needs to.
  // Parameters: patientHash (String): Patient hash, URI-encoded into the payload as given.
  // Returns: The payload "caregiver:<encoded patientHash>".
  static String caregiverPayload(String patientHash) =>
      '$caregiverPayloadPrefix${Uri.encodeComponent(patientHash)}';

  // Function Name: chatPayload
  // Description: Builds the route that opens one linked chat conversation.
  // Parameters: linkId (int): Patient-caregiver link ID of the conversation.
  // Returns: The payload "chat:<linkId>".
  static String chatPayload(int linkId) => 'chat:$linkId';

  // Function Name: decode
  // Description: Parses scoped destinations and only accepts actions supported by that payload type.
  // Parameters:
  // - payload (String?): Notification wire payload, including legacy undated schedules.
  // - actionId (String?): Selected platform notification button identifier.
  // - notificationId (int?): Platform reminder identifier overriding the encoded ID.
  // Returns: A validated selection, or null when the payload is malformed.
  static MedicationNotificationSelection? decode(
    String? payload, {
    String? actionId,
    int? notificationId,
  }) {
    if (payload?.startsWith('caregiver-v1:') ?? false) {
      final alert = CaregiverAlertContext.fromPayload(payload!);
      if (alert == null) return null;
      return MedicationNotificationSelection(
        destination: MedicationNotificationDestination.caregiverSchedule,
        patientHash: alert.patientHash,
        slotKey: alert.slotKey,
        linkId: alert.linkId,
        scheduleDate: DateTime.parse(alert.scheduleDate),
        caregiverAlert: alert,
        action: switch (actionId) {
          caregiverSnoozeActionId =>
            MedicationNotificationAction.caregiverSnooze,
          caregiverChatActionId =>
            MedicationNotificationAction.caregiverRequestCheck,
          _ => MedicationNotificationAction.open,
        },
      );
    }
    final segments = payload?.split(':') ?? const <String>[];
    if ((segments.length == 3 || segments.length == 4) &&
        segments[0] == 'schedule' &&
        caregiverNotificationSlotKeys.contains(
          segments[1].trim().toLowerCase(),
        )) {
      final encodedNotificationId = int.tryParse(segments[2]);
      if (encodedNotificationId == null || encodedNotificationId < 0) {
        return null;
      }
      DateTime? scheduleDate;
      if (segments.length == 4) {
        final rawDate = segments[3];
        scheduleDate = DateTime.tryParse(rawDate);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate) ||
            scheduleDate == null ||
            scheduleDate.toIso8601String().split('T').first != rawDate) {
          return null;
        }
      }
      return MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
        slotKey: segments[1].trim().toLowerCase(),
        notificationId: notificationId ?? encodedNotificationId,
        scheduleDate: scheduleDate,
        // 필요시 확인 알림은 복용 처리와 다시 알림을 자동 실행하지 않는다.
        action: segments[1].trim().toLowerCase() == 'as_needed'
            ? MedicationNotificationAction.open
            : switch (actionId) {
                markSlotTakenActionId =>
                  MedicationNotificationAction.markSlotTaken,
                snoozeTenMinutesActionId =>
                  MedicationNotificationAction.snoozeTenMinutes,
                _ => MedicationNotificationAction.open,
              },
      );
    }
    if (segments.length == 2 &&
        segments[0] == 'caregiver' &&
        segments[1].trim().isNotEmpty) {
      try {
        final patientHash = Uri.decodeComponent(segments[1]).trim();
        if (patientHash.isEmpty) return null;
        return MedicationNotificationSelection(
          destination: MedicationNotificationDestination.caregiverSchedule,
          patientHash: patientHash,
        );
      } on FormatException {
        return null;
      } on ArgumentError {
        return null;
      }
    }
    if (segments.length == 2 && segments[0] == 'chat') {
      final linkId = int.tryParse(segments[1]);
      if (linkId == null || linkId < 1) return null;
      return MedicationNotificationSelection(
        destination: MedicationNotificationDestination.linkedChat,
        linkId: linkId,
      );
    }
    return null;
  }

  // Function Name: isSessionPayload
  // Description: Classifies MedBuddy prefixes for sign-out cleanup, even when a payload is malformed.
  // Parameters: payload (String?): Stored platform notification payload.
  // Returns: Whether session cleanup owns the notification.
  static bool isSessionPayload(String? payload) =>
      payload?.startsWith('schedule:') == true ||
      payload?.startsWith('caregiver-v1:') == true ||
      payload?.startsWith(caregiverPayloadPrefix) == true ||
      payload?.startsWith('chat:') == true;
}
