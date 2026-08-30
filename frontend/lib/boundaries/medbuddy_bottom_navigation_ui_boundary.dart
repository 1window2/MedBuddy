import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 파일명: medbuddy_bottom_navigation_ui_boundary.dart
// 역할: MedBuddy의 주요 목적지 사이를 이동하는 공통 하단 탐색 UI를 구성한다.

// 열거형명: MedBuddyDestination
// 역할: 하단 탐색 막대에서 선택할 수 있는 앱의 최상위 목적지를 구분한다.
enum MedBuddyDestination { home, schedule, medicationCabinet, profile }

// 클래스명: MedBuddyBottomNavigationUI
// 역할: 홈, 일정, 복약함, 내 정보 목적지를 접근 가능한 고정 탐색 막대로 표시한다.
// 주요 책임:
// - 선택한 목적지를 색상과 배경 형태로 함께 구분한다.
// - 모든 목적지에 아이콘과 텍스트 라벨을 함께 제공한다.
// - Android 하단 안전 영역과 최소 터치 영역을 보장한다.
class MedBuddyBottomNavigationUI extends StatelessWidget {
  final MedBuddyDestination selectedDestination;
  final String language;
  final ValueChanged<MedBuddyDestination> onDestinationSelected;

  const MedBuddyBottomNavigationUI({
    super.key,
    required this.selectedDestination,
    required this.language,
    required this.onDestinationSelected,
  });

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
        destination: MedBuddyDestination.profile,
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        label: text.profile,
      ),
    ];

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
          height: 70,
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: _BottomNavigationButton(
                    item: item,
                    selected: item.destination == selectedDestination,
                    onPressed: () => onDestinationSelected(item.destination),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavigationButton extends StatelessWidget {
  final _BottomNavigationItem item;
  final bool selected;
  final VoidCallback onPressed;

  const _BottomNavigationButton({
    required this.item,
    required this.selected,
    required this.onPressed,
  });

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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textScaler: TextScaler.noScaling,
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

class _BottomNavigationItem {
  final MedBuddyDestination destination;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _BottomNavigationItem({
    required this.destination,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class _BottomNavigationText {
  final String language;

  const _BottomNavigationText(this.language);

  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  String get home => isEnglish ? 'Home' : '홈';
  String get schedule => isEnglish ? 'Schedule' : '일정';
  String get medicationCabinet => isEnglish ? 'Medications' : '복약함';
  String get profile => isEnglish ? 'My Info' : '내 정보';
}
