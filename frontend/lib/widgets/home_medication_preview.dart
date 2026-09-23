// 파일명: home_medication_preview.dart
// 역할: 본인과 연결된 환자의 홈 복약 미리보기에 같은 카드 양식을 적용한다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 클래스명: HomeMedicationPreview
// 역할: 진행률과 일정 요약을 표시하고 화면별 조회·복용 동작을 배치한다.
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
  final Widget? titleLeading;
  final Widget? titleTrailing;
  final Widget? scheduleContent;

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
    this.titleLeading,
    this.titleTrailing,
    this.scheduleContent,
  });

  Widget _heart() => Container(
    key: const Key('home-preview-heart'),
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
  );

  Widget _titleGroup() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ?titleLeading,
      Flexible(
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
      ?titleTrailing,
    ],
  );

  Widget _header(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heartWidth = compact ? 42.0 : 46.0;
      final gap = compact ? 11.0 : 13.0;
      final controlsWidth =
          (titleLeading == null ? 0.0 : 48.0) +
          (titleTrailing == null ? 0.0 : 48.0) +
          (headerAction == null ? 0.0 : 48.0);
      final minimumNameWidth =
          MediaQuery.textScalerOf(context).scale(compact ? 16 : 17) * 4;
      final separateTitle =
          (titleLeading != null || titleTrailing != null) &&
          constraints.maxWidth - heartWidth - gap - controlsWidth <
              minimumNameWidth;
      // 좁은 화면의 큰 글씨에서는 이름과 양옆 화살표를 함께 다음 줄에 배치한다.
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: separateTitle
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [_heart(), const Spacer(), ?headerAction]),
                  const SizedBox(height: 4),
                  _titleGroup(),
                ],
              )
            : Row(
                children: [
                  _heart(),
                  SizedBox(width: gap),
                  Expanded(child: _titleGroup()),
                  ?headerAction,
                ],
              ),
      );
    },
  );

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
            _header(context),
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
            scheduleContent ??
                HomeMedicationSummary(
                  title: scheduleTitle,
                  description: scheduleDescription,
                  hasPendingMedication: hasPendingMedication,
                  compact: compact,
                  showDetailsArrow: onTap != null,
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

// 클래스명: HomeMedicationSummary
// 역할: 홈 미리보기의 아이콘·간단한 요약·선택적 시간대 위치 표시를 공유한다.
class HomeMedicationSummary extends StatelessWidget {
  final String title;
  final String description;
  final bool hasPendingMedication;
  final bool compact;
  final bool showDetailsArrow;
  final int? descriptionMaxLines;
  final Widget? pageIndicator;

  // 함수이름: HomeMedicationSummary
  // 함수역할: 요약 내용과 표시 옵션을 받아 공통 배치를 구성한다.
  // 매개변수: title/description: 문구, hasPendingMedication: 미복용 여부,
  //   compact/showDetailsArrow/descriptionMaxLines: 배치 옵션, pageIndicator: 시간대 위치 표시, key: 식별자.
  // 반환값: 불변 요약 위젯.
  const HomeMedicationSummary({
    super.key,
    required this.title,
    required this.description,
    required this.hasPendingMedication,
    this.compact = false,
    this.showDetailsArrow = false,
    this.descriptionMaxLines,
    this.pageIndicator,
  });

  // 함수이름: build
  // 함수역할: 글 바로 아래에 선택적 점 표시를 붙이고 기존 요약 여백 안에 배치한다.
  // 매개변수: context: 화면 구성 환경. 반환값: 요약 박스.
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    // 점 표시에는 기존 위아래 여백을 일부 사용해 요약 박스 높이를 유지한다.
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 10 : 16,
      vertical: (compact ? 10.0 : 16.0) - (pageIndicator == null ? 0 : 4),
    ),
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
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: compact ? 2 : 3),
              Text(
                description,
                maxLines: descriptionMaxLines,
                overflow: descriptionMaxLines == null
                    ? null
                    : TextOverflow.ellipsis,
                style: TextStyle(
                  color: MedBuddyColors.textMuted,
                  fontSize: compact ? 11 : 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (pageIndicator != null) ...[
                const SizedBox(height: 4),
                pageIndicator!,
              ],
            ],
          ),
        ),
        if (showDetailsArrow) ...[
          const SizedBox(width: 8),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            color: MedBuddyColors.textSubtle,
            size: 16,
          ),
        ],
      ],
    ),
  );
}
