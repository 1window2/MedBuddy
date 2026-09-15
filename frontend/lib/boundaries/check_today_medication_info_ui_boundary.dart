import 'package:flutter/material.dart';

import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: check_today_medication_info_ui_boundary.dart
// 역할: 홈의 다음 복약 시간과 오늘 완료 진행률 요약을 제공한다.

// Class Name: CheckTodayMedicationInfoUI
// Role: Represents the next dose, remaining medications, and today's progress summary.
// Responsibilities:
// - Combines completion status and reminder times to find the next dose slot.
// - Adapts no-schedule and all-complete messages to language and text size.
// - Requests today's schedule when the card is tapped.
// Attributes:
// - title (String): Heading shown for the screen, section, or item.
// - noMedicationLabel (String): Fallback wording when a value or medication information is unavailable.
// - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
// - schedules (List<MedicationSchedule>): Medication schedules for review, display, or slot grouping.
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

  // 함수이름: CheckTodayMedicationInfoUI
  // 함수역할: 다음 복약 시간·남은 약·오늘 진행률 요약에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - noMedicationLabel (String): 값이나 약품 정보를 제공할 수 없을 때 사용할 대체 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - schedules (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
  // - reminderSettings (Map<String, MedicationAlarm>): 시간대 키별 알림 설정.
  // - completedCount (int): 완료한 복약 횟수.
  // - totalCount (int): 예정된 전체 복약 횟수 또는 처리 항목 수.
  // - isLoading (bool): 진행 중 표시를 보여줄지 여부.
  // - onTap (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // - nowProvider (DateTime Function()?): 현재 시각을 공급하는 함수; 생략하면 기기 현재 시각 사용.
  // - compact (bool): 공간을 줄인 카드·상단 배치를 사용할지 여부.
  // - largeTextGridLayout (bool): 큰 글씨 전용 격자 배치를 사용할지 여부.
  // - largeGridTitle (String?): 화면·구역·항목에 표시할 제목.
  // 반환값: 입력 설정이 반영된 CheckTodayMedicationInfoUI 인스턴스.
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

  // Function Name: build
  // Description: Renders the next dose, remaining medications, and today's progress summary from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the next dose, remaining medications, and today's progress summary.
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
            padding: EdgeInsets.all(largeTextGridLayout ? 8 : 10),
            decoration: BoxDecoration(
              borderRadius: MedBuddyRadii.card,
              border: Border.all(color: MedBuddyColors.successBorder),
              boxShadow: MedBuddyShadows.soft,
            ),
            child: largeTextGridLayout
                ? Column(
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
                        maxLines: 3,
                        overflow: TextOverflow.visible,
                        style: const TextStyle(
                          color: MedBuddyColors.textStrong,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: MedBuddyColors.mint,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.schedule_rounded,
                              color: MedBuddyColors.primaryDark,
                              size: 25,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              displayedTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: MedBuddyColors.textStrong,
                                fontSize: 15 * scale,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        summary.primaryText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: summary.isActionable
                              ? MedBuddyColors.primaryDark
                              : MedBuddyColors.textSubtle,
                          fontSize: 11 * scale,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  // 함수이름: _isEnglish
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두어로 영어 여부를 판별한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get _isEnglish =>
      userSetting.language.trim().toLowerCase().startsWith('en');

  // 함수이름: _buildScheduleSummary
  // 함수역할: 완료되지 않은 복약 시간대 중 현재 시각과 가장 가까운 다음 행동을 계산한다.
  // 매개변수:
  // - 없음.
  // 반환값: _TodayScheduleSummary: 다음 복약·미복용·완료 상태의 홈 요약 문구.
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
          // 함수이름: _buildScheduleSummary.where callback
          // 함수역할: 다음 복약 시간·남은 약·오늘 진행률 요약에 대해 `schedule.slotKeys.contains(slotKey) && !schedule.isSlotCompleted(slotKey)` 조건으로 컬렉션 항목을 판별한다.
          // 매개변수:
          // - schedule (콜백 계약에서 추론): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
          // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
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
          // 함수이름: _buildScheduleSummary.firstWhere callback
          // 함수역할: 다음 복약 시간·남은 약·오늘 진행률 요약에 대해 `!slot!.scheduledAt.isBefore(now)` 조건으로 컬렉션 항목을 판별한다.
          // 매개변수:
          // - slot (콜백 계약에서 추론): 복약 시간대의 식별·시각·표시 정보.
          // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
          (slot) => !slot!.scheduledAt.isBefore(now),
          // 함수이름: _buildScheduleSummary.orElse callback
          // 함수역할: 다음 복약 시간·남은 약·오늘 진행률 요약의 캡처된 상태에서 `null` 값을 제공한다.
          // 매개변수:
          // - 없음.
          // 반환값: `null`의 값.
          orElse: () => null,
        ) ??
        pendingSlots.first;
    final isPastDue = nextSlot.scheduledAt.isBefore(now);
    final slotLabel = _slotLabel(nextSlot.slotKey);
    final timeLabel = userSetting.formatTime(
      nextSlot.scheduledAt.hour,
      nextSlot.scheduledAt.minute,
    );
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

  // 함수이름: _slotLabel
  // 함수역할: 복약 시간대 키를 한국어·영어 이름으로 변환하고 알 수 없는 키는 그대로 표시한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
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

// 클래스명: _PendingMedicationSlot
// 역할: 미완료 시간대의 예정 시각과 남은 약 개수를 담당한다.
// 주요 책임:
// - 미완료 시간대의 예정 시각과 남은 약 개수 관련 필드 값을 하나의 객체로 묶어 전달한다.
// 속성:
// - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
// - scheduledAt (DateTime): 해당 시간대의 실제 예정 날짜·시각.
// - medicationCount (int): 해당 시간대 또는 요약에 포함된 약품 수.
class _PendingMedicationSlot {
  final String slotKey;
  final DateTime scheduledAt;
  final int medicationCount;

  // 함수이름: _PendingMedicationSlot
  // 함수역할: 미완료 시간대의 예정 시각과 남은 약 개수 관련 값을 _PendingMedicationSlot 인스턴스에 담는다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // - scheduledAt (DateTime): 해당 시간대의 실제 예정 날짜·시각.
  // - medicationCount (int): 해당 시간대 또는 요약에 포함된 약품 수.
  // 반환값: 입력 설정이 반영된 _PendingMedicationSlot 인스턴스.
  const _PendingMedicationSlot({
    required this.slotKey,
    required this.scheduledAt,
    required this.medicationCount,
  });
}

// 클래스명: _TodayScheduleSummary
// 역할: 홈 카드의 주 문구·보조 문구·행동 필요 여부를 담당한다.
// 주요 책임:
// - 홈 카드의 주 문구·보조 문구·행동 필요 여부 관련 필드 값을 하나의 객체로 묶어 전달한다.
// 속성:
// - primaryText (String): 요약의 주된 안내 문구.
// - secondaryText (String): 요약의 보조 진행·약품 안내.
// - isActionable (bool): 사용자 확인이나 복약 처리가 필요한 요약 상태.
class _TodayScheduleSummary {
  final String primaryText;
  final String secondaryText;
  final bool isActionable;

  // 함수이름: _TodayScheduleSummary
  // 함수역할: 홈 카드의 주 문구·보조 문구·행동 필요 여부 관련 값을 _TodayScheduleSummary 인스턴스에 담는다.
  // 매개변수:
  // - primaryText (String): 요약의 주된 안내 문구.
  // - secondaryText (String): 요약의 보조 진행·약품 안내.
  // - isActionable (bool): 사용자 확인이나 복약 처리가 필요한 요약 상태.
  // 반환값: 입력 설정이 반영된 _TodayScheduleSummary 인스턴스.
  const _TodayScheduleSummary({
    required this.primaryText,
    this.secondaryText = '',
    this.isActionable = false,
  });
}
