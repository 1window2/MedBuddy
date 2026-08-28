import 'package:flutter/material.dart';

import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: check_today_medication_info_ui_boundary.dart
// 역할: 홈 화면에서 오늘 복약 일정의 다음 행동을 요약해 보여준다.

// 클래스명: CheckTodayMedicationInfoUI
// 역할: 다음 복약 시간과 남은 약 개수, 오늘의 완료 진행률을 한 카드에 표시한다.
// 주요 책임:
// - 복약 완료 상태와 알림 시간을 조합해 사용자가 다음에 확인할 시간대를 찾는다.
// - 일정이 없거나 모두 완료된 상태를 사용자 설정 언어와 글자 크기에 맞게 안내한다.
// - 카드를 누르면 오늘의 복약 일정 화면으로 이동하도록 요청한다.
class CheckTodayMedicationInfoUI extends StatelessWidget {
  static const List<String> _slotOrder = [
    'morning',
    'lunch',
    'evening',
    'bedtime',
  ];

  final String title;
  final String noMedicationLabel;
  final UserSetting userSetting;
  final List<MedicationSchedule> schedules;
  final Map<String, MedicationAlarm> reminderSettings;
  final int completedCount;
  final int totalCount;
  final bool isLoading;
  final bool compact;
  final bool largeTextGridLayout;
  final String? largeGridTitle;
  final VoidCallback? onTap;
  final DateTime Function()? nowProvider;

