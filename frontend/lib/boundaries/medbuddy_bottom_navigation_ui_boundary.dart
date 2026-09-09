import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 파일명: medbuddy_bottom_navigation_ui_boundary.dart
// 역할: 고정 목적지와 조건부 채팅 탭의 하단 탐색을 구성한다.

// 클래스명: MedBuddyDestination
// 역할: 고정 목적지와 활성 연동이 있을 때만 노출하는 채팅 목적지를 구분한다.
enum MedBuddyDestination { home, schedule, medicationCabinet, chat, profile }

// Class Name: MedBuddyBottomNavigationUI
// Role: Represents fixed bottom navigation with selected-state and accessibility cues.
// Responsibilities:
// - Distinguishes the selected destination by color and background.
// - Provides an icon and label for each destination.
// - Respects the Android bottom safe area and minimum touch targets.
// Attributes:
// - selectedDestination (MedBuddyDestination): Top-level navigation destination to display or select.
// - language (String): Language code selecting visible wording.
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

  // 함수이름: build
  // 함수역할: 채팅 노출 여부에 맞춰 항목을 구성하고 큰 글씨의 줄바꿈 높이를 확보한다.
  // 매개변수: context: 테마·언어·글씨 배율 문맥. 반환값: 하단 탐색 막대.
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
        destination: MedBuddyDestination.medicationCabinet,
        icon: Icons.medication_outlined,
        selectedIcon: Icons.medication_rounded,
        label: text.medicationCabinet,
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
      // 함수역할: 실제 항목 너비와 글씨 배율로 필요한 높이를 계산해 다섯 탭의 줄바꿈을 보존한다.
      // 매개변수: context, constraints: 표시 문맥과 탐색 막대 크기. 반환값: 탐색 막대.
      builder: (context, constraints) => DecoratedBox(
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
            height: _navigationHeight(context, constraints.maxWidth, items),
            child: Row(
              children: [
                for (final item in items)
                  Expanded(
                    child: _BottomNavigationButton(
                      item: item,
                      selected: item.destination == selectedDestination,
                      // Function Name: build.onPressed callback
                      // Description: Connects fixed bottom navigation with selected-state and accessibility cues to the captured operation `onDestinationSelected(item.destination)`.
                      // Parameters:
                      // - None.
                      // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                      onPressed: () => onDestinationSelected(item.destination),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 함수이름: _navigationHeight
  // 함수역할: 모든 레이블의 줄바꿈 높이를 측정해 선택 상태나 글씨 크기로 잘리지 않도록 한다.
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
        text: TextSpan(
          text: item.label,
          style: const TextStyle(
            fontSize: 11,
            height: 1.1,
            fontWeight: FontWeight.w800,
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
// - onPressed (VoidCallback): Callback executing the item's documented primary action.
class _BottomNavigationButton extends StatelessWidget {
  final _BottomNavigationItem item;
  final bool selected;
  final VoidCallback onPressed;

  // Function Name: _BottomNavigationButton
  // Description: Initializes a navigation destination with icon, label, and selected state with the supplied configuration.
  // Parameters:
  // - item (_BottomNavigationItem): Destination, icon, and label definition for this navigation button.
  // - selected (bool): Whether the item belongs to the current selection.
  // - onPressed (VoidCallback): Callback executing the item's documented primary action.
  // Returns: Initialized _BottomNavigationButton instance.
  const _BottomNavigationButton({
    required this.item,
    required this.selected,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 목적지 아이콘·선택 상태와 글씨 배율을 보존하는 다중 행 레이블을 표시한다.
  // 매개변수: context: 테마·접근성 문맥. 반환값: 목적지 선택 버튼.
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
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            key: ValueKey('bottomNavigation-${item.destination.name}'),
            borderRadius: BorderRadius.circular(22),
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      selected ? item.selectedIcon : item.icon,
                      color: foreground,
                      size: 24,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
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
// Role: Represents localized wording for bottom navigation between Home, Schedule, Pillbox, and My Info.
// Responsibilities:
// - Selects Korean or English labels and interpolates message values for localized wording for bottom navigation between Home, Schedule, Pillbox, and My Info.
// Attributes:
// - language (String): Language code selecting visible wording.
class _BottomNavigationText {
  final String language;

  // Function Name: _BottomNavigationText
  // Description: Stores the language used to select localized wording for bottom navigation between Home, Schedule, Pillbox, and My Info.
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
  // Function Name: medicationCabinet
  // Description: Provides localized wording for "Medications" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get medicationCabinet => isEnglish ? 'Medications' : '복약함';
  // Function Name: profile
  // Description: Provides localized wording for "My Info" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get profile => isEnglish ? 'My Info' : '내 정보';
}
