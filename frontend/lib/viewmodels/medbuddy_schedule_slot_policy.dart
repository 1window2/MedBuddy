// File Name: medbuddy_schedule_slot_policy.dart
// Role: Shared pure schedule-slot interpretation without feature-state dependencies.
import '../entities/medication_schedule_entity.dart';

// Function Name: resolveScheduleSlotKeys
// Description: Returns the slot keys of a medication course. The rule itself lives in MedicationSchedule.slotKeys so that screen grouping, dose recording, reminders and the widget cannot disagree.
// Parameters:
// - schedule (MedicationSchedule): Medication course with name, dose, duration, and slots.
// Returns:
// - List<String>: Empty for as-needed medication; otherwise explicit slots, recorded supported slots when frequency is unknown, or the frequency-derived/default slots.
List<String> resolveScheduleSlotKeys(MedicationSchedule schedule) {
  return schedule.slotKeys;
}
