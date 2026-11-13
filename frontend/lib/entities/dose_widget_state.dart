// File Name: dose_widget_state.dart
// Role: Projects encrypted account and caregiver snapshots into home-widget display and action state.
// Home-screen projections keep caregiver viewing separate from dose writes.
import 'dart:math';

import 'medication_alarm_entity.dart';
import 'medication_schedule_entity.dart';
import 'medication_slot_label.dart';
import 'user_setting_entity.dart';

const doseWidgetUtcOffset = int.fromEnvironment(
  'APPLICATION_UTC_OFFSET_MINUTES',
  defaultValue: 540,
);

// 함수이름: doseWidgetLocalTime
// 함수역할: 기준 시각에 위젯의 설정된 UTC 오프셋을 적용해 표시용 달력 필드를 만든다.
// 매개변수: now: 실제 기준 시각.
// 반환값: 오프셋만큼 이동한 UTC DateTime; 실제 새 시점을 나타내는 용도로 쓰지 않는다.
DateTime doseWidgetLocalTime(DateTime now) =>
    now.toUtc().add(const Duration(minutes: doseWidgetUtcOffset));

// 함수이름: doseWidgetDay
// 함수역할: 위젯 기준 시간대의 날짜 키를 만든다.
// 매개변수: now: 기준 시각.
// 반환값: YYYY-MM-DD 형태의 위젯 날짜.
String doseWidgetDay(DateTime now) =>
    doseWidgetLocalTime(now).toIso8601String().substring(0, 10);

// 함수이름: newWidgetActionToken
// 함수역할: 위젯 동작의 재사용을 구분할 보안 난수 토큰을 만든다.
// 매개변수: 없음.
// 반환값: widget_ 접두사와 24바이트 난수의 16진수 문자열.
String newWidgetActionToken() =>
    'widget_${List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

// Class Name: DoseWidgetState
// Role: Projects encrypted schedules and ordered outbox records into native widget state.
// Responsibilities: Build display and guarded actions from persisted data; native display values are never the source of truth.
// Attributes: data contains owner/configuration, action tokens, reminder completion and the native view; callers persist it within their acceptance transaction.
class DoseWidgetState {
  final Map<String, dynamic> data;
  // 함수이름: DoseWidgetState
  // 함수역할: 준비된 위젯 상태 맵을 감싼다.
  // 매개변수: data: 소유 계정·동작·표시 정보를 담은 맵.
  // 반환값: 상태 객체; 입력 맵을 복사하거나 검증하지 않는다.
  DoseWidgetState(this.data);

  // 함수이름: view
  // 함수역할: 위젯 표시 부분을 문자열 키 맵으로 복사해 제공한다.
  // 매개변수: 없음.
  // 반환값: view의 얕은 복사본; 저장된 필드가 맵이 아니면 타입 오류.
  Map<String, dynamic> get view =>
      Map<String, dynamic>.from(data['view'] as Map);

  // Function Name: completedReminderSlots
  // Description: Reads current-day completed owner slots independently of which patient's schedule is displayed.
  // Parameters: now: Reference instant for the widget day.
  // Returns: Supported completed slot keys in canonical order, or none for a missing/expired snapshot.
  Iterable<String> completedReminderSlots(DateTime now) {
    final reminder = data['reminder_slots'] as Map?;
    if (reminder == null || reminder['date'] != doseWidgetDay(now)) {
      return const [];
    }
    final completed = (reminder['slots'] as List? ?? const []).toSet();
    return medicationScheduleSlotKeys.where(completed.contains);
  }

  // Function Name: completedSlotsOf
  // Description: Selects slots containing at least one medication and no incomplete projected doses.
  // Parameters: schedules: Current schedules with pending operations applied.
  // Returns: Completed slot keys in canonical morning-to-bedtime order.
  static List<String> completedSlotsOf(List<MedicationSchedule> schedules) =>
      medicationScheduleSlotKeys.where((slot) {
        final scheduled = schedules.where((s) => s.slotKeys.contains(slot));
        return scheduled.isNotEmpty &&
            scheduled.every((s) => s.isSlotCompleted(slot));
      }).toList();

