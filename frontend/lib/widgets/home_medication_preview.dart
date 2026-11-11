// 파일명: home_medication_preview.dart
// 역할: 본인과 연결된 환자의 홈 복약 미리보기에 같은 카드 양식을 적용한다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';

// 클래스명: HomeMedicationPreview
// 역할: 홈에서 진행률과 일정 요약 또는 조회 상태 안내를 공통 틀로 표시한다.
// 주요 책임: 이름 탐색·헤더 조작·일정 내용과 선택적 복용 명령을 화면 조건에 맞게 배치한다.
// 속성: title 계열: 제목; progress 계열: 진행 표시; schedule 계열/statusContent: 정상·상태 내용; compact: 밀도; 콜백·선택 위젯: 조작 영역.
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
  final Widget? statusContent;

  // 함수이름: HomeMedicationPreview
  // 함수역할: 진행률과 일정 요약을 표시하는 홈 미리보기를 구성한다.
  // 매개변수: key/title: 식별과 제목; progressTitle/progressLabel/progress/progressSemanticsLabel: 진행 표시; scheduleTitle/scheduleDescription/hasPendingMedication: 요약; compact: 밀도; onTap: 진입; headerAction/action/titleLeading/titleTrailing/scheduleContent: 선택적 구성 요소.
  // 반환값: 정상 일정 미리보기; statusContent는 사용하지 않는다.
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
  }) : statusContent = null;

  // 함수이름: HomeMedicationPreview.status
  // 함수역할: 조회 중·실패·연결 없음 같은 상태 내용을 정상 일정과 같은 틀에 배치한다.
  // 매개변수: key/title: 식별과 제목; content: 상태 내용; compact/onTap: 배치와 진입; headerAction/titleLeading/titleTrailing: 선택적 제목 조작.
  // 반환값: 진행률과 일정 요약 대신 content를 표시하는 미리보기.
  const HomeMedicationPreview.status({
    super.key,
    required this.title,
    required Widget content,
    this.compact = false,
    this.onTap,
    this.headerAction,
    this.titleLeading,
    this.titleTrailing,
  }) : statusContent = content,
       progressTitle = '',
       progressLabel = '',
       progress = null,
       progressSemanticsLabel = null,
       scheduleTitle = '',
       scheduleDescription = '',
       hasPendingMedication = false,
       scheduleContent = null,
       action = null;

  // 함수이름: _heart
  // 함수역할: 미리보기 제목 옆 공통 하트 표시를 만든다.
  // 매개변수: 없음.
  // 반환값: compact에 따라 정해진 크기를 사용하는 아이콘 위젯.
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

  // 함수이름: _titleGroup
  // 함수역할: 양옆 탐색 위젯의 위치를 유지하면서 제목을 남은 너비에 배치한다.
  // 매개변수: 없음.
  // 반환값: 두 줄까지 표시하고 넘친 제목은 생략하는 Row.
  Widget _titleGroup() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ?titleLeading,
      // 이름 길이가 바뀌어도 양옆 탐색 버튼의 가로 위치를 유지한다.
      Expanded(
        child: KeepWordsText(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: MedBuddyColors.textStrong,
            fontSize: compact ? 16 : 17,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      ?titleTrailing,
    ],
  );

  // 함수이름: _header
  // 함수역할: 너비와 글자 확대를 기준으로 제목·탐색 조작을 한 줄 또는 두 줄로 배치한다.
  // 매개변수: context: 글자 배율을 읽을 구성 문맥.
  // 반환값: 최소 높이를 유지하는 반응형 헤더.
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

  // Function Name: build
  // Description: Builds the shared preview frame with either status content or progress and schedule details.
  // Parameters: context: Flutter build context.
  // Returns: A tappable preview when onTap is supplied, with optional header and dose actions.
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
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context),
            SizedBox(height: compact ? 10 : 20),
            if (statusContent != null)
              statusContent!
            else ...[
              Row(
                children: [
                  Expanded(
                    child: KeepWordsText(
                      progressTitle,
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  KeepWordsText(
                    progressLabel,
                    style: const TextStyle(
                      color: MedBuddyColors.primaryDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
          ],
        ),
      ),
    ),
  );
}

// Class Name: HomeMedicationSummary
// Role: Shares a compact medication summary with optional slot navigation indicators.
// Responsibilities: Render semantic slot visuals, text and a details affordance without owning schedule state.
// Attributes: title/description: Text; slotKey/hasPendingMedication: Visual state; compact/descriptionMaxLines/showDetailsArrow/pageIndicator: Layout options.
class HomeMedicationSummary extends StatelessWidget {
  final String title;
  final String description;
  final bool hasPendingMedication;
  final bool compact;
  final bool showDetailsArrow;
  final int? descriptionMaxLines;
  final Widget? pageIndicator;
  final String? slotKey;

  // Function Name: HomeMedicationSummary
  // Description: Configures summary content and optional slot-specific styling.
  // Parameters: key: Identity; title/description: Text; hasPendingMedication: Incomplete state; compact/showDetailsArrow/descriptionMaxLines: Layout; pageIndicator: Optional navigation marker; slotKey: Optional style key.
  // Returns: An immutable summary widget.
  const HomeMedicationSummary({
    super.key,
    required this.title,
    required this.description,
    required this.hasPendingMedication,
    this.compact = false,
    this.showDetailsArrow = false,
    this.descriptionMaxLines,
    this.pageIndicator,
    this.slotKey,
  });

  // Function Name: build
  // Description: Builds slot-colored summary text and an optional page indicator within the existing padding.
  // Parameters: context: Flutter build context.
  // Returns: A summary surface with a neutral fallback when no slot is supplied.
  @override
  Widget build(BuildContext context) {
    final style = slotKey == null ? null : MedBuddySlotStyle.of(slotKey!);
    return Container(
    width: double.infinity,
    // 점 표시에는 기존 위아래 여백을 일부 사용해 요약 박스 높이를 유지한다.
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 10 : 16,
      vertical: (compact ? 10.0 : 16.0) - (pageIndicator == null ? 0 : 4),
    ),
    decoration: BoxDecoration(
      color: style?.tint ?? MedBuddyColors.surfaceSubtle,
      borderRadius: MedBuddyRadii.card,
    ),
    child: Row(
      children: [
        Container(
          width: compact ? 34 : 38,
          height: compact ? 34 : 38,
          decoration: BoxDecoration(
            color:
                style?.color ??
                (hasPendingMedication
                    ? MedBuddyColors.mint
                    : MedBuddyColors.lavenderSurface),
            borderRadius: MedBuddyRadii.control,
          ),
          child: Icon(
            style?.icon ??
                (hasPendingMedication
                    ? Icons.alarm_outlined
                    : Icons.event_available_outlined),
            color: style == null ? MedBuddyColors.primaryDark : Colors.white,
            size: compact ? 19 : 21,
          ),
        ),
        SizedBox(width: compact ? 10 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeepWordsText(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: compact ? 2 : 3),
              KeepWordsText(
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
}
