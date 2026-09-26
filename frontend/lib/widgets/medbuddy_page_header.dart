import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 파일명: medbuddy_page_header.dart
// 역할: 오늘의 복약 일정과 동일한 초록색 헤더·제목·탐색 명령을 제공한다.

// 클래스명: MedBuddyPageHeader
// 역할: 화면별 동작은 유지하면서 제목과 안전 영역의 시각적 기준을 통일한다.
class MedBuddyPageHeader extends StatelessWidget {
  // 일정 화면도 같은 줄 높이를 사용해 한글·영문 제목의 시작점과 기준선을 맞춘다.
  static const titleStyle = TextStyle(
    color: Colors.white,
    fontSize: 21,
    fontWeight: FontWeight.w800,
    height: 1.3,
    letterSpacing: 0,
  );
  static const titleStrutStyle = StrutStyle(
    fontSize: 21,
    fontWeight: FontWeight.w800,
    height: 1.3,
    leadingDistribution: TextLeadingDistribution.even,
    forceStrutHeight: true,
  );
  // 함수이름: MedBuddyPageHeader
  // 함수역할: 제목·부제·탐색 명령을 받아 공통 헤더를 초기화한다.
  // 매개변수: prominent는 최상위 화면 여부, titleKey는 제목 식별자이다.
  // 반환값: 안전 영역과 큰 글씨에 대응하는 헤더 위젯.
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

  // 함수이름: build
  // 함수역할: 일정 화면의 색상·21px 제목·하단 라운드를 적용하고 좁은 화면의 도구는 아래 줄에 배치한다.
  // 매개변수: context는 테마·글씨 배율·안전 영역을 제공한다.
  // 반환값: 상단 안전 영역을 포함한 헤더. 부모는 상단 SafeArea를 중복 적용하지 않는다.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF249B62), MedBuddyColors.topBar],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
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
                                  Text(
                                    subtitle!,
                                    maxLines: subtitleMaxLines,
                                    overflow: subtitleMaxLines == null
                                        ? null
                                        : TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFD6F2E3),
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
