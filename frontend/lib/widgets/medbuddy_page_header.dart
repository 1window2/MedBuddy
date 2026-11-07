import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';

// 파일명: medbuddy_page_header.dart
// 역할: 오늘의 복약 일정과 동일한 초록색 헤더·제목·탐색 명령을 제공한다.

// 클래스명: MedBuddyPageHeader
// 역할: 페이지 제목·뒤로 가기·작업 버튼을 공통 상단 영역으로 배치한다.
// 주요 책임: 안전 영역과 큰 글씨 배치를 반영하고 사용자 지정 leading·bottom을 지원한다.
// 속성: title/subtitle: 표시 문구; onBackRequested/actions/leading/bottom: 탐색·추가 UI; 툴팁·키·줄 수: 접근성 및 배치 설정; titleStyle/titleStrutStyle: 공통 제목 서식.
class MedBuddyPageHeader extends StatelessWidget {
  // 일정 화면도 같은 줄 높이를 사용해 한글·영문 제목의 시작점과 기준선을 맞춘다.
  static const titleStyle = TextStyle(
    color: Colors.white,
    fontSize: 21,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0,
  );
  static const titleStrutStyle = StrutStyle(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    height: 1.3,
    leadingDistribution: TextLeadingDistribution.even,
    forceStrutHeight: true,
  );
  // 함수이름: MedBuddyPageHeader
  // 함수역할: 제목·부제·탐색 동작과 추가 위젯을 보관하여 공통 상단 영역을 구성한다.
  // 매개변수: title (String)/subtitle (String?): 제목·부제; onBackRequested (VoidCallback?): 뒤로 가기; actions (List<Widget>): 작업 버튼; prominent (bool): 상위 화면 표시값(현재 빌드에는 미사용); backTooltip (String?): 접근성 뒤로 가기 문구; backButtonKey/titleKey/key (Key?): 버튼·제목·위젯 식별자; leading/bottom (Widget?): 선행·하단 추가 내용; titleMaxLines/subtitleMaxLines (int?): 제목·부제 줄 제한.
  // 반환값: MedBuddyPageHeader: 구성된 헤더 위젯.
  const MedBuddyPageHeader({
    required this.title,
    this.subtitle,
    this.onBackRequested,
    this.actions = const [],
    this.prominent = false,
    this.backTooltip,
    this.backButtonKey,
    this.leading,
    this.titleKey,
    this.titleMaxLines,
    this.subtitleMaxLines,
    this.bottom,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBackRequested;
  final List<Widget> actions;
  final bool prominent;
  final String? backTooltip;
  final Key? backButtonKey;
  final Widget? leading;
  final Key? titleKey;
  // 사용자 입력인 채팅 별칭만 줄 수를 제한하고 화면 제목은 필요한 만큼 줄바꿈한다.
  final int? titleMaxLines;
  final int? subtitleMaxLines;
  final Widget? bottom;

  // Function Name: build
  // Description: Build the header with optional leading/back control, subtitle and bottom content; stack multiple actions on narrow layouts with large text.
  // Parameters: context (BuildContext): theme, localization and text scale source.
  // Returns: Widget: safe-area page header.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: MedBuddyColors.topBar,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Theme(
            data: theme.copyWith(
              iconTheme: const IconThemeData(color: Colors.white),
              iconButtonTheme: IconButtonThemeData(
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white54,
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stackActions =
                    actions.length > 1 &&
                    constraints.maxWidth < 360 &&
                    MediaQuery.textScalerOf(context).scale(16) > 20;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (leading != null) ...[
                            SizedBox(width: 48, height: 48, child: leading),
                            const SizedBox(width: 8),
                          ] else if (onBackRequested != null) ...[
                            Semantics(
                              label:
                                  backTooltip ??
                                  MaterialLocalizations.of(
                                    context,
                                  ).backButtonTooltip,
                              button: true,
                              onTap: onBackRequested,
                              excludeSemantics: true,
                              child: IconButton(
                                key: backButtonKey,
                                tooltip:
                                    backTooltip ??
                                    MaterialLocalizations.of(
                                      context,
                                    ).backButtonTooltip,
                                onPressed: onBackRequested,
                                constraints: const BoxConstraints.tightFor(
                                  width: 48,
                                  height: 48,
                                ),
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ] else
                            const SizedBox(width: 12),
                          Expanded(
                            // 버튼의 터치 영역과 무관하게 제목 바로 아래에 설명을 배치한다.
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  key: titleKey,
                                  maxLines: titleMaxLines,
                                  overflow: titleMaxLines == null
                                      ? null
                                      : TextOverflow.ellipsis,
                                  style: titleStyle,
                                  strutStyle: titleStrutStyle,
                                ),
                                if (subtitle != null &&
                                    subtitle!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  KeepWordsText(
                                    subtitle!,
                                    maxLines: subtitleMaxLines,
                                    overflow: subtitleMaxLines == null
                                        ? null
                                        : TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: MedBuddyColors.onPrimaryMuted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (actions.isNotEmpty && !stackActions) ...[
                            const SizedBox(width: 8),
                            ...actions,
                          ],
                        ],
                      ),
                    ),
                    if (stackActions)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions,
                      ),
                    ?bottom,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
