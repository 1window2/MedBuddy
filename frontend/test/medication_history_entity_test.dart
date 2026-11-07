// 파일명: medication_history_entity_test.dart
// 역할: 이력 날짜·상태·실제 시각을 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_history_entity.dart';

import 'medication_history_fixtures.dart';

// 함수역할: 경계 날짜와 내보내기 계약에 대한 독립 회귀 테스트를 등록한다.
// 함수이름: main
// 함수역할:
// - 이력 날짜·기간·서버 허용 상태·복용 시각과 변경 요청의 직렬화 경계를 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록한 테스트는 프레임워크가 실행한다.
void main() {
  // 윤년·날짜 넘침을 느슨하게 보정하지 않고 명확히 거부한다.
  // 함수이름: 엄격한 달력 날짜 해석
  // 함수역할:
  // - 윤년 날짜는 허용하되 존재하지 않는 날짜·시각 포함 문자열·다른 날짜 형식·빈 입력은 FormatException으로 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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
  // 함수이름: 한국 날짜와 UTC 순간 변환
  // 함수역할:
  // - 한국 자정 경계의 오늘 날짜·표시 시각·입력 시각 및 시간대 유무 ISO 문자열이 동일한 UTC 순간을 유지하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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
  // 함수이름: 포함 날짜 범위 검증
  // 함수역할:
  // - 최대 31일과 최근 90일의 양 끝은 허용하고 기간 초과·조회 창 밖·미래·역순 범위는 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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
  // 함수이름: 손상 이력 스냅샷 거부
  // 함수역할:
  // - 정상 미기록 건수와 함께 알 수 없는 상태·시간대, 음수 버전, 잘못된 약 ID, 범위 밖 날짜와 중복 항목을 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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
  // 함수이름: 서버의 필요시 기록 가능 상태
  // 함수역할:
  // - 서버의 true/false를 필요시 약에 그대로 반영하고 정기 약은 기록 가능으로 바꾸지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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
  // 함수이름: 기록 가능 상태의 기본값
  // 함수역할:
  // - 직접 생성하거나 구형 서버의 허용 필드가 빠진 필요시 약은 처방 날짜가 있어도 기록을 허용하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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
  // 함수이름: 불리언이 아닌 기록 허용 값
  // 함수역할:
  // - 문자열·숫자·null·배열·맵을 true로 강제 변환하지 않고 필요시 기록을 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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
  // 함수이름: 예정일과 실제 복용 시각 분리
  // 함수역할:
  // - 늦은 복용도 원래 예정일을 유지하며 실제 시각은 UTC로 전송하고 서버 기록 시각은 생략하되 미래 또는 누락 실제 시각은 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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
  // 함수이름: 필요시 이벤트 시간대 키
  // 함수역할:
  // - UUID 형식 이벤트 키를 필요시 약에서만 허용하며 서로 다른 이벤트는 같은 약이라도 독립 이력 두 건으로 유지하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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

  // Ordering is verified on parsed items here; export formatting is covered separately.
  // Function Name: same-day as-needed ordering
  // Description:
  // - Orders taken events chronologically rather than by UUID and places the event without an actual intake time last.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('same-day PRN doses are ordered by the time they were taken', () {
    // Function Name: dose
    // Description:
    // - Builds an as-needed event whose completion state follows the presence of an actual intake time.
    // Parameters:
    // - uuid (String): Suffix of the event slot key.
    // - taken (String?): Actual intake timestamp; null marks the event unrecorded.
    // - recorded (String?): Server-recorded timestamp; defaults to taken.
    // Returns:
    // - Map<String, dynamic>: A revision-1 event on the fixed fixture day.
    Map<String, dynamic> dose(String uuid, String? taken, {String? recorded}) => {
      ...historyTestEntry(
        id: 2,
        date: '2026-10-17',
        slot: 'as_needed:$uuid',
        mode: 'as_needed',
        status: taken == null ? 'unrecorded' : 'taken',
        revision: 1,
      ),
      'actual_taken_at': taken,
      'recorded_at': recorded ?? taken,
    };
    final items = MedicationHistorySnapshot.fromJson(
      historyTestBody(
        items: [
          dose('ffffffff-1234-4234-8234-123456789012', '2026-10-17T00:30:00Z'),
          dose('00000000-1234-4234-8234-123456789012', '2026-10-17T05:10:00Z'),
          dose('88888888-1234-4234-8234-123456789012', null),
          dose('77777777-1234-4234-8234-123456789012', '2026-10-17T03:00:00Z'),
        ],
      ),
    ).items.where((item) => item.isAsNeeded).toList();
    expect(items.map((item) => item.slotKey.substring(10, 18)), [
      'ffffffff',
      '77777777',
      '00000000',
      '88888888',
    ]);
  });

  // 건너뜀만 이유를 가지며 그 외 상태에 실제 복용 시각이 남지 않는다.
  // 함수이름: 상태별 시각과 사유 검증
  // 함수역할:
  // - 건너뜀은 실제 복용 시각 없이 직렬화하고 201자 사유 또는 미기록 상태의 실제 복용 시각은 FormatException으로 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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
}
