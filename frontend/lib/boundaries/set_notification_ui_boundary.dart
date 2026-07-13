import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/medbuddy_theme.dart';

// File Name: set_notification_ui_boundary.dart
// Role: Collects and validates a patient-selected medication alarm time.

// Class Name: SetNotificationUI
// Role: Presents the medication alarm popup used by today's schedule flow.
// Responsibilities:
// - Accept a local alarm time in 24-hour HH:mm format.
// - Reject incomplete or out-of-range time values before the control is called.
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

  static Future<TimeOfDay?> showAlarmSettingPopup(
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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _timeController;

  bool get _isEnglish => widget.language.trim().toLowerCase().startsWith('en');

  @override
  void initState() {
    super.initState();
    _timeController = TextEditingController(
      text: _formatTime(widget.initialTime),
    );
  }

  @override
  void dispose() {
    _timeController.dispose();
    super.dispose();
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
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: _isEnglish ? 'Close' : '닫기',
                    onPressed: () => Navigator.pop(context),
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
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 190,
                child: TextFormField(
                  controller: _timeController,
                  autofocus: true,
                  keyboardType: TextInputType.datetime,
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                  decoration: InputDecoration(
                    labelText: _isEnglish ? 'Time (HH:mm)' : '시간 (HH:mm)',
                    prefixIcon: const Icon(
                      Icons.schedule_outlined,
                      color: MedBuddyColors.primary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: MedBuddyColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  inputFormatters: const [_AlarmTimeInputFormatter()],
                  validator: _validateTime,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: MedBuddyColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  _isEnglish ? 'Confirm' : '확인',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateTime(String? value) {
    if (_parseTime(value ?? '') != null) {
      return null;
    }
    return _isEnglish
        ? 'Enter a valid 24-hour time.'
        : '올바른 24시간 형식으로 입력해 주세요.';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.pop(context, _parseTime(_timeController.text));
  }

  static TimeOfDay? _parseTime(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2 || parts[0].length != 2 || parts[1].length != 2) {
      return null;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}

class _AlarmTimeInputFormatter extends TextInputFormatter {
  const _AlarmTimeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitedDigits = digits.substring(
      0,
      digits.length > 4 ? 4 : digits.length,
    );
    final formatted = limitedDigits.length <= 2
        ? limitedDigits
        : '${limitedDigits.substring(0, 2)}:${limitedDigits.substring(2)}';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
