import 'package:flutter/material.dart';

// 파일명: set_guardian_alert_setting_ui_boundary.dart
// 역할: 보호자 알림 설정 화면의 placeholder UI를 정의한다.

// 클래스명: SetGuardianAlertSettingUI
// 역할: 후속 보호자 알림 기능에서 사용할 UI boundary 계약을 보존한다.
// 주요 책임:
// - 현재는 미구현 상태를 빈 화면으로 유지한다.
// - 보호자 알림 설정 화면 진입점을 명시적으로 남긴다.
class SetGuardianAlertSettingUI extends StatelessWidget {
  const SetGuardianAlertSettingUI({super.key});

  void clickGuardianAlertSetting() {}

  Widget showGuardianAlertSetting() {
    return this;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
