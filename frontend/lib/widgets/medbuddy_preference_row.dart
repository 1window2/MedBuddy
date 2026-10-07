// 파일명: medbuddy_preference_row.dart
// 역할: 환경설정과 조회 조건에서 같은 라벨·현재 값·화살표 배치를 제공한다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 클래스명: MedBuddyPreferenceRow
// 역할: 시간·공개 범위·화면 이동을 같은 라벨·값·화살표 배치로 제공한다.
class MedBuddyPreferenceRow extends StatelessWidget {
  final String title;
  final String? description;
  final String? value;
  final VoidCallback? onTap;

  // 함수이름: MedBuddyPreferenceRow
  // 함수역할: 라벨·설명·현재 값·선택 콜백을 받는다. 반환값: 설정 행.
  const MedBuddyPreferenceRow({
    required this.title,
    required this.onTap,
    this.description,
    this.value,
    super.key,
  });

  // 함수이름: build
  // 함수역할: 큰 글씨에서 현재 값의 너비를 제한해 제목과 겹치지 않게 배치한다.
  // 매개변수: context는 접근성 배율과 테마. 반환값: 최소 64 높이의 설정 행.
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
                          Text(
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
                            Text(
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
                        child: Text(
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
