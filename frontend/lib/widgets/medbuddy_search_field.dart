// 파일명: medbuddy_search_field.dart
// 역할: 앱의 검색 입력과 결과 패널에 공통 표시·입력 동작을 제공한다.
// 기능·진료과 검색의 입력창과 결과 테두리를 같은 형태로 유지한다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 클래스명: MedBuddySearchField
// 역할: 검색어 편집·지우기·제출 동작을 공통 입력창에 연결한다.
// 주요 책임: 120자 제한과 검색 키보드 동작을 제공하고 컨트롤러 변경을 호출자에 알린다.
// 속성: controller: 호출자 소유 입력 컨트롤러; label/hint: 입력 문구; onChanged/onSubmitted: 변경·제출 콜백; isEnglish: 언어; inputKey/clearKey: 선택 식별 키.
class MedBuddySearchField extends StatelessWidget {
  // 함수이름: MedBuddySearchField
  // 함수역할: 입력 컨트롤러와 검색 동작을 보관한다. 컨트롤러 수명은 호출자가 관리한다.
  // 매개변수: key/inputKey/clearKey: 식별 키; controller: 검색어; label/hint: 안내 문구; onChanged: 변경 통지; onSubmitted: 선택 제출; isEnglish: 지우기 문구 언어.
  // 반환값: 검색 입력 위젯.
  const MedBuddySearchField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.onChanged,
    required this.isEnglish,
    this.inputKey,
    this.clearKey,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback onChanged;
  final bool isEnglish;
  final Key? inputKey;
  final Key? clearKey;
  final VoidCallback? onSubmitted;

  // 함수이름: build
  // 함수역할: 입력·지우기 시 변경을 알리고 제출 시 키보드 포커스를 해제한 뒤 제출 콜백을 실행한다.
  // 매개변수: context (BuildContext): 포커스 조회에 사용할 위젯 위치.
  // 반환값: 최대 120자 TextField. 입력이 비어 있으면 지우기 버튼을 숨긴다.
  @override
  Widget build(BuildContext context) => TextField(
    key: inputKey,
    controller: controller,
    maxLength: 120,
    style: MedBuddyTextStyles.menuBody,
    textInputAction: TextInputAction.search,
    onChanged: (_) => onChanged(),
    onSubmitted: (_) {
      FocusScope.of(context).unfocus();
      onSubmitted?.call();
    },
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      counterText: '',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: controller.text.isNotEmpty
          ? IconButton(
              key: clearKey,
              tooltip: isEnglish ? 'Clear search' : '검색어 지우기',
              onPressed: () {
                controller.clear();
                onChanged();
              },
              icon: const Icon(Icons.close),
            )
          : null,
    ),
  );
}

// 클래스명: MedBuddySearchPanel
// 역할: 검색 결과를 공통 테두리 안에 표시한다.
// 주요 책임: 자식의 터치 효과가 보이는 Material 표면과 모서리 클리핑을 제공한다.
// 속성: child (Widget): 검색 결과 내용.
class MedBuddySearchPanel extends StatelessWidget {
  // 함수이름: MedBuddySearchPanel
  // 함수역할: 표시할 결과 위젯을 패널에 연결한다.
  // 매개변수: key (Key?): 식별 키; child (Widget): 결과 내용.
  // 반환값: 상태 없는 검색 결과 패널.
  const MedBuddySearchPanel({super.key, required this.child});

  final Widget child;

  // 안의 목록 터치 효과가 보이도록 장식 상자가 아닌 Material로 그린다.
  // Function Name: build
  // Description: Uses a clipped outlined Material surface so descendant ink responses remain visible.
  // Parameters: context (BuildContext): Current widget context.
  // Returns: The supplied child within the shared search-panel shape and surface color.
  @override
  Widget build(BuildContext context) => Material(
    color: MedBuddyColors.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: MedBuddyRadii.card,
      side: const BorderSide(color: MedBuddyColors.outline),
    ),
    child: child,
  );
}
