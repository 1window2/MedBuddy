// 파일명: app_version_label.dart
// 역할: MedBuddy 빌드 버전을 설정 화면에 표시한다.

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

const medBuddyAppVersion = String.fromEnvironment(
  'MEDBUDDY_APP_VERSION',
  defaultValue: '0.1.1',
);

// 클래스명: AppVersionLabel
// 역할: 빌드 환경에 정의된 앱 버전을 짧은 보조 정보로 보여준다.
class AppVersionLabel extends StatelessWidget {
  final String version;

  const AppVersionLabel({super.key, this.version = medBuddyAppVersion});

  @override
  Widget build(BuildContext context) {
    return Text(
      'MedBuddy v$version',
      key: const ValueKey('appVersionLabel'),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: MedBuddyColors.textMuted,
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}
