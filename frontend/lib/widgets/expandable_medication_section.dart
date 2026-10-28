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
          Semantics(
            expanded: _expanded,
            child: IconButton(
              key: widget.toggleKey,
              tooltip: label,
              onPressed: () => setState(() => _expanded = !_expanded),
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              color: MedBuddyColors.primaryDark,
              icon: Icon(
                _expanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 28,
              ),
            ),
          ),
        ),
        if (_expanded) widget.details,
      ],
    );
  }
}
