import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';

const _history = <String, dynamic>{
  'start_date': '2024-02-28',
  'end_date': '2024-02-29',
  'taken_count': 4,
  'skipped_count': 0,
  'unrecorded_count': 2,
};

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

void main() {
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

  test('missing and non-object history falls back to the message', () {
    for (final raw in [null, [], 'bad', 1, <String, dynamic>{}]) {
      final message = ChatMessage.fromJson(_message(raw));
      expect(message.historyContext, isNull);
      expect(message.body, 'Shared records');
    }
  });

  test('snapshot does not change when the source map changes', () {
    final raw = {..._history};
    final context = ChatMedicationHistoryContext.fromJson(raw);
    raw['taken_count'] = 999;
    raw['start_date'] = '2024-01-01';
    expect(context.takenCount, 4);
    expect(context.startDate, DateTime.utc(2024, 2, 28));
  });

  for (final hidden in [false, true]) {
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
