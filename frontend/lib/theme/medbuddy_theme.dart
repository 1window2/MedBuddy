import 'package:flutter/material.dart';

// 파일명: medbuddy_theme.dart
// 역할: MedBuddy 화면에서 반복 사용하는 색상, 모서리, 그림자 값을 모아 관리한다.

// 클래스명: MedBuddyColors
// 역할: 앱 전반의 주요 색상 토큰을 제공한다.
class MedBuddyColors {
  static const Color primary = Color(0xFF009966);
  static const Color primaryDark = Color(0xFF007A55);
  static const Color mint = Color(0xFFD0FAE5);
  static const Color pageBackground = Color(0xFFF4FFF4);
  static const Color textStrong = Color(0xFF101828);
  static const Color textMuted = Color(0xFF4A5565);
  static const Color textLight = Color(0xFF99A1AF);
  static const Color infoBlue = Color(0xFF1C398E);
}

// 클래스명: MedBuddyRadii
// 역할: 카드, 큰 카드, pill 형태 버튼에 사용할 공통 모서리 값을 제공한다.
class MedBuddyRadii {
  static BorderRadius card = BorderRadius.circular(14);
  static BorderRadius largeCard = BorderRadius.circular(16);
  static BorderRadius pill = BorderRadius.circular(999);
}

// 클래스명: MedBuddyShadows
// 역할: 카드형 UI에서 반복 사용하는 그림자 스타일을 제공한다.
class MedBuddyShadows {
  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.12),
      blurRadius: 10,
      offset: Offset(0, 5),
    ),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.12),
      blurRadius: 14,
      offset: Offset(0, 8),
    ),
  ];
}
