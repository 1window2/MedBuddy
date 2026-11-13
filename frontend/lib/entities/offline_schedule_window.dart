// 파일명: offline_schedule_window.dart
// 역할: 서버가 검증한 최대 14일 기간에서 오프라인 복약 일정을 투영한다.
import 'medication_schedule_entity.dart';

// 서버가 확인한 기간 안에서만 계산한다. 날짜가 다른 복용 완료 상태는 사용하지 않는다.
// 클래스명: OfflineScheduleWindow
// 역할: 검증된 기간 안의 특정 날짜에 해당하는 복약 일정만 계산한다.
// 주요 책임: 기간·처방 시작일·복용 주기를 확인하고 다른 날짜의 완료 상태를 제거한다.
// 속성: maximumDays (int): 허용하는 기간의 최대 날짜 수.
class OfflineScheduleWindow {
  static const maximumDays = 14;

  // 함수이름: project
  // 함수역할: 기간과 약의 복용일을 검증하고 날짜에 맞는 일정의 완료 상태를 초기화한다.
  // 매개변수: window (Map<String, dynamic>): start/end/courses 데이터; day (String): 조회할 날짜.
  // 반환값: 유효하면 일정 목록(없으면 빈 목록), 날짜·기간·courses 형식이 부적절하면 null.
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
