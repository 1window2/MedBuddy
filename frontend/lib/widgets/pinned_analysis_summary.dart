import 'package:flutter/material.dart';

// 결과 요약을 첫 프레임부터 표시하며 아래 목록만 독립적으로 스크롤한다.
// horizontalPadding·maxHeightFactor는 요약 영역의 좌우 여백과 사용 가능 높이 대비 최대 비율,
// summaryKey는 높이가 제한된 요약 영역, gap은 요약과 목록 사이 간격이다.
class PinnedAnalysisSummary extends StatelessWidget {
  const PinnedAnalysisSummary({
    super.key,
    required this.summary,
    required this.child,
    this.horizontalPadding = 20,
    this.maxHeightFactor = .35,
    this.summaryKey = const Key('analysis-summary-pinned'),
    this.gap = 0,
  });

  final Widget summary;
  final Widget child;
  final double horizontalPadding;
  final double maxHeightFactor;
  final Key summaryKey;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: ConstrainedBox(
            key: summaryKey,
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: constraints.maxHeight * maxHeightFactor,
            ),
            child: SingleChildScrollView(child: summary),
          ),
        ),
        if (gap > 0) SizedBox(height: gap),
        Expanded(child: child),
      ],
    ),
  );
}
