// File Name: medbuddy_option_sheet.dart
// Role: Provides the shared bottom-sheet frame and option rows used by home choice sheets.

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';

// 클래스명: MedBuddyOptionSheet
// 역할: 선택 항목을 안전 영역 안의 스크롤 가능한 시트로 배치한다.
// 주요 책임: 선택적으로 끌기 손잡이를 표시하고 자식 위젯의 순서를 유지한다.
// 속성: children (List<Widget>): 시트 내용; showHandle (bool): 손잡이 및 위쪽 안전 영역 적용 여부.
class MedBuddyOptionSheet extends StatelessWidget {
  final List<Widget> children;
  final bool showHandle;

  // 함수이름: MedBuddyOptionSheet
  // 함수역할: 시트 내용과 손잡이 표시 여부를 보관한다.
  // 매개변수: key (Key?): 위젯 식별자; children (List<Widget>): 내용; showHandle (bool): 손잡이 표시 여부.
  // 반환값: MedBuddyOptionSheet: 구성된 시트.
  const MedBuddyOptionSheet({
    super.key,
    required this.children,
    this.showHandle = true,
  });

  // 함수이름: build
  // 함수역할: 손잡이 표시 설정에 따라 여백·안전 영역을 적용한 스크롤 시트를 만든다.
  // 매개변수: context (BuildContext): 빌드 문맥.
  // 반환값: Widget: 자식 목록을 포함한 시트.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: showHandle,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHandle)
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: MedBuddyColors.outline,
                  borderRadius: MedBuddyRadii.pill,
                ),
              ),
            if (showHandle) const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}

// Class Name: MedBuddyOptionTile
// Role: Represents one tappable choice with an icon, title and explanation.
// Responsibilities:
// - Scales both text lines with the user's content text setting.
// - Runs the caller's action when selected.
// Attributes:
// - icon (IconData): Leading choice icon.
// - title (String): Choice name.
// - subtitle (String): What the choice does.
// - onTap (VoidCallback): Selection action.
// - inkKey (Key?): Optional key for the tappable area.
class MedBuddyOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Key? inkKey;

  // Function Name: MedBuddyOptionTile
  // Description: Stores the choice content and selection action.
  // Parameters:
  // - icon, title, subtitle: Displayed choice content.
  // - onTap (VoidCallback): Selection action.
  // - inkKey (Key?): Optional key for the tappable area.
  // Returns: A configured MedBuddyOptionTile.
  const MedBuddyOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.inkKey,
  });

  // Function Name: build
  // Description: Renders the icon, two text lines and a chevron on a tinted row.
  // Parameters:
  // - context (BuildContext): Widget tree location.
  // Returns: The tappable choice row.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: MedBuddyColors.successSurface,
      borderRadius: MedBuddyRadii.card,
      child: InkWell(
        key: inkKey,
        borderRadius: MedBuddyRadii.card,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: Border.all(color: MedBuddyColors.successBorder),
          ),
          child: Row(
            children: [
              Icon(icon, color: MedBuddyColors.primary, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeepWordsText(
                      title,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    KeepWordsText(
                      subtitle,
                      style: TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: MedBuddyColors.primary,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
