// File Name: medication_slot_label.dart
// Role: Provides the single Korean and English display name of each medication time slot.

// Function Name: medicationSlotLabelOrNull
// Description: Maps a medication slot key to its display name so every screen and notification uses the same wording; the key is matched exactly.
// Parameters:
// - slotKey (String): Slot key, one of morning, lunch, evening or bedtime.
// - isEnglish (bool): Whether to return the English name instead of the Korean one.
// - lowercase (bool): Whether to return the English sentence form (morning) instead of the title form (Morning); Korean names are unaffected.
// Returns:
// - The slot name, or null when the key is not one of the four slots.
String? medicationSlotLabelOrNull(
  String slotKey, {
  required bool isEnglish,
  bool lowercase = false,
}) {
  if (!isEnglish) {
    return switch (slotKey) {
      'morning' => '아침',
      'lunch' => '점심',
      'evening' => '저녁',
      'bedtime' => '취침 전',
      _ => null,
    };
  }
  final label = switch (slotKey) {
    'morning' => 'Morning',
    'lunch' => 'Lunch',
    'evening' => 'Evening',
    'bedtime' => 'Bedtime',
    _ => null,
  };
  return lowercase ? label?.toLowerCase() : label;
}

// Function Name: medicationSlotLabel
// Description: Maps a medication slot key to its title-form display name and lets the caller choose the text shown for an unknown key.
// Parameters:
// - slotKey (String): Slot key, one of morning, lunch, evening or bedtime.
// - isEnglish (bool): Whether to return the English name instead of the Korean one.
// - fallback (String?): Text returned for an unknown key; the key itself is returned when omitted.
// Returns:
// - The slot name, or the fallback (the key when no fallback is given) for an unknown key.
String medicationSlotLabel(
  String slotKey, {
  required bool isEnglish,
  String? fallback,
}) {
  return medicationSlotLabelOrNull(slotKey, isEnglish: isEnglish) ??
      fallback ??
      slotKey;
}
