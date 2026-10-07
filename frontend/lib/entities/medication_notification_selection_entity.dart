// File Name: medication_notification_selection_entity.dart
// Role: Defines platform-independent notification destinations and action arguments.

import 'caregiver_alert_context_entity.dart';

// 클래스명: MedicationNotificationDestination
// 역할: 복약 일정·보호자 환자 일정·가족 채팅 알림의 이동 대상을 구분한다.
// 주요 책임:
// - payload 해석과 앱 내 경로 선택에서 동일한 목적지 분류를 사용하게 한다.
enum MedicationNotificationDestination {
  schedule,
  caregiverSchedule,
  linkedChat,
}

// Class Name: MedicationNotificationAction
// Role: Distinguishes opening a reminder, completing its slot, and snoozing for ten minutes.
// Responsibilities:
// - Preserve the selected system-notification action for application dispatch.
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
