// 파일명: medbuddy_setting_toggle.dart
// 역할: 앱 설정과 기기 권한에 같은 스위치 모양과 간격을 적용한다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 클래스명: MedBuddySettingToggle
// 역할: 이진 설정의 라벨·설명·현재 값을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 이진 설정의 라벨·설명·현재 값 위젯을 구성한다.
// 속성:
// - switchKey (Key): 위젯을 구분하고 상태를 유지할 식별 키.
// - title (String): 화면·구역·항목에 표시할 제목.
// - description (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
// - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
class MedBuddySettingToggle extends StatelessWidget {
  final Key switchKey;
  final String title;
  final String description;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  // 함수이름: MedBuddySettingToggle
  // 함수역할: 이진 설정의 라벨·설명·현재 값에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - switchKey (Key): 위젯을 구분하고 상태를 유지할 식별 키.
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - description (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
  // - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
  // - onChanged (ValueChanged<bool>?): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // 반환값: 입력 설정이 반영된 MedBuddySettingToggle 인스턴스.
  const MedBuddySettingToggle({
    super.key,
    required this.switchKey,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onChanged,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 이진 설정의 라벨·설명·현재 값 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 이진 설정의 라벨·설명·현재 값에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SwitchListTile(
        key: switchKey,
        value: enabled,
        onChanged: onChanged,
        activeThumbColor: MedBuddyColors.primary,
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        title: Text(
          title,
          style: const TextStyle(
            color: MedBuddyColors.textStrong,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            description,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
