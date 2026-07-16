import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// File Name: set_notification_ui_boundary.dart
// Role: Collects and validates a patient-selected medication alarm time.

// Class Name: SetNotificationUI
// Role: Presents the medication alarm popup used by today's schedule flow.
// Responsibilities:
// - Let the user select a local alarm time with rotating time wheels.
// - Return a TimeOfDay value without owning persistence or notification logic.
class SetNotificationUI extends StatefulWidget {
  final String language;
  final String slotTitle;
  final TimeOfDay initialTime;

  const SetNotificationUI({
    super.key,
    required this.language,
    required this.slotTitle,
    required this.initialTime,
  });

  static Future<TimeOfDay?> showNotificationPopup(
    BuildContext context, {
    required String language,
    required String slotTitle,
    required TimeOfDay initialTime,
  }) {
    return showDialog<TimeOfDay>(
      context: context,
      barrierDismissible: true,
      builder: (context) => SetNotificationUI(
        language: language,
        slotTitle: slotTitle,
        initialTime: initialTime,
      ),
    );
  }

  @override
  State<SetNotificationUI> createState() => _SetNotificationUIState();
}

class _SetNotificationUIState extends State<SetNotificationUI> {
  late DateTime _selectedDateTime;

  bool get _isEnglish => widget.language.trim().toLowerCase().startsWith('en');

  @override
  void initState() {
    super.initState();
    _selectedDateTime = DateTime(
      2000,
      1,
      1,
      widget.initialTime.hour,
      widget.initialTime.minute,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF344054), width: 1.6),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.18),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('notification-time-close'),
                  tooltip: _isEnglish ? 'Close' : '닫기',
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(
                    backgroundColor: MedBuddyColors.surfaceSubtle,
                    foregroundColor: MedBuddyColors.textStrong,
                  ),
                  icon: const Icon(Icons.close, size: 25),
                ),
                Expanded(
                  child: Text(
                    _isEnglish
                        ? '${widget.slotTitle} Reminder'
                        : '${widget.slotTitle} 알림',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('notification-time-confirm'),
                  tooltip: _isEnglish ? 'Confirm' : '확인',
                  onPressed: setNotificationTime,
                  style: IconButton.styleFrom(
                    backgroundColor: MedBuddyColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check, size: 25),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Semantics(
              label: _isEnglish ? 'Medication reminder time' : '복약 알림 시간',
              child: SizedBox(
                height: 220,
                child: CupertinoDatePicker(
                  key: const Key('notification-time-wheel'),
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: _selectedDateTime,
                  minuteInterval: 1,
                  use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
                  onDateTimeChanged: (value) {
                    setState(() => _selectedDateTime = value);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void setNotificationTime() {
    Navigator.pop(
      context,
      TimeOfDay(
        hour: _selectedDateTime.hour,
        minute: _selectedDateTime.minute,
      ),
    );
  }
}
