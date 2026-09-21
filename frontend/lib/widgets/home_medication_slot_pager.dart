// 파일명: home_medication_slot_pager.dart
// 역할: 기존 홈 요약 박스 안에서 시간대별 복용 상태를 넘겨 확인한다.
import 'package:flutter/material.dart';

import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../theme/medbuddy_theme.dart';
import 'home_medication_preview.dart';

class HomeMedicationSlotPager extends StatefulWidget {
  final List<MedicationSchedule> schedules;
  final bool isEnglish;
  final bool compact;
  final bool isLoading;
  final bool hasError;
  final String? initialSlotKey;
  // 보호자 조회에는 환자의 알림 시각이 없으므로 기본 시각을 추정하지 않는다.
  final Map<String, MedicationAlarm>? reminderSettings;
  final Future<bool> Function(String slotKey, bool completed)?
  onStatusUpdateRequested;
  final bool isCompletionLoading;
  final bool showDetailsButton;
  final VoidCallback? onDetailsRequested;

  const HomeMedicationSlotPager({
    super.key,
    required this.schedules,
    required this.isEnglish,
    this.compact = false,
    this.isLoading = false,
    this.hasError = false,
    this.initialSlotKey,
    this.reminderSettings,
    this.onStatusUpdateRequested,
    this.isCompletionLoading = false,
    this.showDetailsButton = false,
    this.onDetailsRequested,
  });

  @override
  State<HomeMedicationSlotPager> createState() =>
      _HomeMedicationSlotPagerState();
}

