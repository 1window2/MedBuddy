import 'package:flutter/material.dart';

// 파일명: medbuddy_theme.dart
// 역할: MedBuddy 화면에서 반복 사용하는 색상, 모서리, 그림자 값을 모아 관리한다.

// Class Name: MedBuddyColors
// Role: Provides shared semantic color tokens for MedBuddy screens.
// Responsibilities:
// - Keep text contrast, statuses, schedule slots, surfaces, and accents consistent across features.
class MedBuddyColors {
  // MedBuddy's established green remains the primary action and brand color.
  static const Color primary = Color(0xFF009966);
  static const Color primaryDark = Color(0xFF007A55);
  static const Color topBar = Color(0xFF198C54);
  static const Color progressTrack = Color(0xFF006045);
  static const Color mint = Color(0xFFD0FAE5);
  static const Color successBorder = Color(0xFFA4F4CF);
  static const Color successSurface = Color(0xFFECFDF5);
  static const Color analysisBackground = Color(0xFFEEFDF6);
  static const Color pageBackground = Color(0xFFF8FBF9);
  static const Color surface = Colors.white;
  static const Color surfaceSubtle = Color(0xFFF4F8F6);
  static const Color cardBorder = Color(0xFFE1EBE6);
  static const Color divider = Color(0xFFE2EBE6);
  static const Color outline = Color(0xFFC8D8D0);
  static const Color imageAccent = Color(0xFFE4E7F5);
  static const Color textStrong = Color(0xFF25252B);
  static const Color textMuted = Color(0xFF5E5D67);
  static const Color textBody = Color(0xFF46454E);
  static const Color textSubtle = Color(0xFF797782);
  static const Color textLight = Color(0xFFA3A1AA);
  static const Color infoBlue = Color(0xFF1C398E);
  static const Color reminderAccent = Color(0xFF8B6A00);
  static const Color danger = Color(0xFFD92D20);
  static const Color slotMorning = Color(0xFF168872);
  static const Color slotLunch = Color(0xFF247C6D);
  static const Color slotEvening = Color(0xFF356B63);
  static const Color slotBedtime = Color(0xFF405F66);
  static const Color lavenderSurface = Color(0xFFF0F1FA);
  static const Color butterSurface = Color(0xFFF8F1D9);
  static const Color roseSurface = Color(0xFFFBEAEC);
}

// 클래스명: MedBuddyRadii
// 역할: 카드·큰 카드·pill 버튼의 공통 모서리 반경을 제공한다.
// 주요 책임:
// - 화면별 반복 도형의 라운딩 값을 한곳에서 공유한다.
class MedBuddyRadii {
  static BorderRadius card = BorderRadius.circular(16);
  static BorderRadius largeCard = BorderRadius.circular(22);
  static BorderRadius pill = BorderRadius.circular(999);
}

// 클래스명: MedBuddySpacing
// 역할: 화면의 여백과 정보 밀도에 사용할 공통 치수를 제공한다.
// 주요 책임:
// - 페이지 좌우 여백·섹션·항목 간격 및 콘텐츠 최대 폭을 일관되게 유지한다.
class MedBuddySpacing {
  static const double pageHorizontal = 20;
  static const double section = 24;
  static const double item = 12;
  static const double contentMaxWidth = 720;
}

// 클래스명: MedBuddyShadows
// 역할: 카드 UI의 기본 및 강조 그림자 스타일을 제공한다.
// 주요 책임:
// - 화면마다 같은 색·흐림·오프셋의 표면 구분 효과를 재사용한다.
class MedBuddyShadows {
  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color.fromRGBO(12, 47, 40, 0.06),
      blurRadius: 14,
      offset: Offset(0, 5),
    ),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color.fromRGBO(12, 47, 40, 0.09),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
}
