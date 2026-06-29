import 'package:flutter/material.dart';

// 파일명: set_caregiver_notification_ui_boundary.dart
// 역할: 보호자 알림 설정 화면의 placeholder UI를 정의한다.

// 클래스명: SetCaregiverNotificationUI
// 역할: 후속 보호자 알림 기능에서 사용할 UI boundary 계약을 보존한다.
// 주요 책임:
// - 현재는 미구현 상태를 빈 화면으로 유지한다.
// - 보호자 알림 설정 화면 진입점을 명시적으로 남긴다.
class SetCaregiverNotificationUI extends StatelessWidget {
  const SetCaregiverNotificationUI({super.key});

  void clickCaregiverNotification() {}

  Widget showCaregiverNotification() {
    return this;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
