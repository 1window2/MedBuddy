// File Name: medication_notification_selection_entity.dart
// Role: Defines platform-independent notification destinations and action arguments.

import 'caregiver_alert_context_entity.dart';

// Class Name: MedicationNotificationDestination
// Role: Identify the screen targeted by a medication-related notification.
// Responsibilities: Keep routing choices independent of platform payload formats.
// Attributes: schedule: own doses; caregiverSchedule: linked patient's doses; linkedChat: linked conversation.
enum MedicationNotificationDestination {
  schedule,
  caregiverSchedule,
  linkedChat,
}

// Class Name: MedicationNotificationAction
// Role: Identify the operation requested by a notification interaction.
// Responsibilities: Separate navigation, dose recording and reminder/caregiver actions.
// Attributes: open, markSlotTaken, snoozeTenMinutes, caregiverSnooze and caregiverRequestCheck: supported interaction kinds.
enum MedicationNotificationAction {
  open,
  markSlotTaken,
  snoozeTenMinutes,
  caregiverSnooze,
  caregiverRequestCheck,
}

// Class Name: MedicationNotificationSelection
// Role: Carries a notification destination and its scoped navigation or action arguments.
// Responsibilities:
// - Preserve patient, link, slot, and notification identifiers so navigation and quick actions target the intended record.
// Attributes:
// - destination (MedicationNotificationDestination): Screen destination selected by the notification.
// - patientHash (String?): Ownership hash of the patient targeted by lookup, storage, or alerts.
// - linkId (int?): Link ID targeted by lookup, messaging, or monitoring.
// - slotKey (String?): Medication slot key: morning, lunch, evening, or bedtime.
// - notificationId (int?): Platform notification or server setting identifier.
// - action (MedicationNotificationAction): Selected open, completion, or snooze action.
// - scheduleDate (DateTime?): Original dose day; absent on legacy notifications.
class MedicationNotificationSelection {
  final MedicationNotificationDestination destination;
  final String? patientHash;
  final int? linkId;
  final String? slotKey;
  final int? notificationId;
  final MedicationNotificationAction action;
  final DateTime? scheduleDate;
  final CaregiverAlertContext? caregiverAlert;
  // Signed part of a schedule payload and the tag the app attached when it scheduled the
  // reminder; a quick action runs only when the tag verifies for the signed-in account.
  final String? signedPayload;
  final String? actionTag;

  // Function Name: MedicationNotificationSelection
  // Description: Captures a parsed notification destination with optional patient, link, slot, and notification identifiers plus the selected action.
  // Parameters:
  // - destination (MedicationNotificationDestination): Screen destination selected by the notification.
  // - patientHash (String?): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - linkId (int?): Link ID targeted by lookup, messaging, or monitoring.
  // - slotKey (String?): Medication slot key: morning, lunch, evening, or bedtime.
  // - notificationId (int?): Platform notification or server setting identifier.
  // - action (MedicationNotificationAction): Selected open, completion, or snooze action.
  // - scheduleDate (DateTime?): Original dose day, preserved across snoozes.
  // - caregiverAlert (CaregiverAlertContext?): Validated server delivery context for caregiver actions.
  // - signedPayload (String?): Schedule payload without its tag, as signed when scheduled.
  // - actionTag (String?): Tag proving the reminder came from this app; null for unsigned payloads.
  // Returns:
  // - MedicationNotificationSelection: the initialized instance.
  const MedicationNotificationSelection({
    required this.destination,
    this.patientHash,
    this.linkId,
    this.slotKey,
    this.notificationId,
    this.action = MedicationNotificationAction.open,
    this.scheduleDate,
    this.caregiverAlert,
    this.signedPayload,
    this.actionTag,
  });

  // Function Name: isForDate
  // Description: Rejects undated legacy actions and actions for a different dose day.
  // Parameters: date (DateTime): Current local calendar date.
  // Returns: Whether a quick action belongs to the supplied day.
  bool isForDate(DateTime date) =>
      scheduleDate != null &&
      scheduleDate!.year == date.year &&
      scheduleDate!.month == date.month &&
      scheduleDate!.day == date.day;
}

// 함수이름: MedicationNotificationSelectionHandler
// 함수역할: 해석된 알림 이동 대상과 사용자 액션을 앱 내비게이션 경계에 전달하는 계약이다.
// 매개변수:
// - selection (MedicationNotificationSelection): 해석된 알림 목적지와 액션 인자
// 반환값:
// - 없음.
typedef MedicationNotificationSelectionHandler =
    void Function(MedicationNotificationSelection selection);