  const CheckTodayMedicationInfoUI({
    super.key,
    required this.title,
    required this.noMedicationLabel,
    required this.userSetting,
    required this.schedules,
    this.reminderSettings = const {},
    required this.completedCount,
    required this.totalCount,
    required this.isLoading,
    required this.onTap,
    this.nowProvider,
    this.compact = false,
    this.largeTextGridLayout = false,
    this.largeGridTitle,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;
    final summary = _buildScheduleSummary();
    final displayedTitle = largeTextGridLayout
        ? largeGridTitle ?? title
        : title;

    if (compact) {
      return Material(
        color: MedBuddyColors.surface,
        borderRadius: MedBuddyRadii.card,
        child: InkWell(
          borderRadius: MedBuddyRadii.card,
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: MedBuddyRadii.card,
              border: Border.all(color: MedBuddyColors.successBorder),
              boxShadow: MedBuddyShadows.soft,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: MedBuddyColors.mint,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    color: MedBuddyColors.primaryDark,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  displayedTitle,
                  maxLines: largeTextGridLayout ? 3 : 2,
                  overflow: largeTextGridLayout
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: largeTextGridLayout ? 14 : 16 * scale,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!largeTextGridLayout) ...[
                  const SizedBox(height: 2),
                  Text(
                    summary.primaryText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: summary.isActionable
                          ? MedBuddyColors.primaryDark
                          : MedBuddyColors.textSubtle,
                      fontSize: 11 * scale,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: MedBuddyColors.surface,
      borderRadius: MedBuddyRadii.largeCard,
      elevation: 0,
      child: InkWell(
        borderRadius: MedBuddyRadii.largeCard,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 164),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.largeCard,
            border: Border.all(color: MedBuddyColors.successBorder),
            boxShadow: MedBuddyShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: MedBuddyColors.mint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.schedule_rounded,
                      color: MedBuddyColors.primaryDark,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: MedBuddyColors.textLight,
                    size: 16,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                summary.primaryText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: summary.isActionable
                      ? MedBuddyColors.primaryDark
                      : MedBuddyColors.textLight,
                  fontSize: 15 * scale,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (summary.secondaryText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  summary.secondaryText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MedBuddyColors.textLight,
                    fontSize: 13 * scale,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (!isLoading && schedules.isNotEmpty) ...[
                const SizedBox(height: 9),
                Text(
                  _isEnglish ? 'View today\'s schedule' : '오늘 복약 일정 확인하기',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _isEnglish =>
      userSetting.language.trim().toLowerCase().startsWith('en');

  // 함수명: _buildScheduleSummary
  // 역할:
  // - 완료되지 않은 복약 시간대 중 현재 시각과 가장 가까운 다음 행동을 계산한다.
  // 반환값:
  // - 홈 카드에 표시할 주 문구와 보조 문구
  _TodayScheduleSummary _buildScheduleSummary() {
    if (isLoading) {
      return _TodayScheduleSummary(
        primaryText: _isEnglish ? 'Loading schedule...' : '일정을 불러오는 중입니다',
      );
    }
    if (schedules.isEmpty) {
      return _TodayScheduleSummary(primaryText: noMedicationLabel);
    }

    final displayTotalCount = totalCount == 0 ? schedules.length : totalCount;
    if (completedCount >= displayTotalCount) {
      return _TodayScheduleSummary(
        primaryText: _isEnglish
            ? 'All medication completed today'
            : '오늘 복약을 모두 완료했습니다',
        secondaryText: '$completedCount/$displayTotalCount',
      );
    }

    final now = nowProvider?.call() ?? DateTime.now();
    final pendingSlots = <_PendingMedicationSlot>[];
    for (final slotKey in _slotOrder) {
      final pendingSchedules = schedules
          .where((schedule) {
            return schedule.slotKeys.contains(slotKey) &&
                !schedule.isSlotCompleted(slotKey);
          })
          .toList(growable: false);
      if (pendingSchedules.isEmpty) {
        continue;
      }

      final alarm =
          reminderSettings[slotKey] ?? MedicationAlarm.defaults(slotKey);
      final scheduledAt = DateTime(
        now.year,
        now.month,
        now.day,
        alarm.hour,
        alarm.minute,
      );
      pendingSlots.add(
        _PendingMedicationSlot(
          slotKey: slotKey,
          scheduledAt: scheduledAt,
          medicationCount: pendingSchedules.length,
        ),
      );
    }

    if (pendingSlots.isEmpty) {
      return _TodayScheduleSummary(
        primaryText: _isEnglish
            ? 'Review today\'s medication status'
            : '오늘 복약 상태를 확인해주세요',
        secondaryText: '$completedCount/$displayTotalCount',
      );
    }

    final nextSlot =
        pendingSlots.cast<_PendingMedicationSlot?>().firstWhere(
          (slot) => !slot!.scheduledAt.isBefore(now),
          orElse: () => null,
        ) ??
        pendingSlots.first;
    final isPastDue = nextSlot.scheduledAt.isBefore(now);
    final slotLabel = _slotLabel(nextSlot.slotKey);
    final timeLabel =
        '${nextSlot.scheduledAt.hour.toString().padLeft(2, '0')}:'
        '${nextSlot.scheduledAt.minute.toString().padLeft(2, '0')}';
    final primaryLabel = _isEnglish
        ? (isPastDue ? 'Check missed dose' : 'Next medication')
        : (isPastDue ? '미복용 확인' : '다음 복약');
    final medicationCountLabel = _isEnglish
        ? '${nextSlot.medicationCount} medication(s)'
        : '복용할 약 ${nextSlot.medicationCount}개';
    final progressLabel = _isEnglish
        ? '$completedCount/$displayTotalCount completed today'
        : '오늘 $completedCount/$displayTotalCount회 완료';

    return _TodayScheduleSummary(
      primaryText: '$primaryLabel: $slotLabel $timeLabel',
      secondaryText: '$medicationCountLabel · $progressLabel',
      isActionable: true,
    );
  }

  String _slotLabel(String slotKey) {
    if (_isEnglish) {
      return switch (slotKey) {
        'morning' => 'Morning',
        'lunch' => 'Lunch',
        'evening' => 'Evening',
        'bedtime' => 'Bedtime',
        _ => slotKey,
      };
    }
    return switch (slotKey) {
      'morning' => '아침',
      'lunch' => '점심',
      'evening' => '저녁',
      'bedtime' => '취침 전',
      _ => slotKey,
    };
  }
}

class _PendingMedicationSlot {
  final String slotKey;
  final DateTime scheduledAt;
  final int medicationCount;

  const _PendingMedicationSlot({
    required this.slotKey,
    required this.scheduledAt,
    required this.medicationCount,
  });
}

class _TodayScheduleSummary {
  final String primaryText;
  final String secondaryText;
  final bool isActionable;

  const _TodayScheduleSummary({
    required this.primaryText,
    this.secondaryText = '',
    this.isActionable = false,
  });
}
