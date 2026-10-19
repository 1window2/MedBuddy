// File Name: medbuddy_notice.dart
// Role: Provides the shared amber notice used for safety and review guidance.

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// Class Name: MedBuddyNotice
// Role: Shows one caution or review message beside an icon on a warning surface.
// Responsibilities:
// - Keeps safety and review guidance visually identical across features.
// - Scales the icon and text with the user's content text setting.
// Attributes:
// - message (String): Guidance shown to the user.
// - icon (IconData): Leading caution or information icon.
// - padding (EdgeInsetsGeometry): Inner spacing around the icon and message.
// - action (Widget?): Optional control shown below the message, stretched to the notice width.
class MedBuddyNotice extends StatelessWidget {
  final String message;
  final IconData icon;
  final EdgeInsetsGeometry padding;
  final Widget? action;

  // Function Name: MedBuddyNotice
  // Description: Stores the notice content and layout options.
  // Parameters:
  // - key (Key?): Optional widget identity.
  // - message, icon, padding: Notice content and layout.
  // - action (Widget?): Optional control placed 10 px below the message; null shows the message only.
  // Returns: A configured MedBuddyNotice.
  const MedBuddyNotice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.padding = const EdgeInsets.all(14),
    this.action,
  });

  // Function Name: build
  // Description: Renders the icon and wrapped message on the warning surface, followed by the
  //   optional action stretched to the full width.
  // Parameters:
  // - context (BuildContext): Widget tree location.
  // Returns: The notice container.
  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: MedBuddyColors.reminderAccent, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: MedBuddyColors.reminderAccent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.4,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: MedBuddyColors.warningSurface,
        borderRadius: MedBuddyRadii.small,
        border: Border.all(color: MedBuddyColors.warningBorder),
      ),
      child: action == null
          ? row
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [row, const SizedBox(height: 10), action!],
            ),
    );
  }
}
