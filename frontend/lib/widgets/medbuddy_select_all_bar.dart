// 파일명: medbuddy_select_all_bar.dart
// 역할: 알림함과 채팅 첨부용 약 선택 화면이 함께 쓰는 전체·일부·미선택 체크박스 줄을 제공한다.

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 클래스명: MedBuddySelectAllBar
// 역할: 목록 위에서 전체 선택 체크박스와 현재 선택 개수를 나란히 표시한다.
// 주요 책임:
// - 아무것도 고르지 않으면 해제, 모두 고르면 선택, 일부만 고르면 중간 상태로 체크박스를 표시한다.
// - 큰 글씨에서는 선택 개수만 다음 줄로 옮겨 전체 선택 문구를 자르지 않는다.
// 속성 :
//   - tileKey : 체크박스 줄의 위젯 키 (Key)
//   - label : 전체 선택 문구 (String)
//   - countLabel : 선택 개수 문구 (String)
//   - countKey : 선택 개수 문구의 위젯 키 (Key)
//   - selectedCount : 현재 선택한 항목 수 (int)
//   - totalCount : 선택할 수 있는 전체 항목 수 (int)
//   - onToggleAll : 전체 선택·해제 콜백; null이면 체크박스를 비활성화한다 (VoidCallback?)
class MedBuddySelectAllBar extends StatelessWidget {
  final Key tileKey;
  final String label;
  final String countLabel;
  final Key countKey;
  final int selectedCount;
  final int totalCount;
  final VoidCallback? onToggleAll;

  // 함수이름: MedBuddySelectAllBar
  // 함수역할: 전체 선택 줄에 표시할 문구, 키, 선택 개수와 전환 콜백을 받는다.
  // 매개변수:
  // - key (Key?): 위젯 식별 키.
  // - tileKey (Key): 체크박스 줄의 위젯 키.
  // - label (String): 전체 선택 문구.
  // - countLabel (String): 선택 개수 문구.
  // - countKey (Key): 선택 개수 문구의 위젯 키.
  // - selectedCount (int): 현재 선택한 항목 수.
  // - totalCount (int): 선택할 수 있는 전체 항목 수.
  // - onToggleAll (VoidCallback?): 전체 선택·해제 콜백; null이면 비활성화한다.
  // 반환값: 입력 설정이 반영된 MedBuddySelectAllBar 인스턴스.
  const MedBuddySelectAllBar({
    super.key,
    required this.tileKey,
    required this.label,
    required this.countLabel,
    required this.countKey,
    required this.selectedCount,
    required this.totalCount,
    required this.onToggleAll,
  });

  // 함수이름: build
  // 함수역할: 전체 선택 체크박스와 개수를 나란히 배치하고 큰 글씨에서는 줄바꿈한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정을 참조할 위젯 트리 위치.
  // 반환값: 전체 선택 줄 위젯 트리.
  @override
  Widget build(BuildContext context) => Material(
    color: MedBuddyColors.surfaceSubtle,
    shape: const Border(bottom: BorderSide(color: MedBuddyColors.divider)),
    child: CheckboxListTile(
      key: tileKey,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: MedBuddySpacing.pageHorizontal,
        vertical: 8,
      ),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: MedBuddyColors.primary,
      checkColor: MedBuddyColors.surface,
      checkboxShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      tristate: true,
      value: selectedCount == 0
          ? false
          : selectedCount == totalCount
          ? true
          : null,
      onChanged: onToggleAll == null ? null : (_) => onToggleAll!(),
      title: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.35,
              letterSpacing: 0,
              color: MedBuddyColors.textStrong,
            ),
          ),
          Text(
            countLabel,
            key: countKey,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.35,
              letterSpacing: 0,
              color: selectedCount == 0
                  ? MedBuddyColors.textMuted
                  : MedBuddyColors.primaryDark,
            ),
          ),
        ],
      ),
    ),
  );
}
