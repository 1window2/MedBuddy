// File Name: medication_reminder_text.dart
// Role: Provides the single Korean and English wording of scheduled medication reminders, shared by the notifications and the inbox that shows them again.

const asNeededReminderSlotKey = 'as_needed';

// Function Name: medicationReminderTitle
// Description: Builds the reminder title for a slot; the as-needed check has its own fixed title.
// Parameters:
// - slotKey (String): Slot key, one of morning, lunch, evening, bedtime or as_needed.
// - slotTitle (String): Display name of the slot in the same language.
// - isEnglish (bool): Whether to return the English wording instead of the Korean one.
// Returns:
// - The reminder title.
String medicationReminderTitle(
  String slotKey, {
  required String slotTitle,
  required bool isEnglish,
}) {
  if (slotKey == asNeededReminderSlotKey) {
    return isEnglish ? 'As-needed medication check' : '필요시 약 확인';
  }
  return isEnglish ? '$slotTitle medication schedule' : '$slotTitle 복약 일정 확인';
}

// Function Name: medicationReminderBody
// Description: Builds the neutral reminder body. Android keeps this text until delivery, when the doses may already be recorded, so it never names pending medications.
// Parameters:
// - slotKey (String): Slot key, one of morning, lunch, evening, bedtime or as_needed.
// - isEnglish (bool): Whether to return the English wording instead of the Korean one.
// Returns:
// - The reminder body.
String medicationReminderBody(String slotKey, {required bool isEnglish}) {
  if (slotKey == asNeededReminderSlotKey) {
    return isEnglish
        ? 'Check your as-needed medication and recorded doses.'
        : '필요시 약과 오늘 기록한 복용 내역을 확인해 주세요.';
  }
  return isEnglish
      ? 'Check your medication schedule and recorded completion status.'
      : '복약 일정과 복용 완료 기록을 확인해 주세요.';
}
