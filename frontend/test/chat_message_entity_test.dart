// 파일명: chat_message_entity_test.dart
// 역할: 채팅의 필요시 복약·공유 이력·공유 장소 스냅샷을 해석하고 잘못된 첨부를 격리하는지 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';

// 윤년의 이틀과 복용·건너뜀·미기록 건수를 담은 정상 공유 이력 기준값.
const _history = <String, dynamic>{
  'start_date': '2024-02-28',
  'end_date': '2024-02-29',
  'taken_count': 4,
  'skipped_count': 0,
  'unrecorded_count': 2,
};

// 함수이름: _message
// 함수역할:
// - 정상 본문과 고정 메시지 시각에 주어진 공유 이력 원본을 넣어 첨부 해석을 시험한다.
// 매개변수:
// - history(Object?): 정상 맵뿐 아니라 누락·잘못된 타입도 그대로 넣을 첨부 값.
// 반환값:
// - Map<String, dynamic>: medication_history_share 종류의 메시지 응답.
Map<String, dynamic> _message(Object? history) => {
  'message_id': 7,
  'link_id': 17,
  'sender_hash': 'patient-a',
  'client_message_id': 'history-7',
  'body': 'Shared records',
  'message_kind': 'medication_history_share',
  'created_at': '2024-02-29T01:15:00Z',
  'context': {'history_context': history},
};

