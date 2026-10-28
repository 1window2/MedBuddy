import 'package:flutter/material.dart';

// 결과 요약을 첫 프레임부터 표시하며 아래 목록만 독립적으로 스크롤한다.
class PinnedAnalysisSummary extends StatelessWidget {
  const PinnedAnalysisSummary({
    super.key,
    required this.summary,
    required this.child,
  });

  final Widget summary;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: constraints.maxHeight * .35,
            ),
            child: SingleChildScrollView(
              child: KeyedSubtree(
                key: const Key('analysis-summary-pinned'),
                child: summary,
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}
