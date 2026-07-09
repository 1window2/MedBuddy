import 'package:flutter/material.dart';

import '../entities/guardian_alert_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: set_guardian_alert_setting_ui_boundary.dart
// 역할: 보호자 알림 설정 UI boundary를 구성한다.

// 클래스명: SetGuardianAlertSettingUI
// 역할: 보호자가 환자별 알림 수신 여부를 확인하고 변경하는 UI를 제공한다.
// 주요 책임:
// - 현재 GuardianAlertSetting 상태를 시각화한다.
// - 사용자의 enable/disable 선택을 상위 control 흐름으로 전달한다.
class SetGuardianAlertSettingUI extends StatelessWidget {
  final GuardianAlertSetting setting;
  final bool isLoading;
  final ValueChanged<bool> onAlertOptionChanged;

  const SetGuardianAlertSettingUI({
    super.key,
    required this.setting,
    required this.onAlertOptionChanged,
    this.isLoading = false,
  });

  void clickGuardianAlertSetting(bool enabled) {
    onAlertOptionChanged(enabled);
  }

  Widget showGuardianAlertSetting() {
    return this;
  }

  @override
  Widget build(BuildContext context) {
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
            setting.enabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_outlined,
            color: setting.enabled
                ? MedBuddyColors.primary
                : MedBuddyColors.textLight,
            size: 22,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '보호자 알림',
              style: TextStyle(
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
              value: setting.enabled,
              activeThumbColor: MedBuddyColors.primary,
              onChanged: clickGuardianAlertSetting,
            ),
        ],
      ),
    );
  }
}
