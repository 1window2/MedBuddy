// File Name: medbuddy_option_sheet.dart
// Role: Provides the shared bottom-sheet frame and option rows used by home choice sheets.

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// Class Name: MedBuddyOptionSheet
// Role: Frames a scrollable choice sheet with a drag handle.
// Responsibilities:
// - Keeps large-text option lists scrollable inside the safe area.
// Attributes:
// - children (List<Widget>): Options and headings shown below the handle.
class MedBuddyOptionSheet extends StatelessWidget {
  final List<Widget> children;

  // Function Name: MedBuddyOptionSheet
  // Description: Stores the sheet content.
  // Parameters:
  // - key (Key?): Identity used to reset the sheet when its mode changes.
  // - children (List<Widget>): Options and headings shown below the handle.
  // Returns: A configured MedBuddyOptionSheet.
  const MedBuddyOptionSheet({super.key, required this.children});

  // Function Name: build
  // Description: Places the drag handle above the supplied options.
  // Parameters:
  // - context (BuildContext): Widget tree location.
  // Returns: A scrollable, safe-area sheet body.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: MedBuddyColors.outline,
                borderRadius: MedBuddyRadii.pill,
              ),
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}

// Class Name: MedBuddyOptionTile
// Role: Represents one tappable choice with an icon, title and explanation.
// Responsibilities:
// - Scales both text lines with the user's content text setting.
// - Runs the caller's action when selected.
// Attributes:
// - icon (IconData): Leading choice icon.
// - title (String): Choice name.
// - subtitle (String): What the choice does.
// - scale (double): User content text scale.
// - onTap (VoidCallback): Selection action.
// - inkKey (Key?): Optional key for the tappable area.
class MedBuddyOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double scale;
  final VoidCallback onTap;
  final Key? inkKey;

  // Function Name: MedBuddyOptionTile
  // Description: Stores the choice content and selection action.
  // Parameters:
  // - icon, title, subtitle: Displayed choice content.
  // - scale (double): User content text scale.
  // - onTap (VoidCallback): Selection action.
  // - inkKey (Key?): Optional key for the tappable area.
  // Returns: A configured MedBuddyOptionTile.
  const MedBuddyOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.scale,
    required this.onTap,
    this.inkKey,
  });

  // Function Name: build
  // Description: Renders the icon, two text lines and a chevron on a tinted row.
  // Parameters:
  // - context (BuildContext): Widget tree location.
  // Returns: The tappable choice row.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: MedBuddyColors.successSurface,
      borderRadius: MedBuddyRadii.card,
      child: InkWell(
        key: inkKey,
        borderRadius: MedBuddyRadii.card,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: Border.all(color: MedBuddyColors.successBorder),
          ),
          child: Row(
            children: [
              Icon(icon, color: MedBuddyColors.primary, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 17 * scale,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 13 * scale,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: MedBuddyColors.primary,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
