// 파일명: medbuddy_preference_row.dart
// 역할: 환경설정과 조회 조건에서 같은 라벨·현재 값·화살표 배치를 제공한다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';

// 클래스명: MedBuddyPreferenceRow
// 역할: 설정 제목·설명·현재 값을 하나의 선택 행으로 표시한다.
// 주요 책임: 비활성 상태와 통합 접근성 정보를 제공하고 긴 문구를 줄바꿈한다.
// 속성: title (String): 제목; description/value (String?): 설명·현재 값; onTap (VoidCallback?): 선택 동작, null이면 비활성.
class MedBuddyPreferenceRow extends StatelessWidget {
  final String title;
  final String? description;
  final String? value;
  final VoidCallback? onTap;

  // 함수이름: MedBuddyPreferenceRow
  // 함수역할: 설정 행의 표시 내용과 선택 가능 여부를 구성한다.
  // 매개변수: title (String): 제목; onTap (VoidCallback?): 선택 동작; description/value (String?): 설명·값; key (Key?): 위젯 식별자.
  // 반환값: MedBuddyPreferenceRow: 구성된 설정 행.
  const MedBuddyPreferenceRow({
    required this.title,
    required this.onTap,
    this.description,
    this.value,
    super.key,
  });

  // Function Name: build
  // Description: Build one semantic button row with wrapped labels and a width-bounded value; disable interaction when no callback is provided.
  // Parameters: context (BuildContext): layout context.
  // Returns: Widget: preference row with merged accessibility semantics.
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      button: true,
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KeepWordsText(
                            title,
                            style: TextStyle(
                              color: onTap == null
                                  ? MedBuddyColors.textMuted
                                  : MedBuddyColors.textStrong,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                          if (description != null) ...[
                            const SizedBox(height: 4),
                            KeepWordsText(
                              description!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: MedBuddyColors.textMuted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (value != null) ...[
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * 0.42,
                        ),
                        child: KeepWordsText(
                          value!,
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: MedBuddyColors.primaryDark,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: MedBuddyColors.textSubtle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
