import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// File Name: medbuddy_bottom_navigation_ui_boundary.dart
// Role: UI boundaries and helpers for bottom navigation between Home, Schedule, Pillbox, and My Info.

// Class Name: MedBuddyDestination
// Role: Represents the application's Home, Schedule, Pillbox, and My Info destinations.
// Responsibilities:
// - Enumerates and distinguishes the supported options for the application's Home, Schedule, Pillbox, and My Info destinations: home, schedule, medicationCabinet, profile.
enum MedBuddyDestination { home, schedule, medicationCabinet, profile }

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
  final ValueChanged<MedBuddyDestination> onDestinationSelected;

  // Function Name: MedBuddyBottomNavigationUI
  // Description: Initializes fixed bottom navigation with selected-state and accessibility cues with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - selectedDestination (MedBuddyDestination): Top-level navigation destination to display or select.
  // - language (String): Language code selecting visible wording.
  // - onDestinationSelected (ValueChanged<MedBuddyDestination>): Callback reporting the selected top-level destination.
  // Returns: Initialized MedBuddyBottomNavigationUI instance.
  const MedBuddyBottomNavigationUI({
    super.key,
    required this.selectedDestination,
    required this.language,
    required this.onDestinationSelected,
  });

  // Function Name: build
  // Description: Renders fixed bottom navigation with selected-state and accessibility cues from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for fixed bottom navigation with selected-state and accessibility cues.
  @override
  Widget build(BuildContext context) {
    final text = _BottomNavigationText(language);
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(11) * 1.1;
    final navigationHeight = scaledLabelHeight + 58 < 70
        ? 70.0
        : scaledLabelHeight + 58;
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
          height: navigationHeight,
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
    );
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

  // Function Name: build
  // Description: Renders a navigation destination with icon, label, and selected state from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a navigation destination with icon, label, and selected state.
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
