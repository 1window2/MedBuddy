// 파일명: medbuddy_choice_sheet.dart
// 역할: 두세 가지 중 하나를 고르는 아래쪽 시트. 큰 아이콘과 이름만 있는 큰 타일을 나란히 둔다.
//   카메라·갤러리 선택이 쓴다.

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';

// 클래스명: MedBuddyChoice
// 역할: 시트의 선택지 하나.
// 속성: value: 고르면 돌려줄 값; icon·label: 표시; tileKey: 테스트·접근성용 키.
class MedBuddyChoice<T> {
  final T value;
  final IconData icon;
  final String label;
  final Key? tileKey;

  const MedBuddyChoice({
    required this.value,
    required this.icon,
    required this.label,
    this.tileKey,
  });
}

// 함수이름: showMedBuddyChoiceSheet
// 함수역할: 제목과 큰 선택 타일이 있는 시트를 열고 고른 값을 돌려준다. 두 번 눌러도 한 번만 닫는다.
// 매개변수: context: 위치; title: 질문; choices: 선택지(2~3개).
// 반환값: 고른 값, 닫으면 null.
Future<T?> showMedBuddyChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required List<MedBuddyChoice<T>> choices,
}) {
  var responded = false;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MedBuddyColors.surface,
    showDragHandle: true,
    builder: (sheetContext) {
      void select(T value) {
        if (responded || ModalRoute.of(sheetContext)?.isCurrent != true) {
          return;
        }
        responded = true;
        Navigator.pop(sheetContext, value);
      }

      final scale = MediaQuery.textScalerOf(sheetContext).scale(16) / 16;
      final stacked = scale > 1.3;
      final tiles = [
        for (final choice in choices)
          _ChoiceTile(
            key: choice.tileKey,
            icon: choice.icon,
            label: choice.label,
            horizontal: stacked,
            onTap: () => select(choice.value),
          ),
      ];
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeepWordsText(
                title,
                style: const TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 18),
              if (stacked)
                for (final tile in tiles) ...[
                  tile,
                  if (tile != tiles.last) const SizedBox(height: 12),
                ]
              else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final tile in tiles) ...[
                        Expanded(child: tile),
                        if (tile != tiles.last) const SizedBox(width: 12),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

// 클래스명: _ChoiceTile
// 역할: 큰 선택 타일. 보통은 아이콘 위·이름 아래, 아주 큰 글씨에서는 가로로 놓는다.
class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool horizontal;
  final VoidCallback onTap;

  const _ChoiceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.horizontal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconBox = Container(
      width: 84,
      height: 84,
      decoration: const BoxDecoration(
        color: MedBuddyColors.surface,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: MedBuddyColors.primary, size: 50),
    );
    final text = KeepWordsText(
      label,
      textAlign: horizontal ? TextAlign.start : TextAlign.center,
      style: const TextStyle(
        color: MedBuddyColors.textStrong,
        fontSize: 19,
        fontWeight: FontWeight.w800,
        height: 1.3,
      ),
    );
    return Material(
      color: MedBuddyColors.successSurface,
      borderRadius: MedBuddyRadii.largeCard,
      child: InkWell(
        onTap: onTap,
        borderRadius: MedBuddyRadii.largeCard,
        child: Container(
          constraints: BoxConstraints(minHeight: horizontal ? 104 : 172),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.largeCard,
            border: Border.all(color: MedBuddyColors.successBorder, width: 1.5),
          ),
          child: horizontal
              ? Row(
                  children: [
                    iconBox,
                    const SizedBox(width: 16),
                    Expanded(child: text),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [iconBox, const SizedBox(height: 14), text],
                ),
        ),
      ),
    );
  }
}
