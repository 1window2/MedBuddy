// File Name: responsive_card_header.dart
// Role: Stacks card actions below the title when narrow layouts and large text require more room.
import 'package:flutter/material.dart';

// 좁은 화면의 큰 글씨에서만 동작 영역을 제목 아래 오른쪽으로 내려 제목 폭을 지킨다.
// 동작 영역이 배치 방식이나 폭에 따라 달라지면 builder 생성자를 사용한다.
// Function Name: ResponsiveCardHeaderActionsBuilder
// Description: Builds actions using the header's selected layout and available width.
// Parameters: context (BuildContext): Header context; isStacked (bool): Actions placed below title; maxWidth (double): Available width.
// Returns: Action widget suitable for that layout.
typedef ResponsiveCardHeaderActionsBuilder =
    Widget Function(BuildContext context, bool isStacked, double maxWidth);

// Class Name: ResponsiveCardHeader
// Role: Protects title width by moving actions below it on narrow large-text layouts.
// Responsibilities: Choose one-row or stacked placement and support prebuilt or layout-aware actions.
// Attributes: title (Widget): Heading; titleFontSize/spacing (double): Scale reference and row gap; _actions/_actionsBuilder: Exclusive action sources.
class ResponsiveCardHeader extends StatelessWidget {
  // title: 남은 폭을 차지할 제목, actions: 제목 옆 또는 아래 오른쪽에 둘 동작 영역,
  // titleFontSize: 확대 여부를 판단할 제목 기준 글자 크기, spacing: 한 줄 배치에서 제목과 동작 사이 간격.
  // Function Name: ResponsiveCardHeader
  // Description: Configures prebuilt actions that can move beside or below the title.
  // Parameters: key (Key?): Identity; title/actions (Widget): Header content; titleFontSize (double): Scaling reference; spacing (double): Positive row gap.
  // Returns: Responsive header using the supplied action widget.
  const ResponsiveCardHeader({
    super.key,
    required this.title,
    required Widget actions,
    this.titleFontSize = 18,
    this.spacing = 0,
  }) : _actions = actions,
       _actionsBuilder = null;

  // actionsBuilder: 배치 방식(isStacked)과 머리글 최대 폭으로 동작 영역을 만든다.
  // Function Name: ResponsiveCardHeader.builder
  // Description: Defers action construction until the header knows its layout and width.
  // Parameters: key (Key?): Identity; title (Widget): Heading; actionsBuilder: Layout-aware action factory; titleFontSize/spacing (double): Scale reference and row gap.
  // Returns: Responsive header using builder-created actions.
  const ResponsiveCardHeader.builder({
    super.key,
    required this.title,
    required ResponsiveCardHeaderActionsBuilder actionsBuilder,
    this.titleFontSize = 18,
    this.spacing = 0,
  }) : _actions = null,
       _actionsBuilder = actionsBuilder;

  final Widget title;
  final double titleFontSize;
  final double spacing;
  final Widget? _actions;
  final ResponsiveCardHeaderActionsBuilder? _actionsBuilder;

  // Function Name: build
  // Description: Stacks actions at the right below the title only below 340px when the scaled title exceeds 24px; otherwise uses a row.
  // Parameters: context (BuildContext): Provides the text scaler and inherited layout.
  // Returns: Header layout with title width preserved and optional spacing in row mode.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final isStacked =
          constraints.maxWidth < 340 &&
          MediaQuery.textScalerOf(context).scale(titleFontSize) > 24;
      final actions =
          _actions ??
          _actionsBuilder!(context, isStacked, constraints.maxWidth);
      if (isStacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            Align(alignment: Alignment.centerRight, child: actions),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: title),
          if (spacing > 0) SizedBox(width: spacing),
          actions,
        ],
      );
    },
  );
}
