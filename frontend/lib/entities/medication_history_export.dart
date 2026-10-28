// 파일명: medication_history_export.dart
// 역할: 선택 기간의 요약과 개인정보 식별자를 제외한 안전한 CSV를 만든다.
import 'medication_history_entity.dart';

// 긴 기록을 임의로 생략하지 않고 기간을 줄이도록 안내하기 위한 공유 본문 상한이다.
const medicationHistoryShareTextLimit = 100000;

// 함수역할: 내부 식별자 없이 날짜별 복약 기록을 다른 앱에서 읽을 수 있는 문장으로 만든다.
String medicationHistoryShareText(
  MedicationHistorySnapshot snapshot, {
  required bool isEnglish,
}) {
  String tr(String ko, String en) => isEnglish ? en : ko;
  String singleLine(String value) =>
      value.replaceAll(RegExp(r'[\x00-\x1f\x7f\u2028\u2029]+'), ' ').trim();
  final entries = [...snapshot.items];
  const slots = ['morning', 'lunch', 'evening', 'bedtime'];
  int slotOrder(MedicationHistoryEntry entry) =>
      entry.isAsNeeded ? slots.length : slots.indexOf(entry.slotKey);
  entries.sort((a, b) {
    final date = a.scheduleDate.compareTo(b.scheduleDate);
    if (date != 0) return date;
    final slot = slotOrder(a).compareTo(slotOrder(b));
    if (slot != 0) return slot;
    final name = a.itemName.compareTo(b.itemName);
    if (name != 0) return name;
    final aTime = a.actualTakenAt ?? a.recordedAt;
    final bTime = b.actualTakenAt ?? b.recordedAt;
    if (aTime == null || bTime == null) {
      return aTime == bTime
          ? 0
          : aTime == null
          ? 1
          : -1;
    }
    return aTime.compareTo(bTime);
  });
  final lines = <String>[
    tr('MedBuddy 복약 기록', 'MedBuddy medication history'),
    '${tr('기간', 'Period')}: ${snapshot.range.label}',
  ];
  if (entries.isEmpty) {
    lines.addAll([
      '',
      tr('이 기간에 표시할 복약 기록이 없습니다.', 'No medication records for this period.'),
    ]);
  } else {
    lines.add(
      MedicationHistoryStatus.values
          .map(
            (status) =>
                '${status.label(isEnglish)} ${snapshot.count(status)}${isEnglish ? '' : '건'}',
          )
          .join(' · '),
    );
    String? previousDate;
    for (final entry in entries) {
      final date = MedicationHistoryDates.format(entry.scheduleDate);
      if (date != previousDate) {
        lines.addAll(['', date]);
        previousDate = date;
      }
      lines.add(
        '- ${entry.slotLabel(isEnglish)} · ${singleLine(entry.itemName)}: ${entry.status.label(isEnglish)}',
      );
      if (entry.status == MedicationHistoryStatus.taken) {
        lines.add(
          entry.actualTakenAt == null
              ? tr('  복용 시각은 입력하지 않았습니다.', '  Taken time was not entered.')
              : '  ${tr('복용 시각', 'Taken at')}: ${MedicationHistoryDates.timestamp(entry.actualTakenAt)}',
        );
      }
      if (entry.status == MedicationHistoryStatus.skipped &&
          entry.reason.trim().isNotEmpty) {
        lines.add(
          '  ${tr('건너뛴 이유', 'Skip reason')}: ${singleLine(entry.reason)}',
        );
      }
    }
  }
  lines.addAll([
    '',
    tr(
      '사용자가 입력한 기록입니다. 미기록은 미복용을 뜻하지 않습니다.',
      'Self-reported records, not proof of ingestion. Unrecorded does not mean not taken.',
    ),
    tr('시각 기준: 한국 시간(UTC+09:00)', 'Time zone: Korea (UTC+09:00)'),
  ]);
  return lines.join('\n');
}

// 사용자 입력이 CSV 수식으로 실행되지 않도록 모든 셀을 인용하고 수식 접두사를 무력화한다.
// 함수역할: 셀의 수식·따옴표·구분자를 처리한 CSV 문자열을 반환한다.
String medicationHistoryCsvCell(String value) {
  var safe = value.replaceAll('\u0000', '');
  // 시각이 없는 칸의 '-' 하나는 수식이 될 수 없으므로 그대로 둔다(엑셀에 "'-"로 보이지 않게).
  if ((safe != '-' && RegExp(r'^\s*[=+@-]').hasMatch(safe)) ||
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
    // 필요시 복용에는 예정일이 없어 기록한 날을 같은 열에 적는다. 내부 기록 버전은 내보내지 않는다.
    [
      tr('날짜 (필요시는 기록일)', 'Date (record date for as-needed)'),
      tr('약 이름', 'Medication'),
      tr('시간대', 'Dose slot'),
      tr('상태', 'Status'),
      tr('실제 복용 시각', 'Actual taken time'),
      tr('기록 시각', 'Recorded time'),
      tr('건너뛴 이유', 'Skip reason'),
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
