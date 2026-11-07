import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 파일명: medbuddy_bottom_navigation_ui_boundary.dart
// 역할: 고정 목적지와 조건부 채팅 탭의 하단 탐색을 구성한다.

// Class Name: MedBuddyDestination
// Role: Top-level destinations with an optional linked-chat tab.
// Responsibilities: Names home, schedule, medication history, chat and profile routes for navigation callbacks.
// Attributes: home/schedule/medicationHistory/chat/profile: destination values.
enum MedBuddyDestination { home, schedule, medicationHistory, chat, profile }

// 하단 탭 레이블 글자 크기. 어르신이 읽을 수 있게 13pt로 두고 사용자 글자 크기 배율을 그대로 적용한다.
const double _labelFontSize = 13;

// Class Name: MedBuddyBottomNavigationUI
// Role: Represents fixed bottom navigation with selected-state and accessibility cues.
// Responsibilities:
// - Distinguishes the selected destination by color and background.
// - Provides an icon and label for each destination.
// - Respects the Android bottom safe area and minimum touch targets.
// Attributes:
// - selectedDestination (MedBuddyDestination): Top-level navigation destination to display or select.
// - language (String): Language code selecting visible wording.
// - showChat (bool): Whether the linked-chat destination is included.
// - onDestinationSelected (ValueChanged<MedBuddyDestination>): Callback reporting the selected top-level destination.
class MedBuddyBottomNavigationUI extends StatelessWidget {
  final MedBuddyDestination selectedDestination;
  final String language;
  final bool showChat;
  final ValueChanged<MedBuddyDestination> onDestinationSelected;

  // 함수이름: MedBuddyBottomNavigationUI
  // 함수역할: 선택 상태와 접근성을 지원하는 네 개 또는 다섯 개의 하단 탭을 구성한다.
  // 매개변수: key, selectedDestination, language: 식별자·선택 목적지·언어.
  // - showChat: 채팅 탭 노출 여부, onDestinationSelected: 목적지 선택 콜백.
  // 반환값: 탐색 막대 UI.
  const MedBuddyBottomNavigationUI({
    super.key,
    required this.selectedDestination,
    required this.language,
    this.showChat = false,
    required this.onDestinationSelected,
  });

  // Function Name: build
  // Description: Includes chat only when enabled and gives all destinations a common height measured from scaled single-line labels.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    final text = _BottomNavigationText(language);
    final items = <_BottomNavigationItem>[
      _BottomNavigationItem(
        destination: MedBuddyDestination.home,
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: text.home,
      ),
      _BottomNavigationItem(
        destination: MedBuddyDestination.schedule,
        icon: Icons.calendar_today_outlined,
        selectedIcon: Icons.calendar_month_rounded,
        label: text.schedule,
      ),
      _BottomNavigationItem(
        destination: MedBuddyDestination.medicationHistory,
        icon: Icons.event_note_outlined,
        selectedIcon: Icons.event_note_rounded,
        label: text.medicationHistory,
      ),
      _BottomNavigationItem(
        destination: MedBuddyDestination.chat,
        icon: Icons.chat_bubble_outline_rounded,
        selectedIcon: Icons.chat_bubble_rounded,
        label: text.chat,
      ),
      _BottomNavigationItem(
        destination: MedBuddyDestination.profile,
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        label: text.profile,
      ),
    ];
    if (!showChat) {
      items.removeAt(3);
    }

