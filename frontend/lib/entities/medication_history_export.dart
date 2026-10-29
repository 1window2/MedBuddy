// 파일명: medication_history_export.dart
// 역할: 선택 기간의 복약 기록을 내부 식별자 없이 다른 앱에서 읽을 수 있는 글로 만든다.
import 'medication_history_entity.dart';
import 'medication_schedule_entity.dart';

// 함수역할: 기록 화면 안내와 공유 본문이 함께 쓰는 자가 기록 한계 문구를 고른다.
String medicationHistoryRecordNotice(bool isEnglish) => isEnglish
    ? 'Self-reported records are not proof of ingestion. Unrecorded does not mean not taken.'
    : '사용자가 입력한 기록이며 실제 복용을 증명하지 않습니다. 미기록은 미복용을 뜻하지 않습니다.';

// 함수역할: 기록 시각이 한국 시간 기준임을 알리는 문구를 고른다.
String medicationHistoryTimeZoneNotice(bool isEnglish) => isEnglish
    ? 'Time zone: Korea (UTC+09:00)'
    : '시각 기준: 한국 시간(UTC+09:00)';

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
  const slots = medicationScheduleSlotKeys;
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
