// File Name: medbuddy_schedule_slot_policy.dart
// Role: Shared pure schedule-slot interpretation without feature-state dependencies.
import '../entities/medication_schedule_entity.dart';

// Function Name: resolveScheduleSlotKeys
// Description: Prefers explicit slots, then known daily frequency, then supported status-map keys, and finally the entity's default slot interpretation.
// Parameters:
// - schedule (MedicationSchedule): Medication course with name, dose, duration, and slots.
// Returns:
// - List<String>: Prefers explicit slots, then known daily frequency, then supported status-map keys, and finally the entity's default slot interpretation.
List<String> resolveScheduleSlotKeys(MedicationSchedule schedule) {
  if (schedule.scheduleSlotKeys.isNotEmpty) {
    return schedule.slotKeys;
  }
  if (schedule.dailyFrequencyCount > 0) {
    return medicationScheduleSlotKeysForFrequency(schedule.dailyFrequencyCount);
  }
  if (schedule.slotStatuses.isNotEmpty) {
    final slotKeys = medicationScheduleSlotKeys
        .where(
          /* 함수이름: where 콜백
           * 함수역할: 일정에 실제 상태 기록이 있는 시간대만 선택한다.
           * 매개변수:
           * - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
           * 반환값:
           * - 상태 맵에 해당 시간대 키가 있으면 true.
           */ (slotKey) => schedule.slotStatuses.containsKey(slotKey),
        )
        .toList(growable: false);
    if (slotKeys.isNotEmpty) {
      return slotKeys;
    }
  }
  return schedule.slotKeys;
}
