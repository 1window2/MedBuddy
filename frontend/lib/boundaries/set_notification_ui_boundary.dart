import 'package:flutter/material.dart';

// 파일명: set_notification_ui_boundary.dart
// 역할: 환자 복약 알림 설정 화면의 placeholder UI를 정의한다.

// 클래스명: SetNotificationUI
// 역할: 후속 알림 설정 기능에서 사용할 UI boundary 계약을 보존한다.
// 주요 책임:
// - 현재는 미구현 상태를 빈 화면으로 유지한다.
// - 알림 설정 화면 진입점을 명시적으로 남긴다.
class SetNotificationUI extends StatelessWidget {
  const SetNotificationUI({super.key});

  void clickNotificationSetting() {}

  Widget showNotificationSetting() {
    return this;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
