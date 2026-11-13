// File Name: prescription_lookup_summary_widgets.dart
// Role: Renders pinned lookup counts alongside the independently scrollable prescription review.

part of 'prescription_analysis_preview_ui_boundary.dart';

// Class Name: _PrescriptionReviewLayout
// Role: A prescription review layout whose header cannot consume the whole viewport.
// Responsibilities: Caps title height and optionally pins lookup status above the scrollable body.
// Attributes: title (String): heading; isEnglish (bool): language; showSummary (bool): summary visibility; counts (Map<MedicationLookupStatus,int>): totals; child (Widget): review body.
class _PrescriptionReviewLayout extends StatelessWidget {
  final String title;
  final bool isEnglish;
  final bool showSummary;
  final Map<MedicationLookupStatus, int> counts;
  final Widget child;

  // 함수이름: _PrescriptionReviewLayout
  // 함수역할: 처방 검토 제목·조회 건수와 스크롤 본문을 받는다.
  // 매개변수: title (String): 제목; isEnglish/showSummary (bool): 언어·요약 여부; counts (Map<MedicationLookupStatus,int>): 상태별 건수; child (Widget): 본문.
  // 반환값: 새 _PrescriptionReviewLayout.
  const _PrescriptionReviewLayout({
    required this.title,
    required this.isEnglish,
    required this.showSummary,
    required this.counts,
    required this.child,
  });

  // Function Name: build
  // Description: Reserves bounded title and summary regions while keeping the review body scrollable.
  // Parameters: context (BuildContext): Parent layout location.
  // Returns: LayoutBuilder containing the constrained review layout.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        // 가로 화면·큰 글씨에서도 본문을 가리지 않도록 고정 영역의 최대 높이를 제한한다.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .25),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: KeepWordsText(
                title,
                key: const Key('prescription-review-title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: showSummary
              ? PinnedAnalysisSummary(
                  horizontalPadding: 16,
                  maxHeightFactor: .4,
                  summaryKey: const Key('lookup-summary-pinned-viewport'),
                  gap: 10,
                  summary: _MedicationLookupSummary(
                    key: const Key('lookup-summary-pinned'),
                    counts: counts,
                    isEnglish: isEnglish,
                  ),
                  child: _buildScrollRegion(),
                )
              : _buildScrollRegion(),
        ),
      ],
    ),
  );

  // Function Name: _buildScrollRegion
  // Description: Clips the scrollable review body and adds top spacing only when the lookup summary is hidden.
  // Parameters: None.
  // Returns: Scrollable review region.
  Widget _buildScrollRegion() => ClipRect(
    key: const Key('prescription-review-scroll-region'),
    child: _ScrollableCenteredCard(
      topPadding: showSummary ? 0 : 24,
      child: child,
    ),
  );
}

// 클래스명: _MedicationLookupSummary
// 역할: 약품 조회의 확정·후보·미발견·실패·대기 건수를 요약한다.
// 주요 책임: 조회 상태별 색상과 문구로 건수를 표시하고 변경을 접근성 알림으로 제공한다.
// 속성: counts (Map<MedicationLookupStatus,int>): 상태별 합계; isEnglish (bool): 언어.
class _MedicationLookupSummary extends StatelessWidget {
  final Map<MedicationLookupStatus, int> counts;
  final bool isEnglish;

  // 함수이름: _MedicationLookupSummary
  // 함수역할: 조회 상태별 건수와 표시 언어를 저장한다.
  // 매개변수: key (Key?): 식별 키; counts (Map<MedicationLookupStatus,int>): 합계; isEnglish (bool): 영어 여부.
  // 반환값: 새 _MedicationLookupSummary.
  const _MedicationLookupSummary({
    super.key,
    required this.counts,
    required this.isEnglish,
  });

  // 함수이름: build
  // 함수역할: 확정·후보·미발견·실패를 표로 배치하고 대기가 있을 때만 대기 행을 추가한다.
  // 매개변수: context (BuildContext): 표시 위치.
  // 반환값: 변경을 알리는 Semantics 요약 위젯.
  @override
  Widget build(BuildContext context) {
    // 함수이름: count
    // 함수역할: 조회 상태에 맞는 문구·색상과 건수를 표시한다. 누락된 상태의 건수는 0으로 본다.
    // 매개변수: status (MedicationLookupStatus): 표시할 상태.
    // 반환값: 상태별 건수 행.
    Widget count(MedicationLookupStatus status) {
      final (label, foreground, background) = _lookupStatusPresentation(
        status,
        isEnglish,
      );
      final value = counts[status] ?? 0;
      return Container(
        key: Key('lookup-summary-count-${status.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        color: background,
        child: Row(
          children: [
            Expanded(
              child: KeepWordsText(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$value',
              style: TextStyle(
                color: foreground,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: MedBuddyColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: MedBuddyRadii.small,
          side: const BorderSide(color: MedBuddyColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Table(
              defaultVerticalAlignment:
                  TableCellVerticalAlignment.intrinsicHeight,
              children: [
                TableRow(
                  children: [
                    count(MedicationLookupStatus.verified),
                    count(MedicationLookupStatus.candidates),
                  ],
                ),
                TableRow(
                  children: [
                    count(MedicationLookupStatus.notFound),
                    count(MedicationLookupStatus.failed),
                  ],
                ),
              ],
            ),
            if ((counts[MedicationLookupStatus.pending] ?? 0) > 0)
              count(MedicationLookupStatus.pending),
          ],
        ),
      ),
    );
  }
}
