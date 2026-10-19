// 파일명: medication_history_entity_test.dart
// 역할: 이력 날짜·상태·실제 시각 및 CSV 수식 방어를 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_history_entity.dart';
import 'package:medbuddy_frontend/entities/medication_history_export.dart';

import 'medication_history_fixtures.dart';

// 함수역할: 경계 날짜와 내보내기 계약에 대한 독립 회귀 테스트를 등록한다.
void main() {
  // 윤년·날짜 넘침을 느슨하게 보정하지 않고 명확히 거부한다.
  test('calendar parsing rejects rolled dates and timestamps', () {
    expect(
      MedicationHistoryDates.parse('2024-02-29'),
      DateTime.utc(2024, 2, 29),
    );
    for (final invalid in [
      '2026-02-29',
      '2026-13-01',
      '2026-10-17T00:00:00Z',
      '10/17/2026',
      '',
    ]) {
      expect(
        () => MedicationHistoryDates.parse(invalid),
        throwsFormatException,
      );
    }
  });

  // 기기 지역과 무관하게 한국 자정에서 조회 날짜가 전환되는지 확인한다.
  test('Korea date and timestamp preserve UTC instant across midnight', () {
    expect(
      MedicationHistoryDates.today(DateTime.utc(2026, 10, 16, 15)),
      DateTime.utc(2026, 10, 17),
    );
    expect(
      MedicationHistoryDates.timestamp(DateTime.utc(2026, 10, 16, 15, 30)),
      '2026-10-17 00:30',
    );
    expect(
      MedicationHistoryDates.instant(DateTime.utc(2026, 10, 17), 0, 30),
      DateTime.utc(2026, 10, 16, 15, 30),
    );
    expect(
      MedicationHistoryDates.parseTimestamp('2026-10-16T15:30:00'),
      DateTime.utc(2026, 10, 16, 15, 30),
    );
    expect(
      MedicationHistoryDates.parseTimestamp('2026-10-17T00:30:00+09:00'),
      DateTime.utc(2026, 10, 16, 15, 30),
    );
  });

  // 최근 90일과 31일 상한 모두 양 끝 날짜를 포함한다.
  test('range validates inclusive 31 days and 90 day window', () {
    final today = MedicationHistoryDates.today(historyTestNow);
    MedicationHistoryRange(
      today.subtract(const Duration(days: 30)),
      today,
    ).validate(historyTestNow);
    final first = today.subtract(const Duration(days: 89));
    MedicationHistoryRange(first, first).validate(historyTestNow);
    for (final range in [
      MedicationHistoryRange(today.subtract(const Duration(days: 31)), today),
      MedicationHistoryRange(first.subtract(const Duration(days: 1)), first),
      MedicationHistoryRange(today, today.add(const Duration(days: 1))),
      MedicationHistoryRange(today, today.subtract(const Duration(days: 1))),
    ]) {
      expect(() => range.validate(historyTestNow), throwsFormatException);
    }
  });

  // 잘못된 상태를 미기록으로 숨기거나 중복 복용을 이중 집계하지 않는다.
  test('snapshot rejects unknown status revision duplicates and dates', () {
    final body = historyTestBody();
    expect(
      MedicationHistorySnapshot.fromJson(
        body,
      ).count(MedicationHistoryStatus.unrecorded),
      1,
    );
    for (final item in [
      {...historyTestEntry(), 'status': 'unknown'},
      {...historyTestEntry(), 'revision': -1},
      {...historyTestEntry(), 'medication_id': 0},
      {...historyTestEntry(), 'slot_key': 'unknown'},
      historyTestEntry(date: '2026-10-18'),
    ]) {
      expect(
        () =>
            MedicationHistorySnapshot.fromJson(historyTestBody(items: [item])),
        throwsFormatException,
      );
    }
    expect(
      () => MedicationHistorySnapshot.fromJson(
        historyTestBody(items: [historyTestEntry(), historyTestEntry()]),
      ),
      throwsFormatException,
    );
  });

  // 기록 가능 여부는 앱의 날짜 추정 없이 서버가 명시한 참·거짓으로 보존한다.
  test('history medication parses server recording eligibility', () {
    for (final allowed in [true, false]) {
      final body = historyTestBody();
      (body['medications'] as List)[1]['can_record_as_needed'] = allowed;
      final snapshot = MedicationHistorySnapshot.fromJson(body);
      expect(snapshot.medications[1].canRecordAsNeeded, allowed);
      expect(snapshot.medications[0].canRecordAsNeeded, isFalse);
    }
  });

  // 이전 서버의 누락 값과 직접 생성한 약은 필요시 모드여도 기록을 허용하지 않는다.
  test('history medication recording eligibility defaults to false', () {
    const medication = MedicationHistoryMedication(
      id: 2,
      itemName: '테스트 필요시약',
      dosingMode: 'as_needed',
    );
    expect(medication.canRecordAsNeeded, isFalse);
    final parsed = MedicationHistoryMedication.fromJson({
      'id': 2,
      'item_name': '테스트 필요시약',
      'dosing_mode': 'as_needed',
      'prescription_date': '2026-10-01',
      'total_days': '90',
    });
    expect(parsed.canRecordAsNeeded, isFalse);
  });

  // 참처럼 보이는 문자열·숫자·구조체를 불리언 참으로 변환하지 않는다.
  test(
    'history medication recording eligibility fails closed on non-booleans',
    () {
      for (final value in <Object?>[
        null,
        'true',
        'false',
        '1',
        '',
        1,
        0,
        -1,
        1.0,
        <Object?>[true],
        <String, Object?>{'allowed': true},
      ]) {
        final medication = MedicationHistoryMedication.fromJson({
          'id': 2,
          'item_name': '테스트 필요시약',
          'dosing_mode': 'as_needed',
          'can_record_as_needed': value,
        });
        expect(medication.canRecordAsNeeded, isFalse, reason: '$value');
      }
    },
  );

  // 다음 날 복용해도 예정일을 옮기지 않으며 미래 실제 복용 시각은 거부한다.
  test('late weekly dose has distinct scheduled actual and recorded times', () {
    final entry = MedicationHistoryEntry.fromJson(historyTestEntry());
    final change = MedicationHistoryChange(
      entry: entry,
      status: MedicationHistoryStatus.taken,
      operationId: '12345678-1234-4234-8234-123456789012',
      actualTakenAt: historyTestNow.subtract(const Duration(minutes: 5)),
    );
    change.validate(historyTestNow);
    expect(
      MedicationHistoryDates.format(change.entry.scheduleDate),
      '2026-10-16',
    );
    expect(
      MedicationHistoryDates.timestamp(change.actualTakenAt),
      '2026-10-17 14:55',
    );
    expect(
      change.toJson('patient')['actual_taken_at'],
      '2026-10-17T05:55:00.000Z',
    );
    expect(change.toJson('patient').containsKey('recorded_at'), isFalse);
    expect(
      () => MedicationHistoryChange(
        entry: entry,
        status: MedicationHistoryStatus.taken,
        operationId: change.operationId,
        actualTakenAt: historyTestNow.add(const Duration(minutes: 1)),
      ).validate(historyTestNow),
      throwsFormatException,
    );
    expect(
      () => MedicationHistoryChange(
        entry: entry,
        status: MedicationHistoryStatus.taken,
        operationId: change.operationId,
      ).validate(historyTestNow),
      throwsFormatException,
    );
  });

  // 동적 필요시 기록 키는 정기 복용 약에 허용하지 않는다.
  test('PRN event keys are unique slots only for as-needed medication', () {
    const slot = 'as_needed:12345678-1234-4234-8234-123456789012';
    expect(MedicationHistoryEntry.validSlot(slot, 'as_needed'), isTrue);
    expect(MedicationHistoryEntry.validSlot(slot, 'scheduled'), isFalse);
    expect(
      MedicationHistoryEntry.validSlot('as_needed:garbage', 'as_needed'),
      isFalse,
    );
    final first = historyTestEntry(id: 2, slot: slot, mode: 'as_needed');
    final second = {
      ...first,
      'slot_key': 'as_needed:12345678-1234-4234-8234-123456789013',
    };
    expect(
      MedicationHistorySnapshot.fromJson(
        historyTestBody(items: [first, second]),
      ).items,
      hasLength(2),
    );
  });

  // 건너뜀만 이유를 가지며 그 외 상태에 실제 복용 시각이 남지 않는다.
  test('reason length and mutually exclusive status fields are validated', () {
    final entry = MedicationHistoryEntry.fromJson(historyTestEntry());
    const operation = '12345678-1234-4234-8234-123456789012';
    final skipped = MedicationHistoryChange(
      entry: entry,
      status: MedicationHistoryStatus.skipped,
      operationId: operation,
      reason: '약을 두고 나옴',
    );
    skipped.validate(historyTestNow);
    expect(skipped.toJson('patient')['actual_taken_at'], isNull);
    expect(
      () => MedicationHistoryChange(
        entry: entry,
        status: MedicationHistoryStatus.skipped,
        operationId: operation,
        reason: '가' * 201,
      ).validate(historyTestNow),
      throwsFormatException,
    );
    expect(
      () => MedicationHistoryChange(
        entry: entry,
        status: MedicationHistoryStatus.unrecorded,
        operationId: operation,
        actualTakenAt: historyTestNow,
      ).validate(historyTestNow),
      throwsFormatException,
    );
  });

  // 스프레드시트 수식, 줄바꿈, 따옴표가 포함된 사용자 입력도 안전한 단일 셀로 유지한다.
  test('CSV cells quote delimiters and neutralize formulas', () {
    expect(medicationHistoryCsvCell('약, "이름"\n둘째 줄'), '"약, ""이름""\n둘째 줄"');
    for (final value in [
      '=HYPERLINK("x")',
      '+1',
      '-1',
      '@SUM(A1)',
      '  =1',
      '\t=1',
      '\rhello',
      '\nhello',
    ]) {
      expect(medicationHistoryCsvCell(value).startsWith('"\''), isTrue);
    }
    expect(medicationHistoryCsvCell('일반 약'), '"일반 약"');
  });

  // 요약은 자가 기록임을 밝히며 내보내기에 내부 환자 식별자를 노출하지 않는다.
  test(
    'export includes summary timings medicines without scope identifiers',
    () {
      final body = historyTestBody(
        items: [
          {
            ...historyTestEntry(status: 'taken'),
            'actual_taken_at': '2026-10-17T05:55:00Z',
            'recorded_at': '2026-10-17T06:00:00Z',
            'patient_hash': 'private-scope',
          },
        ],
      );
      final snapshot = MedicationHistorySnapshot.fromJson(body);
      final csv = medicationHistoryCsv(snapshot, isEnglish: false);
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv, contains('2026-10-17 14:55'));
      expect(csv, contains('2026-10-17 15:00'));
      expect(csv, contains('테스트 주간약'));
      expect(csv, isNot(contains('테스트 필요시약')));
      expect(csv, isNot(contains('private-scope')));
      // 시각 기준 행과 복용 시간대 열의 제목이 겹치지 않는다.
      expect(csv, contains('"표준시","UTC+09:00"'));
      // 시각이 없는 칸은 수식 방지 접두사 없이 '-'로 남는다.
      expect(csv, isNot(contains('"\'-"')));
      expect(medicationHistoryCsvCell('-'), '"-"');
      expect(medicationHistoryCsvCell('-1+2'), '"\'-1+2"');
      expect('"시간대"'.allMatches(csv).length, 1);
      expect(
        medicationHistorySummary(snapshot, isEnglish: true),
        contains('not proof of ingestion'),
      );
      expect(
        medicationHistorySummary(snapshot, isEnglish: false),
        contains('미기록은 미복용을 뜻하지 않습니다'),
      );
    },
  );

  // 약 목록 전체가 반환되어도 조회 기간 밖 처방과 기록 없는 필요시 약은 내보내지 않는다.
  test('CSV medication list excludes out-of-period and no-event medicines', () {
    final body = historyTestBody();
    (body['medications'] as List).addAll(<Map<String, Object>>[
      {
        'id': 3,
        'item_name': '기간 이전 처방약',
        'regimen_effective_from': '2026-09-01',
        'stopped_on': '2026-10-01',
      },
      {
        'id': 4,
        'item_name': '기간 이후 처방약',
        'regimen_effective_from': '2026-10-18',
      },
    ]);
    final snapshot = MedicationHistorySnapshot.fromJson(body);
    for (final isEnglish in [false, true]) {
      final csv = medicationHistoryCsv(snapshot, isEnglish: isEnglish);
      expect(
        csv,
        contains(
          isEnglish ? 'Medications in the selected period' : '조회 기간의 약 목록',
        ),
      );
      expect(csv, contains('"테스트 주간약","1정","주 1회"'));
      for (final excluded in ['테스트 필요시약', '기간 이전 처방약', '기간 이후 처방약']) {
        expect(csv, isNot(contains(excluded)));
      }
    }
    expect(snapshot.medications, hasLength(4));
  });

  // 빈 조회 기간을 내보낼 때 보관된 약 정보가 CSV에 섞이지 않는다.
  test('CSV without period events exports no medication details', () {
    final snapshot = MedicationHistorySnapshot.fromJson(
      historyTestBody(items: []),
    );
    for (final isEnglish in [false, true]) {
      final csv = medicationHistoryCsv(snapshot, isEnglish: isEnglish);
      expect(csv, isNot(contains('테스트 주간약')));
      expect(csv, isNot(contains('테스트 필요시약')));
      expect(csv, isNot(contains('1정')));
    }
  });
}
