import 'package:flutter/material.dart';

import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: check_today_medication_info_ui_boundary.dart
// 역할: 홈 화면에서 오늘의 복약 정보 요약을 표시한다.

// 클래스명: CheckTodayMedicationInfoUI
// 역할: 오늘의 복약 일정과 완료 진행률을 한 장의 요약 카드로 보여준다.
// 주요 책임:
// - 로딩, 빈 일정, 일정 요약 상태를 사용자 설정에 맞게 표시한다.
// - 사용자가 카드를 누르면 오늘의 복약 일정 화면으로 이동하도록 요청한다.
class CheckTodayMedicationInfoUI extends StatelessWidget {
  final String title;
  final String noMedicationLabel;
  final UserSetting userSetting;
  final List<MedicationSchedule> schedules;
  final int completedCount;
  final int totalCount;
  final bool isLoading;
  final VoidCallback? onTap;

  const CheckTodayMedicationInfoUI({
    super.key,
    required this.title,
    required this.noMedicationLabel,
    required this.userSetting,
    required this.schedules,
    required this.completedCount,
    required this.totalCount,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Material(
      color: Colors.white,
      borderRadius: MedBuddyRadii.card,
      elevation: 7,
      shadowColor: const Color.fromRGBO(0, 0, 0, 0.16),
      child: InkWell(
        borderRadius: MedBuddyRadii.card,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 171),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: Border.all(color: MedBuddyColors.mint, width: 2.7),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: MedBuddyColors.primary,
                size: 50,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF0A0A0A),
                  fontSize: 22 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                _buildScheduleSummary(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MedBuddyColors.textLight,
                  fontSize: 14 * scale,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildScheduleSummary() {
    final isEnglish =
        userSetting.language.trim().toLowerCase().startsWith('en');
    if (isLoading) {
      return isEnglish ? 'Loading schedule...' : '일정을 불러오는 중입니다';
    }
    if (schedules.isEmpty) {
      return noMedicationLabel;
    }

    final firstNames =
        schedules.take(2).map((schedule) => schedule.displayName).join(', ');
    final remainingCount = schedules.length - 2;
    final suffix = remainingCount > 0
        ? (isEnglish ? ' and $remainingCount more' : ' 외 $remainingCount개')
        : '';
    final displayTotalCount = totalCount == 0 ? schedules.length : totalCount;
    return isEnglish
        ? '$completedCount/$displayTotalCount completed\n$firstNames$suffix'
        : '$completedCount/$displayTotalCount 복용 완료\n$firstNames$suffix';
  }
}
