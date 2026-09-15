// 파일명: home_medication_preview.dart
// 역할: 본인과 연결된 환자의 홈 복약 미리보기에 같은 카드 양식을 적용한다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 클래스명: HomeMedicationPreview
// 역할: 진행률과 일정 안내를 표시한다. 복용 처리는 본인 화면에서 전달한 action만 제공한다.
class HomeMedicationPreview extends StatelessWidget {
  final String title;
  final String progressTitle;
  final String progressLabel;
  final double? progress;
  final String? progressSemanticsLabel;
  final String scheduleTitle;
  final String scheduleDescription;
  final bool hasPendingMedication;
  final bool compact;
  final VoidCallback? onTap;
  final Widget? headerAction;
  final Widget? action;

  const HomeMedicationPreview({
    super.key,
    required this.title,
    required this.progressTitle,
    required this.progressLabel,
    required this.progress,
    this.progressSemanticsLabel,
    required this.scheduleTitle,
    required this.scheduleDescription,
    required this.hasPendingMedication,
    this.compact = false,
    this.onTap,
    this.headerAction,
    this.action,
  });

  // 함수역할: 환자 화면의 간격과 글꼴을 유지하면서 선택적 조회·복용 동작을 배치한다.
  @override
  Widget build(BuildContext context) => Material(
    color: MedBuddyColors.surface,
    borderRadius: MedBuddyRadii.largeCard,
    child: InkWell(
      borderRadius: MedBuddyRadii.largeCard,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: compact ? 190 : 260),
        padding: EdgeInsets.all(compact ? 14 : 24),
        decoration: BoxDecoration(
          borderRadius: MedBuddyRadii.largeCard,
          border: Border.all(color: MedBuddyColors.cardBorder),
          boxShadow: MedBuddyShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: compact ? 42 : 46,
                  height: compact ? 42 : 46,
                  decoration: BoxDecoration(
                    color: MedBuddyColors.mint,
                    borderRadius: BorderRadius.circular(compact ? 14 : 15),
                  ),
                  child: Icon(
                    Icons.favorite_rounded,
                    color: MedBuddyColors.primaryDark,
                    size: compact ? 22 : 24,
                  ),
                ),
                SizedBox(width: compact ? 11 : 13),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: compact ? 16 : 17,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ?headerAction,
              ],
            ),
            SizedBox(height: compact ? 10 : 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    progressTitle,
                    style: const TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  progressLabel,
                  style: const TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 6 : 9),
            ClipRRect(
              borderRadius: MedBuddyRadii.pill,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: compact ? 7 : 9,
                color: MedBuddyColors.primary,
                backgroundColor: MedBuddyColors.mint,
                semanticsLabel: progressSemanticsLabel,
              ),
            ),
            SizedBox(height: compact ? 10 : 18),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(compact ? 10 : 16),
              decoration: BoxDecoration(
                color: MedBuddyColors.surfaceSubtle,
                borderRadius: MedBuddyRadii.card,
              ),
              child: Row(
                children: [
                  Container(
                    width: compact ? 34 : 38,
                    height: compact ? 34 : 38,
                    decoration: BoxDecoration(
                      color: hasPendingMedication
                          ? MedBuddyColors.mint
                          : MedBuddyColors.lavenderSurface,
                      borderRadius: BorderRadius.circular(compact ? 11 : 13),
                    ),
                    child: Icon(
                      hasPendingMedication
                          ? Icons.alarm_outlined
                          : Icons.event_available_outlined,
                      color: MedBuddyColors.primaryDark,
                      size: compact ? 19 : 21,
                    ),
                  ),
                  SizedBox(width: compact ? 10 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scheduleTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MedBuddyColors.textStrong,
                            fontSize: compact ? 13 : 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: compact ? 2 : 3),
                        Text(
                          scheduleDescription,
                          style: TextStyle(
                            color: MedBuddyColors.textMuted,
                            fontSize: compact ? 11 : 12,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: MedBuddyColors.textSubtle,
                      size: 16,
                    ),
                  ],
                ],
              ),
            ),
            if (action != null) ...[
              SizedBox(height: compact ? 10 : 14),
              action!,
            ],
          ],
        ),
      ),
    ),
  );
}
