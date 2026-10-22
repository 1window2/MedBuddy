import 'medication_schedule_entity.dart';

// 서버가 확인한 기간 안에서만 계산한다. 날짜가 다른 복용 완료 상태는 사용하지 않는다.
class OfflineScheduleWindow {
  static const maximumDays = 14;

  static List<MedicationSchedule>? project(
    Map<String, dynamic> window,
    String day,
  ) {
    final date = DateTime.tryParse(day);
    final start = DateTime.tryParse('${window['start']}');
    final end = DateTime.tryParse('${window['end']}');
    if (date == null ||
        start == null ||
        end == null ||
        end.isBefore(start) ||
        end.difference(start).inDays >= maximumDays ||
        date.isBefore(start) ||
        date.isAfter(end) ||
        window['courses'] is! List) {
      return null;
    }
    final courses = MedicationSchedule.fromScheduleJsonList(window['courses']);
    return courses
        .where((course) {
          final rawStart = course.prescriptionDate ?? course.createdDate;
          if (rawStart == null ||
              course.medicationID.isEmpty ||
              course.needsScheduleReview ||
              course.scheduleSlotKeys.isEmpty) {
            return false;
          }
          final courseStart = DateTime(
            rawStart.year,
            rawStart.month,
            rawStart.day,
          );
          final courseEnd = course.medicationTime > 0
              ? DateTime(
                  courseStart.year,
                  courseStart.month,
                  courseStart.day + course.medicationTime - 1,
                )
              : end;
          return !date.isBefore(courseStart) &&
              !date.isAfter(courseEnd) &&
              course.isDoseDay(date);
        })
        .map(
          (course) => course.copyWith(
            medicationStatus: false,
            slotStatuses: {for (final slot in course.slotKeys) slot: false},
          ),
        )
        .toList(growable: false);
  }
}
