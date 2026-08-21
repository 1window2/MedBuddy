import 'package:flutter/material.dart';

import '../entities/user_setting_entity.dart';

// 파일명: medbuddy_text_scale.dart
// 역할: 사용자 글씨 크기 설정을 앱 전체 MediaQuery에 한 번만 적용한다.

// 클래스명: MedBuddyTextScale
// 역할: 운영체제 접근성 배율과 앱 설정 배율을 조합해 모든 하위 화면에 전달한다.
// 주요 책임:
// - 휴대폰 자체 글씨 크기를 축소하지 않는다.
// - 환경설정의 큰 글씨를 모든 화면과 새로 추가되는 화면에도 적용한다.
// - 최대 배율을 제한해 고정 크기 UI의 심각한 오버플로우를 예방한다.
class MedBuddyTextScale extends StatelessWidget {
  final UserSetting userSetting;
  final Widget child;

  const MedBuddyTextScale({
    super.key,
    required this.userSetting,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final systemTextScale = mediaQuery.textScaler.scale(16) / 16;
    final resolvedTextScale = userSetting.resolveTextScale(systemTextScale);

    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: TextScaler.linear(resolvedTextScale),
      ),
      child: child,
    );
  }
}
