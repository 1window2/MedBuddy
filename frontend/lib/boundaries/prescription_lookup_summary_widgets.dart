part of 'prescription_analysis_preview_ui_boundary.dart';

// 조회 결과는 대기 없이 제목 아래에 표시하고 본문과 분리해 고정한다.
class _PrescriptionReviewLayout extends StatelessWidget {
  final String title;
  final bool isEnglish;
  final bool showSummary;
  final Map<MedicationLookupStatus, int> counts;
  final Widget child;

  const _PrescriptionReviewLayout({
    required this.title,
    required this.isEnglish,
    required this.showSummary,
    required this.counts,
    required this.child,
  });

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
              child: Text(
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
          child: LayoutBuilder(
            builder: (context, bodyConstraints) => Column(
              children: [
                if (showSummary)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ConstrainedBox(
                      key: const Key('lookup-summary-pinned-viewport'),
                      constraints: BoxConstraints(
                        maxWidth: 640,
                        maxHeight: bodyConstraints.maxHeight * .4,
                      ),
                      child: SingleChildScrollView(
                        child: _MedicationLookupSummary(
                          key: const Key('lookup-summary-pinned'),
                          counts: counts,
                          isEnglish: isEnglish,
                        ),
                      ),
                    ),
                  ),
                if (showSummary)
                  const SizedBox(
                    key: Key('lookup-summary-bottom-gap'),
                    height: 10,
                  ),
                Expanded(
                  child: ClipRect(
                    key: const Key('prescription-review-scroll-region'),
                    child: _ScrollableCenteredCard(
                      topPadding: showSummary ? 0 : 24,
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _MedicationLookupSummary extends StatelessWidget {
  final Map<MedicationLookupStatus, int> counts;
  final bool isEnglish;

  const _MedicationLookupSummary({
    super.key,
    required this.counts,
    required this.isEnglish,
  });

  @override
  Widget build(BuildContext context) {
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
              child: Text(
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
