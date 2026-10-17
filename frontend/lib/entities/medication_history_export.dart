// 파일명: medication_history_export.dart
// 역할: 선택 기간의 요약과 개인정보 식별자를 제외한 안전한 CSV를 만든다.
import 'medication_history_entity.dart';

// 사용자 입력이 CSV 수식으로 실행되지 않도록 모든 셀을 인용하고 수식 접두사를 무력화한다.
// 함수역할: 셀의 수식·따옴표·구분자를 처리한 CSV 문자열을 반환한다.
String medicationHistoryCsvCell(String value) {
  var safe = value.replaceAll('\u0000', '');
  if (RegExp(r'^\s*[=+@-]').hasMatch(safe) ||
      safe.startsWith('\t') ||
      safe.startsWith('\r') ||
      safe.startsWith('\n')) {
    safe = "'$safe";
  }
  return '"${safe.replaceAll('"', '""')}"';
}

// 함수역할: 스냅샷의 기간·상태별 개수·자가 기록 한계를 선택한 언어로 요약한다.
String medicationHistorySummary(
  MedicationHistorySnapshot snapshot, {
  required bool isEnglish,
}) {
  // 함수역할: 내보내기 언어에 맞는 한국어 또는 영어 문구를 선택한다.
  String tr(String ko, String en) => isEnglish ? en : ko;
  final counts = MedicationHistoryStatus.values
      .map((status) => '${status.label(isEnglish)} ${snapshot.count(status)}')
      .join(' · ');
  return '${tr('복약 기록', 'Medication history')}\n${snapshot.range.label}\n$counts\n'
      '${tr('사용자가 입력한 기록이며 실제 복용을 증명하지 않습니다. 미기록은 미복용을 뜻하지 않습니다.', 'Self-reported records are not proof of ingestion. Unrecorded does not mean not taken.')}\n'
      '${tr('시각 기준: 한국 시간(UTC+09:00)', 'Time zone: Korea (UTC+09:00)')}';
}

// 함수역할: 기간별 기록과 해당 기록에 등장하는 약 목록만 BOM이 있는 UTF-8 CSV 본문으로 만든다.
String medicationHistoryCsv(
  MedicationHistorySnapshot snapshot, {
  required bool isEnglish,
}) {
  // 함수역할: 내보내기 언어에 맞는 열 제목과 상태 문구를 선택한다.
  String tr(String ko, String en) => isEnglish ? en : ko;
  final periodMedicationIds = snapshot.items
      .map((item) => item.medicationId)
      .toSet();
  final rows = <List<String>>[
    ['MedBuddy', tr('복약 기록', 'Medication history')],
    [tr('조회 기간', 'Selected period'), snapshot.range.label],
    [
      tr('기록 기준', 'Record source'),
      tr('사용자 입력, 실제 복용 증명 아님', 'Self-reported, not proof of ingestion'),
    ],
    // 아래 표의 복용 '시간대' 열과 구분되도록 시각 기준 행은 '표준시'로 적는다.
    [tr('표준시', 'Time zone'), 'UTC+09:00'],
    for (final status in MedicationHistoryStatus.values)
      [status.label(isEnglish), '${snapshot.count(status)}'],
    [],
    [
      tr('예정일', 'Scheduled date'),
      tr('약 이름', 'Medication'),
      tr('시간대', 'Dose slot'),
      tr('상태', 'Status'),
      tr('실제 복용 시각', 'Actual taken time'),
      tr('기록 시각', 'Recorded time'),
      tr('건너뛴 이유', 'Skip reason'),
      tr('기록 버전', 'Revision'),
    ],
    for (final item in snapshot.items)
      [
        MedicationHistoryDates.format(item.scheduleDate),
        item.itemName,
        item.slotLabel(isEnglish),
        item.status.label(isEnglish),
        MedicationHistoryDates.timestamp(item.actualTakenAt),
        MedicationHistoryDates.timestamp(item.recordedAt),
        item.reason,
        '${item.revision}',
      ],
    [],
    [tr('조회 기간의 약 목록', 'Medications in the selected period')],
    [
      tr('약 이름', 'Medication'),
      tr('1회 복용량', 'Dose'),
      tr('복용 주기', 'Frequency'),
      tr('복용 방식', 'Dosing mode'),
      tr('적용 시작일', 'Effective start date'),
      tr('중단일 (이날부터)', 'Stopped from'),
      tr('처방 기간', 'Course duration'),
      // 정보 수정과 새 처방 교체 모두 다음 항목으로 이어지므로 '변경'으로 적는다.
      tr('변경된 처방', 'Changed course'),
    ],
    for (final item in snapshot.medications.where(
      (item) => periodMedicationIds.contains(item.id),
    ))
      [
        item.itemName,
        item.dosage,
        item.frequency,
        item.dosingMode == 'as_needed'
            ? tr('필요시 복용', 'As needed')
            : item.dosingMode == 'scheduled'
            ? tr('정기 복용', 'Scheduled')
            : tr('복용법 확인 필요', 'Directions need review'),
        item.startDate == null
            ? ''
            : MedicationHistoryDates.format(item.startDate!),
        item.stoppedOn == null
            ? ''
            : MedicationHistoryDates.format(item.stoppedOn!),
        item.totalDays,
        item.superseded ? tr('예', 'Yes') : tr('아니오', 'No'),
      ],
  ];
  return '\uFEFF${rows.map((row) => row.map(medicationHistoryCsvCell).join(',')).join('\r\n')}\r\n';
}
