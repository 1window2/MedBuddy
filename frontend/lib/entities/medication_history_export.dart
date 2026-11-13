// 파일명: medication_history_export.dart
// 역할: 선택 기간의 복약 기록을 내부 식별자 없이 다른 앱에서 읽을 수 있는 글로 만든다.
import 'medication_history_entity.dart';
import 'medication_schedule_entity.dart';

// Function Name: medicationHistoryRecordNotice
// Description: Selects the shared notice distinguishing self-reported records from proof of ingestion.
// Parameters: isEnglish (bool): English versus Korean.
// Returns: Localized notice that unrecorded does not mean not taken.
String medicationHistoryRecordNotice(bool isEnglish) => isEnglish
    ? 'Self-reported records are not proof of ingestion. Unrecorded does not mean not taken.'
    : '사용자가 입력한 기록이며 실제 복용을 증명하지 않습니다. 미기록은 미복용을 뜻하지 않습니다.';

// Function Name: medicationHistoryTimeZoneNotice
// Description: Selects the export's fixed Korea timezone notice.
// Parameters: isEnglish (bool): Display language.
// Returns: Localized UTC+09:00 label; this text does not inspect a custom configured dose offset.
String medicationHistoryTimeZoneNotice(bool isEnglish) => isEnglish
    ? 'Time zone: Korea (UTC+09:00)'
    : '시각 기준: 한국 시간(UTC+09:00)';

// 긴 기록을 임의로 생략하지 않고 기간을 줄이도록 안내하기 위한 공유 본문 상한이다.
const medicationHistoryShareTextLimit = 100000;

// 기록 공유 창을 열고 계정 삭제 때 남은 내보내기 파일을 지우는 Android 채널 이름이다.
const medicationHistoryExportChannel = 'com.medbuddy/data_export';

// Function Name: medicationHistoryShareText
// Description: Builds a chronological shareable report with status totals and sanitized single-line names/reasons, excluding internal identifiers.
// Parameters: snapshot (MedicationHistorySnapshot): Validated records and range; isEnglish (bool): Language.
// Returns: Plain text with date groups, optional taken times/skip reasons, empty-state text, and reporting/timezone notices.
String medicationHistoryShareText(
  MedicationHistorySnapshot snapshot, {
  required bool isEnglish,
}) {
  // 함수이름: tr
  // 함수역할: 공유 본문의 언어에 맞는 문구를 고른다.
  // 매개변수: ko/en (String): 한국어·영어 문구.
  // 반환값: isEnglish에 대응하는 문자열.
  String tr(String ko, String en) => isEnglish ? en : ko;
  // 함수이름: singleLine
  // 함수역할: 공유 내용의 제어 문자·줄 구분자를 공백으로 바꾸고 앞뒤 공백을 제거한다.
  // 매개변수: value (String): 약 이름 또는 사유.
  // 반환값: 한 줄로 정리한 문자열.
  String singleLine(String value) =>
      value.replaceAll(RegExp(r'[\x00-\x1f\x7f\u2028\u2029]+'), ' ').trim();
  final entries = [...snapshot.items];
  const slots = medicationScheduleSlotKeys;
  // 함수이름: slotOrder
  // 함수역할: 정기 시간대 다음에 필요시 기록이 오도록 정렬 순서를 정한다.
  // 매개변수: entry (MedicationHistoryEntry): 정렬할 기록.
  // 반환값: 정기 시간대 인덱스 또는 필요시는 마지막 순번; 알 수 없는 정기 슬롯은 -1.
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
    medicationHistoryRecordNotice(isEnglish),
    medicationHistoryTimeZoneNotice(isEnglish),
  ]);
  return lines.join('\n');
}
