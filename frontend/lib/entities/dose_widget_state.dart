// A home-screen projection of the account's own doses, never a caregiver write.
import 'dart:math';

import 'medication_alarm_entity.dart';
import 'medication_schedule_entity.dart';

const doseWidgetUtcOffset = int.fromEnvironment(
  'APPLICATION_UTC_OFFSET_MINUTES',
  defaultValue: 540,
);

DateTime doseWidgetLocalTime(DateTime now) =>
    now.toUtc().add(const Duration(minutes: doseWidgetUtcOffset));

String doseWidgetDay(DateTime now) =>
    doseWidgetLocalTime(now).toIso8601String().substring(0, 10);

String newWidgetActionToken() =>
    'widget_${List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

// Rebuilt from encrypted cache + ordered outbox in the same database transaction
// that accepts a widget tap. The native display is not the source of truth.
class DoseWidgetState {
  final Map<String, dynamic> data;
  DoseWidgetState(this.data);

  Map<String, dynamic> get view =>
      Map<String, dynamic>.from(data['view'] as Map);

  static List<MedicationSchedule> projectedSchedules(
    Map<String, dynamic>? cache,
    List<Map<String, dynamic>> operations,
    String day,
  ) {
    if (cache?['date'] != day) return [];
    return MedicationSchedule.fromScheduleJsonList(cache?['schedules']).map((
      s,
    ) {
      final statuses = {
        for (final slot in s.slotKeys) slot: s.isSlotCompleted(slot),
      };
      for (final op in operations) {
        if (op['schedule_date'] == day &&
            (op['medication_ids'] as List).contains(
              int.tryParse(s.medicationID),
            )) {
          statuses[op['slot_key'] as String] = op['completed'] == true;
        }
      }
      return s.copyWith(slotStatuses: statuses);
    }).toList();
  }

  // 함수이름: DoseWidgetState.build
  // 함수역할: 저장된 일정과 전송 대기 기록을 합쳐 시간순 첫 미완료 일정을 표시한다.
  // 매개변수: owner 계정, cache 일정, operations 대기 기록, previous 이전 토큰,
  //   now 기준 시각, configuration 표시 설정.
  // 반환값: 다음 일정 또는 오늘 기록 완료 상태. 이전 되돌리기 표시는 유지하지 않는다.
  factory DoseWidgetState.build({
    required String owner,
    required Map<String, dynamic>? cache,
    required List<Map<String, dynamic>> operations,
    required Map<String, dynamic> previous,
    required DateTime now,
    Map<String, dynamic>? configuration,
  }) {
    final config =
        configuration ??
        Map<String, dynamic>.from(previous['config'] as Map? ?? {});
    final english = config['language'] == 'en';
    String tr(String ko, String en) => english ? en : ko;
    final day = doseWidgetDay(now);
    final local = doseWidgetLocalTime(now);
    final midnight = DateTime.utc(
      local.year,
      local.month,
      local.day + 1,
    ).subtract(const Duration(minutes: doseWidgetUtcOffset));
    final current = cache?['date'] == day;
    final schedules = projectedSchedules(cache, operations, day);
    final blocked = operations.any((op) => op['state'] == 'blocked');
    final total = schedules.fold<int>(0, (n, s) => n + s.slotKeys.length);
    final done = schedules.fold<int>(
      0,
      (n, s) => n + s.slotKeys.where(s.isSlotCompleted).length,
    );
    final alarms = Map<String, dynamic>.from(config['alarms'] as Map? ?? {});
    String time(String slot) =>
        alarms[slot]?.toString() ?? MedicationAlarm.defaults(slot).timeLabel;
    int minute(String slot) {
      final parts = time(slot).split(':');
      return (int.tryParse(parts.first) ?? 0) * 60 +
          (int.tryParse(parts.last) ?? 0);
    }

    final pendingSlots =
        medicationScheduleSlotKeys
            .where(
              (slot) => schedules.any(
                (s) => s.slotKeys.contains(slot) && !s.isSlotCompleted(slot),
              ),
            )
            .toList()
          ..sort((a, b) => minute(a).compareTo(minute(b)));
    // 완료 기록은 로컬 전송 대기 상태에도 반영되어 다음 시간대로 바로 넘어간다.
    final slot = pendingSlots.firstOrNull;
    final medications = schedules
        .where((s) => s.slotKeys.contains(slot) && !s.isSlotCompleted(slot!))
        .toList();
    final ids =
        medications
            .map((s) => int.tryParse(s.medicationID))
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();
    final signature = '$day:$slot:${ids.join(',')}';
    final oldTake = Map<String, dynamic>.from(previous['take'] as Map? ?? {});
    final take = slot == null || ids.isEmpty || blocked
        ? null
        : <String, dynamic>{
            'token': oldTake['signature'] == signature
                ? oldTake['token']
                : newWidgetActionToken(),
            'signature': signature,
            'date': day,
            'slot': slot,
            'ids': ids,
            'names': medications
                .map((m) => m.displayNameForLanguage(english ? 'en' : 'ko'))
                .toList(),
          };
    final labels = english
        ? ['Morning', 'Lunch', 'Evening', 'Bedtime']
        : ['아침', '점심', '저녁', '취침 전'];
    String label(String key) => labels[medicationScheduleSlotKeys.indexOf(key)];
    final names = (take?['names'] as List? ?? []).cast<String>();
    final details = config['hide_names'] == true
        ? tr('복약 일정 ${names.length}개', '${names.length} scheduled medicines')
        : names.join(', ');
    final status = blocked
        ? tr('전송 확인 필요 · 앱에서 확인', 'Sync needs attention · Open app')
        : operations.isNotEmpty
        ? tr(
            '기기 저장 완료 · 전송 대기 ${operations.length}건',
            'Saved on device · ${operations.length} pending',
          )
        : tr('서버 저장 완료', 'Synced');
    final view = <String, dynamic>{
      'language': english ? 'en' : 'ko',
      'date': day,
      'title': tr('나의 복약 일정', 'My medication'),
      'heading': !current
          ? tr('오늘 일정을 불러와주세요', 'Refresh today\'s schedule')
          : slot != null
          ? '${label(slot)} ${time(slot)}'
          : total == 0
          ? tr('등록된 복약 일정이 없어요', 'No medication scheduled')
          : tr('오늘 복약 기록 완료', 'Today\'s doses recorded'),
      'details': details,
      'done': done,
      'total': total,
      'status': !current
          ? tr('새로고침 후 기록할 수 있어요', 'Refresh before recording')
          : status,
      'action': take != null ? 'take' : 'open',
      'token': take?['token'] ?? '',
      'slot': slot ?? '',
      'button': take != null
          ? tr('복용했어요', 'Taken')
          : tr('일정 열기', 'Open schedule'),
      'expires': midnight.millisecondsSinceEpoch,
      'overdue': slot != null && minute(slot) < local.hour * 60 + local.minute,
    };
    return DoseWidgetState({
      'owner': owner,
      'config': config,
      'take': take,
      'view': view,
    });
  }
}
