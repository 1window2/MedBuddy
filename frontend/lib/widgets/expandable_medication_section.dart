// 파일명: expandable_medication_section.dart
// 역할: 복약 상세의 펼침 상태를 유지하고 접근 가능한 펼침 버튼을 공유한다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 검토·결과 화면에서 같은 펼침 버튼을 쓰고 저장 상태 갱신 중에도 펼침 상태를 유지한다.
// 클래스명: ExpandableMedicationSection
// 역할: 저장 상태 갱신과 목록 이동 중 복약 상세의 펼침 상태를 유지한다.
// 주요 책임: 공통 토글을 머리글 빌더에 제공하고 펼쳤을 때만 상세를 표시한다.
// 속성: initiallyExpanded/isEnglish (bool): 초기 상태·언어; toggleKey (Key): 토글 키; headerBuilder: 머리글 함수; details (Widget): 상세; expandLabel/collapseLabel (String?): 문구.
class ExpandableMedicationSection extends StatefulWidget {
  // 함수이름: ExpandableMedicationSection
  // 함수역할: 초기 펼침 상태와 머리글·상세 구성을 보관한다.
  // 매개변수: key/toggleKey: 위젯·버튼 키; initiallyExpanded/isEnglish: 초기 상태·언어; headerBuilder: 토글을 받는 빌더; details: 상세 위젯; expandLabel/collapseLabel: 선택 문구.
  // 반환값: 상세 섹션 위젯. 초기 상태는 State 생성 때만 읽는다.
  const ExpandableMedicationSection({
    super.key,
    required this.initiallyExpanded,
    required this.isEnglish,
    required this.toggleKey,
    required this.headerBuilder,
    required this.details,
    this.expandLabel,
    this.collapseLabel,
  });

  final bool initiallyExpanded;
  final bool isEnglish;
  final Key toggleKey;
  final Widget Function(Widget toggle) headerBuilder;
  final Widget details;
  final String? expandLabel;
  final String? collapseLabel;

  // 함수이름: createState
  // 함수역할: 이 섹션의 펼침 상태를 소유할 상태 객체를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _ExpandableMedicationSectionState.
  @override
  State<ExpandableMedicationSection> createState() =>
      _ExpandableMedicationSectionState();
}

// 클래스명: _ExpandableMedicationSectionState
// 역할: 사용자가 선택한 펼침 상태를 목록의 수명주기 동안 보관한다.
// 주요 책임: 초기 상태를 한 번 읽고 keep-alive와 토글 재구성을 처리한다.
// 속성: _expanded (bool): 현재 상세 표시 여부.
class _ExpandableMedicationSectionState
    extends State<ExpandableMedicationSection>
    with AutomaticKeepAliveClientMixin {
  late bool _expanded = widget.initiallyExpanded;

  // 함수이름: wantKeepAlive
  // 함수역할: 스크롤로 화면 밖에 나가도 펼침 선택을 유지하도록 요청한다.
  // 매개변수: 없음.
  // 반환값: 항상 true.
  @override
  bool get wantKeepAlive => true;

  // Function Name: build
  // Description: Maintains keep-alive state, supplies a localized expansion toggle, and includes details only while expanded.
  // Parameters: context (BuildContext): Current section context.
  // Returns: Header/details column; a tap updates only this section's expansion state.
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final defaultLabel = widget.isEnglish
        ? (_expanded ? 'Hide medication details' : 'Show medication details')
        : (_expanded ? '복약 정보 접기' : '복약 정보 펼치기');
    final label =
        (_expanded ? widget.collapseLabel : widget.expandLabel) ?? defaultLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.headerBuilder(
          MedicationExpandToggle(
            key: widget.toggleKey,
            expanded: _expanded,
            tooltip: label,
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
        ),
        if (_expanded) widget.details,
      ],
    );
  }
}

// 펼침 상태를 화면 읽기에 알리는 48dp 화살표 버튼이다. onPressed가 없으면 비활성 색으로 보인다.
// Class Name: MedicationExpandToggle
// Role: Presents an accessible fixed-size expansion control.
// Responsibilities: Expose expanded semantics and preserve a 48dp target, including disabled buttons.
// Attributes: expanded (bool): Current state; tooltip (String): Action label; onPressed (VoidCallback?): Tap handler.
class MedicationExpandToggle extends StatelessWidget {
  // Function Name: MedicationExpandToggle
  // Description: Configures an expansion button without managing the expanded state itself.
  // Parameters: key (Key?): Identity; expanded (bool): Current state; tooltip (String): Accessible action label; onPressed (VoidCallback?): Null disables taps.
  // Returns: A stateless toggle driven by its parent.
  const MedicationExpandToggle({
    super.key,
    required this.expanded,
    required this.tooltip,
    required this.onPressed,
  });

  final bool expanded;
  final String tooltip;
  final VoidCallback? onPressed;

  // Function Name: build
  // Description: Renders the up/down arrow with expanded semantics and the configured tooltip and callback.
  // Parameters: context (BuildContext): Current widget context.
  // Returns: A semantic 48x48 IconButton; null callbacks leave it disabled.
  @override
  Widget build(BuildContext context) => Semantics(
    expanded: expanded,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      color: MedBuddyColors.primaryDark,
      icon: Icon(
        expanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
        size: 28,
      ),
    ),
  );
}