    return LayoutBuilder(
      // 함수이름: 탐색 막대 builder
      // 함수역할: 표시할 탭의 너비와 글씨 배율로 공통 높이를 계산해 아이콘과 한 줄 문구를 정렬한다.
      // 매개변수: context, constraints: 표시 문맥과 탐색 막대 크기. 반환값: 탐색 막대.
      builder: (context, constraints) {
        final height = _navigationHeight(context, constraints.maxWidth, items);
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: MedBuddyColors.surface,
            border: Border(top: BorderSide(color: MedBuddyColors.divider)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: MedBuddyShadows.card,
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: _BottomNavigationButton(
                        item: item,
                        selected: item.destination == selectedDestination,
                        labelHeight: height - 58,
                        // Function Name: build.onPressed callback
                        // Description: Connects fixed bottom navigation with selected-state and accessibility cues to the captured operation `onDestinationSelected(item.destination)`.
                        // Parameters:
                        // - None.
                        // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                        onPressed: () =>
                            onDestinationSelected(item.destination),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 함수이름: _navigationHeight
  // 함수역할: 표시할 각 레이블의 한 줄 높이를 현재 글씨 배율로 측정해 아이콘 여백을 포함한 최대 높이를 구한다.
  // 매개변수: context, width, items: 표시 문맥, 전체 너비, 표시할 목적지.
  // 반환값: 레이블과 아이콘을 포함하는 공통 높이.
  double _navigationHeight(
    BuildContext context,
    double width,
    List<_BottomNavigationItem> items,
  ) {
    final labelWidth = ((width - 20) / items.length - 14).clamp(1.0, width);
    var height = 70.0;
    for (final item in items) {
      final painter = TextPainter(
        maxLines: 1,
        text: TextSpan(
          text: item.label,
          style: const TextStyle(
            fontSize: _labelFontSize,
            height: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: labelWidth);
      if (painter.height + 58 > height) height = painter.height + 58;
      painter.dispose();
    }
    return height;
  }
}

// Class Name: _BottomNavigationButton
// Role: Represents a navigation destination with icon, label, and selected state.
// Responsibilities:
// - Composes a navigation destination with icon, label, and selected state using the display values and actions supplied by its parent.
// Attributes:
// - item (_BottomNavigationItem): Destination, icon, and label definition for this navigation button.
// - selected (bool): Whether the item belongs to the current selection.
// - labelHeight (double): Shared label-region height used to align all destinations.
// - onPressed (VoidCallback): Callback executing the item's documented primary action.
class _BottomNavigationButton extends StatelessWidget {
  final _BottomNavigationItem item;
  final bool selected;
  final double labelHeight;
  final VoidCallback onPressed;

  // 함수이름: _BottomNavigationButton
  // 함수역할: 하단 탐색 항목의 아이콘·문구·선택 상태와 이동 동작을 받는다.
  // 매개변수: item (_BottomNavigationItem): 목적지 표시 정보; selected (bool): 현재 선택 여부; labelHeight (double): 한 줄 문구를 정렬할 공통 영역 높이; onPressed (VoidCallback): 목적지 이동.
  // 반환값: 새 _BottomNavigationButton.
  const _BottomNavigationButton({
    required this.item,
    required this.selected,
    required this.labelHeight,
    required this.onPressed,
  });

  // Function Name: build
  // Description: Shows the selected icon and accessible destination label, aligning a single-line label in the shared height and scaling it down only when it exceeds the available width.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? MedBuddyColors.primaryDark
        : MedBuddyColors.textSubtle;

    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: selected ? MedBuddyColors.mint : Colors.transparent,
          borderRadius: MedBuddyRadii.largeCard,
          child: InkWell(
            key: ValueKey('bottomNavigation-${item.destination.name}'),
            borderRadius: MedBuddyRadii.largeCard,
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.scale(
                      scale:
                          item.destination ==
                              MedBuddyDestination.medicationHistory
                          ? 1.125
                          : 1,
                      child: Icon(
                        selected ? item.selectedIcon : item.icon,
                        color: foreground,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: labelHeight,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            item.label,
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: foreground,
                              fontSize: _labelFontSize,
                              height: 1.1,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Class Name: _BottomNavigationItem
// Role: Represents a navigation destination's icon and label definition.
// Responsibilities:
// - Groups the supplied field values for a navigation destination's icon and label definition in a single object.
// Attributes:
// - destination (MedBuddyDestination): Top-level navigation destination to display or select.
// - icon (IconData): Icon shown in normal or selected state.
// - selectedIcon (IconData): Icon shown in normal or selected state.
// - label (String): Wording identifying a field, choice, or action.
class _BottomNavigationItem {
  final MedBuddyDestination destination;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  // Function Name: _BottomNavigationItem
  // Description: Combines the supplied values for a navigation destination's icon and label definition in a _BottomNavigationItem instance.
  // Parameters:
  // - destination (MedBuddyDestination): Top-level navigation destination to display or select.
  // - icon (IconData): Icon shown in normal or selected state.
  // - selectedIcon (IconData): Icon shown in normal or selected state.
  // - label (String): Wording identifying a field, choice, or action.
  // Returns: Initialized _BottomNavigationItem instance.
  const _BottomNavigationItem({
    required this.destination,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

// Class Name: _BottomNavigationText
// Role: Supplies localized labels for home, schedule, medication records, chat, and profile destinations.
// Responsibilities:
// - Uses the normalized language prefix to select English or Korean destination labels.
// Attributes:
// - language (String): Language code selecting visible wording.
class _BottomNavigationText {
  final String language;

  // Function Name: _BottomNavigationText
  // Description: Stores the language code used by all five destination-label getters.
  // Parameters:
  // - language (String): Language code selecting visible wording.
  // Returns: Initialized _BottomNavigationText instance.
  const _BottomNavigationText(this.language);

  // Function Name: isEnglish
  // Description: Recognizes English locale prefixes after trimming and lowercasing the language code.
  // Parameters:
  // - None.
  // Returns: True when the documented condition holds; false otherwise.
  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  // Function Name: home
  // Description: Provides localized wording for "Home" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get home => isEnglish ? 'Home' : '홈';
  // 함수이름: chat
  // 함수역할: 채팅 탭의 한영 레이블을 선택한다.
  // 매개변수: 없음. 반환값: 채팅 탭 이름.
  String get chat => isEnglish ? 'Chat' : '채팅';
  // Function Name: schedule
  // Description: Provides localized wording for "Schedule" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get schedule => isEnglish ? 'Schedule' : '일정';
  // Function Name: medicationHistory
  // Description: Labels the medication-records destination in bottom navigation.
  // Parameters:
  // - None.
  // Returns: The localized medication-history navigation label.
  String get medicationHistory => isEnglish ? 'Records' : '복약 기록';
  // Function Name: profile
  // Description: Provides localized wording for "My Info" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get profile => isEnglish ? 'My Info' : '내 정보';
}
