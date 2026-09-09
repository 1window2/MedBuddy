// 파일명: app_version_label.dart
// 역할: 빌드에 정의된 앱 버전 표시를 제공한다.

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

const medBuddyAppVersion = String.fromEnvironment(
  'MEDBUDDY_APP_VERSION',
  defaultValue: '0.2.0',
);

// 클래스명: AppVersionLabel
// 역할: 빌드 버전을 표시하는 짧은 보조 라벨을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 빌드 버전을 표시하는 짧은 보조 라벨 위젯을 구성한다.
// 속성:
// - version (String): 화면에 표시할 빌드 버전 문자열.
class AppVersionLabel extends StatelessWidget {
  final String version;

  // 함수이름: AppVersionLabel
  // 함수역할: 빌드 버전을 표시하는 짧은 보조 라벨에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - version (String): 화면에 표시할 빌드 버전 문자열.
  // 반환값: 입력 설정이 반영된 AppVersionLabel 인스턴스.
  const AppVersionLabel({super.key, this.version = medBuddyAppVersion});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 빌드 버전을 표시하는 짧은 보조 라벨 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 빌드 버전을 표시하는 짧은 보조 라벨에 쓰는 위젯 트리.
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
