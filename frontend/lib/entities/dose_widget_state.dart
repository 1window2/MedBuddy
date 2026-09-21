// Home-screen projections keep caregiver viewing separate from dose writes.
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
  // 함수역할: 저장된 일정과 전송 대기 기록을 합쳐 시간대별 조회·복용·취소 상태를 만든다.
  // 매개변수: owner 계정, cache 일정, operations 대기 기록, previous 이전 토큰,
  //   now 기준 시각, configuration 표시 설정.
  // 반환값: 오늘 날짜와 시간대 페이지. 복용은 미완료 약, 취소는 완료 시간대의 약에 연결한다.
  factory DoseWidgetState.build({
    required String owner,
    required Map<String, dynamic>? cache,
    required List<Map<String, dynamic>> operations,
    required Map<String, dynamic> previous,
    required DateTime now,
    Map<String, dynamic>? configuration,
    bool readOnly = false,
  }) {
    final config =
        configuration ??
        Map<String, dynamic>.from(previous['config'] as Map? ?? {});
    if (config['source'] == 'patients' && !readOnly) {
      return _patients(owner, previous, now, config);
    }
    final oldView = previous['view'] as Map? ?? {};
    final english = config['language'] == 'en';
    String tr(String ko, String en) => english ? en : ko;
    final day = doseWidgetDay(now);
    final local = doseWidgetLocalTime(now);
    final weekday = (english
        ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : ['월', '화', '수', '목', '금', '토', '일'])[local.weekday - 1];
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
      if (readOnly) return medicationScheduleSlotKeys.indexOf(slot);
      final parts = time(slot).split(':');
      return (int.tryParse(parts.first) ?? 0) * 60 +
          (int.tryParse(parts.last) ?? 0);
    }

    final slots = medicationScheduleSlotKeys
        .where((slot) => schedules.any((s) => s.slotKeys.contains(slot)))
        .toList();
    final pendingSlots =
        slots
            .where(
              (slot) => schedules.any(
                (s) => s.slotKeys.contains(slot) && !s.isSlotCompleted(slot),
              ),
            )
            .toList()
          ..sort((a, b) {
            final order = minute(a).compareTo(minute(b));
            return order != 0
                ? order
                : medicationScheduleSlotKeys
                      .indexOf(a)
                      .compareTo(medicationScheduleSlotKeys.indexOf(b));
          });
    // 완료 기록은 로컬 전송 대기 상태에도 반영되어 다음 시간대로 바로 넘어간다.
    final slot = pendingSlots.firstOrNull;
    final labels = english
        ? ['Morning', 'Lunch', 'Evening', 'Bedtime']
        : ['아침', '점심', '저녁', '취침 전'];
    String label(String key) => labels[medicationScheduleSlotKeys.indexOf(key)];
    final takes = <String, Map<String, dynamic>>{};
    final cancels = <String, Map<String, dynamic>>{};
    final pages = <Map<String, dynamic>>[];
    final oldTakes = previous['takes'] as Map? ?? {};
    final oldCancels = previous['cancels'] as Map? ?? {};
    final legacyTake = previous['take'] as Map?;
    for (final pageSlot in slots) {
      final all = schedules
          .where((s) => s.slotKeys.contains(pageSlot))
          .toList();
      final remaining = all.where((s) => !s.isSlotCompleted(pageSlot)).toList();
      final completed = remaining.isEmpty;
      final targets = completed ? all : remaining;
      final ids =
          targets
              .map((s) => int.tryParse(s.medicationID))
              .whereType<int>()
              .toSet()
              .toList()
            ..sort();
      final signature =
          '${completed ? 'cancel:' : ''}$day:$pageSlot:${ids.join(',')}';
      final oldAction = completed
          ? oldCancels[pageSlot] as Map?
          : oldTakes[pageSlot] as Map? ??
                (legacyTake?['slot'] == pageSlot ? legacyTake : null);
      if (!readOnly && ids.isNotEmpty && !blocked) {
        (completed ? cancels : takes)[pageSlot] = {
          'token': oldAction?['signature'] == signature
              ? oldAction!['token']
              : newWidgetActionToken(),
          'signature': signature,
          'date': day,
          'slot': pageSlot,
          'ids': ids,
          'names': targets
              .map((m) => m.displayNameForLanguage(english ? 'en' : 'ko'))
              .toList(),
        };
      }
      final pageDone = all.length - remaining.length;
      final pageAction = completed ? cancels[pageSlot] : takes[pageSlot];
      pages.add({
        'slot': pageSlot,
        'label': label(pageSlot),
        'heading': readOnly
            ? label(pageSlot)
            : '${label(pageSlot)} ${time(pageSlot)}',
        'details': config['hide_names'] == true
            ? tr(
                '복용 완료 $pageDone개 · 미복용 ${remaining.length}개',
                '$pageDone taken · ${remaining.length} not taken',
              )
            : all
                  .map((m) {
                    final name = m.displayNameForLanguage(
                      english ? 'en' : 'ko',
                    );
                    final taken = m.isSlotCompleted(pageSlot)
                        ? tr('복용 완료', 'Taken')
                        : tr('미복용', 'Not taken');
                    return '$name · $taken';
                  })
                  .join('\n'),
        'completed': completed,
        'action': pageAction == null
            ? 'open'
            : completed
            ? 'cancel'
            : 'take',
        'token': pageAction?['token'] ?? '',
        'button': pageAction == null
            ? tr('일정 열기', 'Open schedule')
            : completed
            ? tr('복용 취소', 'Undo dose')
            : tr('복용했어요', 'Taken'),
        'overdue':
            !readOnly &&
            !completed &&
            minute(pageSlot) < local.hour * 60 + local.minute,
      });
    }
    final take = takes[slot];
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
      'date_label': tr(
        '${local.month}월 ${local.day}일 ($weekday)',
        '${local.month}/${local.day} ($weekday)',
      ),
      'utc_offset_minutes': doseWidgetUtcOffset,
      'title': tr('나의 복약 일정', 'My medication'),
      'heading': !current
          ? tr('오늘 일정을 불러와주세요', 'Refresh today\'s schedule')
          : slot != null
          ? (readOnly ? label(slot) : '${label(slot)} ${time(slot)}')
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
      'overdue':
          !readOnly &&
          slot != null &&
          minute(slot) < local.hour * 60 + local.minute,
      'pages': pages,
      // 날짜·계정이 바뀌면 이전 위젯의 조회 위치를 재사용하지 않는다.
      'navigation_key':
          previous['owner'] == owner &&
              oldView['date'] == day &&
              (previous['config'] as Map?)?['source'] == config['source']
          ? oldView['navigation_key'] ?? newWidgetActionToken()
          : newWidgetActionToken(),
    };
    return DoseWidgetState({
      'owner': owner,
      'config': config,
      'take': take,
      'takes': takes,
      'cancels': cancels,
      'view': view,
    });
  }

  // Patient snapshots never share the owner's outbox, alarms or action tokens.
  static DoseWidgetState _patients(
    String owner,
    Map<String, dynamic> previous,
    DateTime now,
    Map<String, dynamic> config,
  ) {
    final base = DoseWidgetState.build(
      owner: owner,
      cache: null,
      operations: [],
      previous: previous,
      now: now,
      configuration: config,
      readOnly: true,
    );
    final english = config['language'] == 'en';
    String tr(String ko, String en) => english ? en : ko;
    final cache = previous['patient_cache'] as Map?;
    final current = cache?['date'] == doseWidgetDay(now);
    final patients = <Map<String, dynamic>>[];
    if (current) {
      for (final entry
          in (cache?['patients'] as List? ?? []).whereType<Map>()) {
        final ready = entry['schedules'] is List;
        final state = DoseWidgetState.build(
          owner: owner,
          cache: ready
              ? {'date': cache!['date'], 'schedules': entry['schedules']}
              : null,
          operations: [],
          previous: {},
          now: now,
          configuration: config,
          readOnly: true,
        );
        patients.add({
          ...state.view,
          'patient_key': entry['key'],
          'title': entry['alias'],
          'counts_known': ready,
          'status': cache?['failed'] == true
              ? tr('최근 조회 기준 · 새로고침 필요', 'Last loaded status · Refresh needed')
              : tr('환자가 기록한 복약 상태', 'Doses recorded by the patient'),
          'action': 'open',
          'token': '',
        });
      }
    }
    final view = {
      ...base.view,
      'source': 'patients',
      'title': tr('환자의 복약 일정', 'Patient medication'),
      'heading': !current || cache?['failed'] == true
          ? tr('환자 일정을 새로고침해주세요', 'Refresh patient schedules')
          : tr('연결된 환자가 없습니다', 'No linked patients'),
      'details': '',
      'status': '',
      'action': 'refresh',
      'token': '',
      'button': tr('새로고침', 'Refresh'),
      'patients': patients,
    };
    return DoseWidgetState({
      ...base.data,
      'patient_cache': cache,
      'patient_revision': previous['patient_revision'],
      'view': view,
    });
  }
}
