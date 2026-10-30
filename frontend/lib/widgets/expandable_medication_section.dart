import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 검토·결과 화면에서 같은 펼침 버튼을 쓰고 저장 상태 갱신 중에도 펼침 상태를 유지한다.
class ExpandableMedicationSection extends StatefulWidget {
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

  @override
  State<ExpandableMedicationSection> createState() =>
      _ExpandableMedicationSectionState();
}

class _ExpandableMedicationSectionState
    extends State<ExpandableMedicationSection>
    with AutomaticKeepAliveClientMixin {
  late bool _expanded = widget.initiallyExpanded;

  @override
  bool get wantKeepAlive => true;

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
class MedicationExpandToggle extends StatelessWidget {
  const MedicationExpandToggle({
    super.key,
    required this.expanded,
    required this.tooltip,
    required this.onPressed,
  });

  final bool expanded;
  final String tooltip;
  final VoidCallback? onPressed;

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