  // 함수이름: projectedSchedules
  // 함수역할: 같은 날짜 캐시의 일정에 대기 요청을 전달 순서대로 덮어 적용한다.
  // 매개변수: cache: 서버 일정 캐시; operations: 순서가 있는 요청 목록; day: 표시 날짜 키.
  // 반환값: 투영 일정 목록; 캐시 날짜가 다르면 빈 목록, 잘못된 요청 필드 타입은 전파한다.
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

  // Function Name: DoseWidgetState.build
  // Description: Builds current-day display pages and guarded take/undo actions from cache plus pending operations.
  // Parameters: owner: Account; cache: Schedule snapshot; operations: Ordered outbox; previous: Prior tokens/config; now: Clock; configuration: Override; readOnly: Disable dose actions.
  // Returns: A widget state expiring at the next configured midnight; blocked operations suppress actions and patient mode stays read-only.
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
    // 재알림 취소는 표시 설정·보류 기록과 관계없이 본인 일정의 투영 결과로 정한다.
    final reminderSlots = <String, dynamic>{
      'date': doseWidgetDay(now),
      'slots': readOnly
          ? const <String>[]
          : completedSlotsOf(
              projectedSchedules(cache, operations, doseWidgetDay(now)),
            ),
    };
    if (config['source'] == 'patients' && !readOnly) {
      return _patients(owner, previous, now, config, reminderSlots);
    }
    final oldView = previous['view'] as Map? ?? {};
    final english = isEnglishLanguage(config['language']?.toString());
    // 함수이름: tr
    // 함수역할: 위젯 설정 언어에 따라 해당 화면 문구를 선택한다.
    // 매개변수: ko/en: 한국어와 영어 문구.
    // 반환값: 현재 언어의 문구.
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
    // 함수이름: time
    // 함수역할: 시간대 알림의 설정 시각을 읽고 없으면 기본 시각을 사용한다.
    // 매개변수: slot: 복용 시간대 키.
    // 반환값: 알람 맵의 문자열 값 또는 기본 HH:mm.
    String time(String slot) =>
        alarms[slot]?.toString() ?? MedicationAlarm.defaults(slot).timeLabel;
    // 함수이름: minute
    // 함수역할: 페이지 정렬과 지연 판단에 사용할 알림 시각 값을 계산한다.
    // 매개변수: slot: 복용 시간대 키.
    // 반환값: 일반 모드에서는 자정 이후 분 수, 읽기 전용에서는 정해진 시간대 순서; 파싱 실패 부분은 0.
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
    // Function Name: label
    // Description: Localizes a medication slot label for the widget language.
    // Parameters: key: Supported medication slot key.
    // Returns: The display label from medicationSlotLabel.
    String label(String key) => medicationSlotLabel(key, isEnglish: english);
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
            ? tr('복용 완료 취소', 'Undo completion')
            : tr('복용했어요', 'Taken'),
        // 서버의 미복용 기준과 같이 복약 시각 뒤 유예 시간이 지나야 놓친 복약 안내를 띄운다.
        'overdue':
            !readOnly &&
            !completed &&
            minute(pageSlot) + missedDoseGraceMinutes <=
                local.hour * 60 + local.minute,
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
          minute(slot) + missedDoseGraceMinutes <=
              local.hour * 60 + local.minute,
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
      'reminder_slots': reminderSlots,
      'view': view,
    });
  }

  // Function Name: _patients
  // Description: Builds read-only patient pages without sharing the owner's outbox, alarms or dose-action tokens.
  // Parameters: owner/previous: Owner and persisted state; now: Reference time; config: Display preferences; reminderSlots: Owner's completed slots.
  // Returns: Patient widget state with fresh-cache pages and retained owner reminder cancellation data; expired data requests refresh.
  static DoseWidgetState _patients(
    String owner,
    Map<String, dynamic> previous,
    DateTime now,
    Map<String, dynamic> config,
    Map<String, dynamic> reminderSlots,
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
    final english = isEnglishLanguage(config['language']?.toString());
    // 함수이름: tr
    // 함수역할: 환자 일정 위젯의 안내 문구를 현재 설정 언어로 선택한다.
    // 매개변수: ko/en: 한국어와 영어 문구.
    // 반환값: 현재 언어의 문구.
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
          : tr('연동된 환자가 없습니다', 'No linked patients'),
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
      'reminder_slots': reminderSlots,
      'view': view,
    });
  }
}
