import 'package:flutter/material.dart';

import '../entities/caregiver_notification_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: set_caregiver_notification_ui_boundary.dart
// 역할: 보호자 알림 설정 UI boundary를 구성한다.

// 클래스명: SetCaregiverNotificationUI
// 역할: 보호자가 환자별 알림 수신 여부를 확인하고 변경하는 UI를 제공한다.
// 주요 책임:
// - 현재 CaregiverNotification 상태를 시각화한다.
// - 사용자의 enable/disable 선택을 상위 control 흐름으로 전달한다.
class SetCaregiverNotificationUI extends StatelessWidget {
  final CaregiverNotification setting;
  final bool isLoading;
  final String language;
  final ValueChanged<bool> onNotificationOptionChanged;

  const SetCaregiverNotificationUI({
    super.key,
    required this.setting,
    required this.onNotificationOptionChanged,
    this.isLoading = false,
    this.language = 'ko',
  });

  static Future<bool?> showNotificationPopup(
    BuildContext context, {
    required CaregiverNotification setting,
    bool isLoading = false,
    String language = 'ko',
  }) {
    final isEnglish = language.trim().toLowerCase().startsWith('en');
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: isEnglish ? 'Close' : '닫기',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                    Expanded(
                      child: Text(
                        isEnglish
                            ? 'Caregiver notification settings'
                            : '보호자 알림 설정',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF0A0A0A),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 12),
                SetCaregiverNotificationUI(
                  setting: setting,
                  isLoading: isLoading,
                  language: language,
                  onNotificationOptionChanged: (enabled) {
                    Navigator.pop(dialogContext, enabled);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void setNotificationOption(bool enabled) {
    onNotificationOptionChanged(enabled);
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = language.trim().toLowerCase().startsWith('en');
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MedBuddyColors.divider),
      ),
      child: Row(
        children: [
          Icon(
            setting.notificationEnabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_outlined,
            color: setting.notificationEnabled
                ? MedBuddyColors.primary
                : MedBuddyColors.textLight,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isEnglish ? 'Caregiver notification' : '보호자 알림',
              style: const TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (isLoading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: MedBuddyColors.primary,
              ),
            )
          else
            Switch(
              value: setting.notificationEnabled,
              activeThumbColor: MedBuddyColors.primary,
              onChanged: setNotificationOption,
            ),
        ],
      ),
    );
  }
}