// 함수이름: main
// 함수역할:
// - 메시지 본문과 첨부 모델의 구형 호환·필드 검증·날짜 해석 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  // 함수이름: PRN chat context keeps its mode without scheduled slots
  // 함수역할:
  // - 필요시 문맥은 JSON 또는 시간대 교체 요청에 정기 시간대가 있어도 비우고 구형 정기 문맥은 기존 시간대를 유지하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
  test('PRN chat context keeps its mode without scheduled slots', () {
    final context = ChatMedicationContext.fromJson({
      'medication_id': 1,
      'medication_name': '필요시 시험약',
      'dosing_mode': 'as_needed',
      'schedule_slot_keys': ['morning'],
    });
    expect(context.isAsNeeded, isTrue);
    expect(context.scheduleSlotKeys, isEmpty);
    expect(context.withScheduleSlots(['evening']).isAsNeeded, isTrue);
    expect(context.withScheduleSlots(['evening']).scheduleSlotKeys, isEmpty);
    final legacy = ChatMedicationContext.fromJson({
      'medication_id': 2,
      'medication_name': '정기 시험약',
      'schedule_slot_keys': ['morning'],
    });
    expect(legacy.isAsNeeded, isFalse);
    expect(legacy.scheduleSlotKeys, ['morning']);
  });
  // 새 공유는 정기·필요시를 분리하고 이전 공유의 필요시 건수는 추정하지 않는다.
  // 함수이름: history parses separate chart counts and retains legacy snapshots
  // 함수역할:
  // - 구형 이력의 정기·필요시 분리 건수는 추정하지 않고 새 분리 건수는 보존하되 합계 불일치·음수·일부 필드 누락은 거부하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
  test('history parses separate chart counts and retains legacy snapshots', () {
    final legacy = ChatMedicationHistoryContext.fromJson(_history);
    expect(legacy.hasScheduledCounts, isFalse);
    expect(legacy.asNeededTakenCount, isNull);
    final raw = {
      ..._history,
      'scheduled_taken_count': 3,
      'scheduled_skipped_count': 0,
      'scheduled_unrecorded_count': 1,
      'as_needed_taken_count': 1,
    };
    final parsed = ChatMedicationHistoryContext.fromJson(raw);
    expect(parsed.scheduledTakenCount, 3);
    expect(parsed.scheduledUnrecordedCount, 1);
    expect(parsed.asNeededTakenCount, 1);
    for (final invalid in [
      {...raw, 'as_needed_taken_count': 3},
      {...raw, 'scheduled_skipped_count': 1},
      {...raw, 'scheduled_unrecorded_count': -1},
      {..._history, 'scheduled_taken_count': 3},
    ]) {
      expect(ChatMedicationHistoryContext.tryParse(invalid), isNull);
    }
  });
  for (final hospital in [true, false]) {
    // 함수이름: place snapshot survives parsing without using viewer time: $hospital
    // 함수역할:
    // - 병원·약국 공유의 원래 운영 상태와 오프셋 포함 시각을 UTC로 복원하고 운영 스냅샷이 없으면 null로 유지하는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 없음; 기대값과 다르면 테스트가 실패한다.
    test(
      'place snapshot survives parsing without using viewer time: $hospital',
      () {
        final json = <String, dynamic>{
          'pharmacy_id': 'test-place',
          'hospital_id': 'test-place',
          'name': 'Test place',
          'schedule_date': '2026-10-28',
          'operating_snapshot': {
            'status': 'closing_soon',
            'as_of': '2026-10-27T18:45:00+09:00',
            'closes_at': '2026-10-27T19:00:00+09:00',
          },
        };
        final ChatPlaceContext place = hospital
            ? ChatHospitalContext.fromJson(json)
            : ChatPharmacyContext.fromJson(json);
        expect(place.operatingSnapshot!.status, 'closing_soon');
        expect(
          place.operatingSnapshot!.asOf,
          DateTime.utc(2026, 10, 27, 9, 45),
        );
        expect(
          place.operatingSnapshot!.closesAt,
          DateTime.utc(2026, 10, 27, 10),
        );
        expect(
          ChatPharmacyContext.fromJson({
            ...json,
            'operating_snapshot': null,
          }).operatingSnapshot,
          isNull,
        );
      },
    );
  }
  // 함수이름: unverifiable snapshot time is not interpreted as current operating state
  // 함수역할:
  // - 누락·잘못된 형식·시간대 없는 기준 시각은 운영 스냅샷에서 제외하고 알 수 없는 상태 값은 unknown으로 해석하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
  test(
    'unverifiable snapshot time is not interpreted as current operating state',
    () {
      for (final time in [null, 'invalid', '2026-10-27T18:00:00']) {
        expect(
          ChatPlaceOperatingSnapshot.tryParse({
            'status': 'open',
            'as_of': time,
          }),
          isNull,
        );
      }
      expect(
        ChatPlaceOperatingSnapshot.tryParse({
          'status': 'unexpected',
          'as_of': '2026-10-27T09:00:00Z',
        })!.status,
        'unknown',
      );
    },
  );
  // 함수이름: history snapshot preserves strict dates counts and message time
  // 함수역할:
  // - 윤년 이력의 날짜·상태 건수·메시지 UTC 시각을 보존하며 읽음 표시 변경이 공유 스냅샷 객체를 교체하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
  test('history snapshot preserves strict dates counts and message time', () {
    final message = ChatMessage.fromJson(_message(_history));
    expect(message.messageKind, ChatMessageKind.medicationHistoryShare);
    expect(message.messageKind.wireName, 'medication_history_share');
    expect(message.createdAt, DateTime.utc(2024, 2, 29, 1, 15));
    final history = message.historyContext!;
    expect(history.startDate, DateTime.utc(2024, 2, 28));
    expect(history.endDate, DateTime.utc(2024, 2, 29));
    expect(history.takenCount, 4);
    expect(history.skippedCount, 0);
    expect(history.unrecordedCount, 2);
    expect(
      message.copyWith(readAt: DateTime.utc(2024, 3)).historyContext,
      same(history),
    );
  });

  for (final invalid in <Map<String, dynamic>>[
    {'start_date': '2023-02-29'},
    {'start_date': '2024-02-30'},
    {'end_date': '2024-13-01'},
    {'start_date': '2024-2-28'},
    {'start_date': ' 2024-02-28'},
    {'start_date': '2024-02-28T00:00:00Z'},
    {'start_date': '0000-01-01'},
    {'start_date': null},
    {'end_date': '2024-02-27'},
    {'end_date': '2024-03-30'},
    for (final key in ['taken_count', 'skipped_count', 'unrecorded_count'])
      for (final value in [-1, 2.5, 2.0, '2', null, true]) {key: value},
  ]) {
    // 함수이름: invalid history is rejected without losing message: $invalid
    // 함수역할:
    // - 잘못된 날짜·기간·건수의 직접 이력 해석은 FormatException이지만 메시지 해석은 해당 첨부만 버리고 본문을 남기는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 없음; 기대값과 다르면 테스트가 실패한다.
    test('invalid history is rejected without losing message: $invalid', () {
      final raw = {..._history, ...invalid};
      expect(
        () => ChatMedicationHistoryContext.fromJson(raw),
        throwsFormatException,
      );
      final message = ChatMessage.fromJson(_message(raw));
      expect(message.historyContext, isNull);
      expect(message.body, 'Shared records');
    });
  }

  // 함수이름: missing and non-object history falls back to the message
  // 함수역할:
  // - null·목록·문자열·숫자·빈 맵 첨부가 들어와도 메시지 본문은 표시하고 공유 이력은 null로 두는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
  test('missing and non-object history falls back to the message', () {
    for (final raw in [null, [], 'bad', 1, <String, dynamic>{}]) {
      final message = ChatMessage.fromJson(_message(raw));
      expect(message.historyContext, isNull);
      expect(message.body, 'Shared records');
    }
  });

  // 함수이름: snapshot does not change when the source map changes
  // 함수역할:
  // - 해석 뒤 원본 맵의 날짜와 건수를 바꿔도 이미 만들어진 이력 스냅샷 값은 유지되는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
  test('snapshot does not change when the source map changes', () {
    final raw = {..._history};
    final context = ChatMedicationHistoryContext.fromJson(raw);
    raw['taken_count'] = 999;
    raw['start_date'] = '2024-01-01';
    expect(context.takenCount, 4);
    expect(context.startDate, DateTime.utc(2024, 2, 28));
  });

  for (final hidden in [false, true]) {
    // 함수이름: hidden/deleted history snapshot is redacted: hidden=$hidden
    // 함수역할:
    // - 숨김 또는 전체 삭제 시 본문·이력 첨부를 지우고 일반 텍스트로 바꾸며 삭제 플래그를 되돌려도 민감 내용을 복원하지 않는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 없음; 기대값과 다르면 테스트가 실패한다.
    test('hidden/deleted history snapshot is redacted: hidden=$hidden', () {
      final message = ChatMessage.fromJson(_message(_history));
      final redacted = message.copyWith(
        hiddenForMe: hidden,
        deletedForEveryone: !hidden,
      );
      expect(redacted.historyContext, isNull);
      expect(redacted.body, isEmpty);
      expect(redacted.messageKind, ChatMessageKind.text);
      expect(
        redacted
            .copyWith(hiddenForMe: false, deletedForEveryone: false)
            .historyContext,
        isNull,
      );
      final serverRedacted = ChatMessage.fromJson({
        ..._message(_history),
        'hidden_for_me': hidden,
        'deleted_for_everyone': !hidden,
      });
      expect(serverRedacted.historyContext, isNull);
    });
  }
}