class _HomeMedicationSlotPagerState extends State<HomeMedicationSlotPager> {
  int _index = 0;
  bool _userSelected = false;
  bool _saving = false;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _index = _initialIndex();
  }

  int _initialIndex() {
    final preferred = medicationScheduleSlotKeys.indexOf(
      widget.initialSlotKey ?? '',
    );
    if (preferred >= 0) return preferred;
    for (var index = 0; index < medicationScheduleSlotKeys.length; index++) {
      final slot = medicationScheduleSlotKeys[index];
      if (widget.schedules.any(
        (s) => s.slotKeys.contains(slot) && !s.isSlotCompleted(slot),
      )) {
        return index;
      }
    }
    return 0;
  }

  @override
  void didUpdateWidget(HomeMedicationSlotPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_userSelected && oldWidget.isLoading && !widget.isLoading) {
      _index = _initialIndex();
    }
  }

  void _select(int index) {
    if (index < 0 ||
        index >= medicationScheduleSlotKeys.length ||
        index == _index) {
      return;
    }
    setState(() {
      _userSelected = true;
      _index = index;
    });
  }

  String _slotLabel(String slot) => switch (slot) {
    'morning' => widget.isEnglish ? 'Morning' : '아침',
    'lunch' => widget.isEnglish ? 'Lunch' : '점심',
    'evening' => widget.isEnglish ? 'Evening' : '저녁',
    _ => widget.isEnglish ? 'Bedtime' : '취침 전',
  };

  List<MedicationSchedule> _medications(String slot) => widget.schedules
      .where((schedule) => schedule.slotKeys.contains(slot))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final slot = medicationScheduleSlotKeys[_index];
    final medications = _medications(slot);
    final hasPending = medications.any((s) => !s.isSlotCompleted(slot));
    final busy = _saving || widget.isCompletionLoading;
    final unavailable = widget.isLoading || widget.hasError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          onIncrease: _index < medicationScheduleSlotKeys.length - 1
              ? () => _select(_index + 1)
              : null,
          onDecrease: _index > 0 ? () => _select(_index - 1) : null,
          child: GestureDetector(
            key: const Key('home-medication-slot-pager'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDetailsRequested,
            onHorizontalDragStart: (_) => _drag = 0,
            onHorizontalDragUpdate: (details) => _drag += details.delta.dx,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (_drag.abs() >= 40 || velocity.abs() >= 250) {
                _select(
                  _index +
                      ((_drag.abs() >= 40 ? _drag : velocity) < 0 ? 1 : -1),
                );
              }
            },
            // 약 개수와 관계없이 요약만 표시하고 넘길 때 박스 높이를 유지한다.
            child: IndexedStack(
              index: _index,
              sizing: StackFit.loose,
              children: [
                for (final key in medicationScheduleSlotKeys) _slotSummary(key),
              ],
            ),
          ),
        ),
        if (widget.onStatusUpdateRequested != null ||
            (widget.showDetailsButton && widget.onDetailsRequested != null))
          SizedBox(height: widget.compact ? 10 : 14),
        if (widget.onStatusUpdateRequested != null)
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              key: const ValueKey('homeNextSlotCompletionButton'),
              onPressed: !unavailable && !busy && medications.isNotEmpty
                  ? () => _updateSlot(slot, completed: hasPending)
                  : null,
              icon: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: MedBuddyColors.primaryDark,
                      ),
                    )
                  : Icon(
                      hasPending ? Icons.done_all_rounded : Icons.undo_rounded,
                    ),
              label: Text(
                busy
                    ? (widget.isEnglish ? 'Saving...' : '저장 중...')
                    : unavailable
                    ? (widget.isEnglish ? 'Check status' : '복약 현황 확인')
                    : medications.isEmpty
                    ? (widget.isEnglish ? 'No scheduled doses' : '복약 일정 없음')
                    : !hasPending
                    ? (widget.isEnglish ? 'Undo completion' : '복용 취소')
                    : (widget.isEnglish ? 'Taken' : '복용했어요'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: hasPending
                    ? MedBuddyColors.primary
                    : MedBuddyColors.surface,
                foregroundColor: hasPending
                    ? Colors.white
                    : MedBuddyColors.primaryDark,
                side: hasPending
                    ? null
                    : const BorderSide(color: MedBuddyColors.cardBorder),
              ),
            ),
          )
        else if (widget.showDetailsButton && widget.onDetailsRequested != null)
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              key: const Key('home-slot-view-schedule'),
              onPressed: widget.onDetailsRequested,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(widget.isEnglish ? 'View schedule' : '일정 보기'),
            ),
          ),
      ],
    );
  }

  Widget _slotSummary(String slot) {
    final medications = _medications(slot);
    final completed = medications.where((s) => s.isSlotCompleted(slot)).length;
    final alarm = widget.reminderSettings == null
        ? null
        : widget.reminderSettings![slot] ?? MedicationAlarm.defaults(slot);
    String status;
    String description;
    if (widget.isLoading || widget.hasError) {
      status = widget.isLoading
          ? (widget.isEnglish ? 'Loading status' : '복약 현황 확인 중')
          : (widget.isEnglish ? 'Status unavailable' : '복약 현황 확인 필요');
      description = widget.isEnglish
          ? 'Check medication status.'
          : '복약 상태를 확인해주세요.';
    } else if (medications.isEmpty) {
      status = widget.isEnglish ? 'No scheduled doses' : '복약 일정 없음';
      description = widget.isEnglish
          ? 'No medication scheduled for this time.'
          : '이 시간대에 등록된 약이 없습니다.';
    } else {
      status = completed == medications.length
          ? (widget.isEnglish ? 'Completed' : '복용 완료')
          : completed == 0
          ? (widget.isEnglish ? 'Not taken' : '미복용')
          : (widget.isEnglish
                ? '$completed/${medications.length} taken'
                : '$completed/${medications.length} 복용');
      final name = medications.first.displayNameForLanguage(
        widget.isEnglish ? 'en' : 'ko',
      );
      final additional = medications.length - 1;
      final names = additional == 0
          ? name
          : widget.isEnglish
          ? '$name +$additional more'
          : '$name 외 $additional개';
      description = alarm == null ? names : '${alarm.timeLabel} · $names';
    }
    return HomeMedicationSummary(
      key: ValueKey('home-slot-page-$slot'),
      title: '${_slotLabel(slot)} · $status',
      description: description,
      hasPendingMedication:
          !widget.isLoading &&
          !widget.hasError &&
          completed < medications.length,
      compact: widget.compact,
      showDetailsArrow: widget.onDetailsRequested != null,
      descriptionMaxLines: 2,
    );
  }

  Future<void> _updateSlot(String slot, {required bool completed}) async {
    if (_saving ||
        widget.isCompletionLoading ||
        widget.onStatusUpdateRequested == null) {
      return;
    }
    setState(() {
      _userSelected = true;
      _saving = true;
    });
    try {
      final success = await widget.onStatusUpdateRequested!(slot, completed);
      if (!mounted || !success || !completed) return;
      // 저장 중 사용자가 다른 시간대로 넘겼다면 그 선택을 유지한다.
      final savedIndex = medicationScheduleSlotKeys.indexOf(slot);
      if (_index != savedIndex) return;
      for (
        var next = savedIndex + 1;
        next < medicationScheduleSlotKeys.length;
        next++
      ) {
        final nextSlot = medicationScheduleSlotKeys[next];
        if (_medications(nextSlot).any((s) => !s.isSlotCompleted(nextSlot))) {
          _select(next);
          break;
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
