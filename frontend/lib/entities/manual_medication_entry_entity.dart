import 'medication_schedule_entity.dart';

// 파일명: manual_medication_entry_entity.dart
// 역할: 사용자가 직접 입력한 약 이름과 복용 일정을 하나의 값 객체로 보관한다.

// 클래스명: ManualMedicationEntry
// 역할: 직접 등록 화면의 입력값을 기존 복약 일정 저장 형식으로 변환한다.
// 주요 책임:
// - 복용 시작일과 종료일을 총 복용 일수로 계산한다.
// - 1회 복용량과 단위를 화면 및 서버가 공유하는 문자열로 만든다.
// - 선택한 시간대를 MedicationSchedule로 변환해 기존 저장 흐름을 재사용한다.
class ManualMedicationEntry {
  final String medicationName;
  final String dosageAmount;
  final String dosageUnit;
  final DateTime startDate;
  final DateTime endDate;
  final List<String> scheduleSlotKeys;
  final String localImagePath;

  const ManualMedicationEntry({
    required this.medicationName,
    required this.dosageAmount,
    required this.dosageUnit,
    required this.startDate,
    required this.endDate,
    required this.scheduleSlotKeys,
    this.localImagePath = '',
  });

  int get totalDays {
    final normalizedStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);
    return normalizedEnd.difference(normalizedStart).inDays + 1;
  }

  String get dosage {
    final amount = dosageAmount.trim();
    final unit = dosageUnit.trim();
    return '$amount$unit';
  }

  MedicationSchedule toMedicationSchedule() {
    final slots = List<String>.of(scheduleSlotKeys, growable: false);
    return MedicationSchedule(
      prescriptionDate: DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      ),
      medicationName: medicationName.trim(),
      dosage: dosage,
      intakeTime: '${slots.length}회',
      medicationTime: totalDays,
      scheduleSlotKeys: slots,
      rawMedicationName: medicationName.trim(),
      nameConfidence: 1,
      nameCorrectionSource: 'manual_entry',
    );
  }
}
