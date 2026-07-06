import 'medication_schedule_entity.dart';

// File Name: today_medication_info_entity.dart
// Role: Entity for today's medication summary and schedule data.

// Class Name: TodayMedicationInfo
// Role: Represents the summary returned by CheckTodayMedicationInfo.
// Responsibilities:
// - Preserve the selected patient scope.
// - Carry dose-level progress counts for home and schedule views.
// - Keep the schedule list as MedicationSchedule entities.
class TodayMedicationInfo {
  final String patientHash;
  final int medicationCount;
  final int totalDoseCount;
  final int completedDoseCount;
  final int remainingDoseCount;
  final double progressRatio;
  final List<MedicationSchedule> schedules;

  const TodayMedicationInfo({
    this.patientHash = '',
    required this.medicationCount,
    required this.totalDoseCount,
    required this.completedDoseCount,
    required this.remainingDoseCount,
    required this.progressRatio,
    required this.schedules,
  });

  factory TodayMedicationInfo.fromJson(Map<String, dynamic> json) {
    final schedules = _readSchedules(json['schedules']);
    return TodayMedicationInfo(
      patientHash: _readString(json['patient_hash'] ?? json['patientHash']),
      medicationCount: _readInt(json['medication_count'] ?? schedules.length),
      totalDoseCount: _readInt(json['total_dose_count']),
      completedDoseCount: _readInt(json['completed_dose_count']),
      remainingDoseCount: _readInt(json['remaining_dose_count']),
      progressRatio: _readDouble(json['progress_ratio']),
      schedules: schedules,
    ).normalized();
  }

  factory TodayMedicationInfo.fromSchedules(
    List<MedicationSchedule> schedules, {
    String patientHash = '',
  }) {
    var totalDoseCount = 0;
    var completedDoseCount = 0;

    for (final schedule in schedules) {
      final scheduleSlotKeys = schedule.slotKeys;
      for (final slotKey in medicationScheduleSlotKeys) {
        if (!scheduleSlotKeys.contains(slotKey)) {
          continue;
        }
        totalDoseCount += 1;
        if (schedule.isSlotCompleted(slotKey)) {
          completedDoseCount += 1;
        }
      }
    }

    return TodayMedicationInfo(
      patientHash: patientHash,
      medicationCount: schedules.length,
      totalDoseCount: totalDoseCount,
      completedDoseCount: completedDoseCount,
      remainingDoseCount: totalDoseCount - completedDoseCount,
      progressRatio:
          totalDoseCount > 0 ? completedDoseCount / totalDoseCount : 0,
      schedules: List.unmodifiable(schedules),
    );
  }

  TodayMedicationInfo normalized() {
    final safeTotalDoseCount =
        totalDoseCount > 0 ? totalDoseCount : _derivedTotalDoseCount(schedules);
    final safeCompletedDoseCount = completedDoseCount >= 0
        ? completedDoseCount
        : _derivedCompletedDoseCount(schedules);
    final safeRemainingDoseCount = remainingDoseCount >= 0
        ? remainingDoseCount
        : safeTotalDoseCount - safeCompletedDoseCount;
    return TodayMedicationInfo(
      patientHash: patientHash,
      medicationCount: medicationCount > 0 ? medicationCount : schedules.length,
      totalDoseCount: safeTotalDoseCount,
      completedDoseCount: safeCompletedDoseCount,
      remainingDoseCount:
          safeRemainingDoseCount < 0 ? 0 : safeRemainingDoseCount,
      progressRatio: safeTotalDoseCount > 0
          ? safeCompletedDoseCount / safeTotalDoseCount
          : 0,
      schedules: List.unmodifiable(schedules),
    );
  }

  static int _derivedTotalDoseCount(List<MedicationSchedule> schedules) {
    return schedules.fold<int>(
      0,
      (total, schedule) => total + schedule.slotKeys.length,
    );
  }

  static int _derivedCompletedDoseCount(List<MedicationSchedule> schedules) {
    var completedCount = 0;
    for (final schedule in schedules) {
      for (final slotKey in schedule.slotKeys) {
        if (schedule.isSlotCompleted(slotKey)) {
          completedCount += 1;
        }
      }
    }
    return completedCount;
  }

  static List<MedicationSchedule> _readSchedules(dynamic rawItems) {
    if (rawItems is! List) {
      return const [];
    }

    return rawItems
        .whereType<Map>()
        .map(
          (item) => MedicationSchedule.fromScheduleJson(
            Map<String, dynamic>.from(item),
          ).getTodayMedicationSchedule(),
        )
        .toList(growable: false);
  }

  static String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final text = _readString(value);
    final match = RegExp(r'-?\d+').firstMatch(text);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(0) ?? '') ?? 0;
  }

  static double _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(_readString(value)) ?? 0;
  }
}
