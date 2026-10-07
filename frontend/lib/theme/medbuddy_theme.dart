import 'package:flutter/material.dart';

// 파일명: medbuddy_theme.dart
// 역할: MedBuddy 화면에서 반복 사용하는 색상, 모서리, 그림자 값을 모아 관리한다.

// Class Name: MedBuddyColors
// Role: Provides shared semantic color tokens for MedBuddy screens.
// Responsibilities:
// - Keep text contrast, statuses, schedule slots, surfaces, and accents consistent across features.
class MedBuddyColors {
  // A deeper pharmacy green keeps white labels above WCAG AA contrast.
  static const Color primary = Color(0xFF0E7C5A);
  static const Color primaryDark = Color(0xFF0A6347);
  static const Color topBar = Color(0xFF0E7C5A);
  static const Color onPrimaryMuted = Color(0xFFD9EEE4);
  static const Color progressTrack = Color(0xFF0A5A40);
  static const Color mint = Color(0xFFD6EEE3);
  static const Color successBorder = Color(0xFFB9DCCB);
  static const Color successSurface = Color(0xFFEAF5EF);
  static const Color analysisBackground = Color(0xFFEFF6F2);
  // Neutrals share the green hue so text and lines sit quietly beside the brand.
  static const Color pageBackground = Color(0xFFF4F6F5);
  static const Color surface = Colors.white;
  static const Color surfaceSubtle = Color(0xFFEEF2F0);
  static const Color cardBorder = Color(0xFFE0E6E3);
  static const Color divider = Color(0xFFE5EAE7);
  static const Color outline = Color(0xFFC8D2CD);
  static const Color imageAccent = Color(0xFFE6EAF0);
  static const Color textStrong = Color(0xFF1C2420);
  static const Color textMuted = Color(0xFF58615C);
  static const Color textBody = Color(0xFF3D4641);
  static const Color textSubtle = Color(0xFF6A726E);
  static const Color textLight = Color(0xFF9AA19D);
  static const Color infoBlue = Color(0xFF2F4A8A);
  static const Color reminderAccent = Color(0xFF8A5A00);
  static const Color danger = Color(0xFFC0352B);
  static const Color dangerSurface = Color(0xFFFDEEEE);
  static const Color dangerBorder = Color(0xFFF2C4C0);
  static const Color warningSurface = Color(0xFFFFF6E3);
  static const Color warningBorder = Color(0xFFEED39A);
  // Dose times move from morning sky to night navy; each passes AA with white labels.
  static const Color slotMorning = Color(0xFF2B6F8A);
  static const Color slotLunch = Color(0xFF0F7B6C);
  static const Color slotEvening = Color(0xFF5A55A0);
  static const Color slotBedtime = Color(0xFF33435C);
  static const Color lavenderSurface = Color(0xFFEEF0F8);
  static const Color butterSurface = Color(0xFFF8F0DC);
}

// 클래스명: MedBuddyRadii
// 역할: 배지·입력·버튼, 카드·큰 카드·pill 버튼의 공통 모서리 반경을 제공한다.
// 주요 책임:
// - 화면별 반복 도형의 라운딩 값을 한곳에서 공유한다.
class MedBuddyRadii {
  static const BorderRadius small = BorderRadius.all(Radius.circular(8));
  static const BorderRadius control = BorderRadius.all(Radius.circular(12));
  static const BorderRadius card = BorderRadius.all(Radius.circular(16));
  static const BorderRadius largeCard = BorderRadius.all(Radius.circular(20));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
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
      color: Color.fromRGBO(16, 40, 30, 0.04),
      blurRadius: 6,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color.fromRGBO(16, 40, 30, 0.06),
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
  ];
}

// 기존 브랜드 색상과 기본 제목·본문·명령 버튼 규칙을 앱 전체에 적용한다.
class MedBuddyTheme {
  // 매개변수 없이 기본 밝은 테마를 반환한다. 화면의 명시적 상태 색상은 유지한다.
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: MedBuddyColors.primary)
        .copyWith(
          primary: MedBuddyColors.primary,
          onPrimary: Colors.white,
          secondary: MedBuddyColors.primaryDark,
          onSecondary: Colors.white,
          secondaryContainer: MedBuddyColors.mint,
          onSecondaryContainer: MedBuddyColors.primaryDark,
          tertiary: MedBuddyColors.slotEvening,
          primaryContainer: MedBuddyColors.successSurface,
          onPrimaryContainer: MedBuddyColors.primaryDark,
          surface: MedBuddyColors.pageBackground,
          onSurface: MedBuddyColors.textStrong,
          onSurfaceVariant: MedBuddyColors.textMuted,
          surfaceContainerLowest: MedBuddyColors.surface,
          surfaceContainerLow: MedBuddyColors.surface,
          surfaceContainer: MedBuddyColors.surface,
          surfaceContainerHigh: MedBuddyColors.surface,
          surfaceContainerHighest: MedBuddyColors.surfaceSubtle,
          outline: MedBuddyColors.outline,
          outlineVariant: MedBuddyColors.divider,
          error: MedBuddyColors.danger,
        );
    const label = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    );
    const title = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.25,
      letterSpacing: 0,
    );
    final shape = RoundedRectangleBorder(borderRadius: MedBuddyRadii.control);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      primaryColor: MedBuddyColors.primary,
      scaffoldBackgroundColor: MedBuddyColors.pageBackground,
      fontFamilyFallback: const ['Noto Sans KR', 'Roboto', 'Arial'],
      textTheme: const TextTheme(
        titleLarge: title,
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: 0,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.5,
          letterSpacing: 0,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.5,
          letterSpacing: 0,
        ),
        labelLarge: label,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: MedBuddyColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        titleTextStyle: TextStyle(
          color: MedBuddyColors.textStrong,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.35,
          letterSpacing: 0,
        ),
        contentTextStyle: TextStyle(
          color: MedBuddyColors.textBody,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          height: 1.5,
          letterSpacing: 0,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: MedBuddyColors.pageBackground,
        foregroundColor: MedBuddyColors.textStrong,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: MedBuddyColors.textStrong,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: MedBuddyColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: MedBuddyRadii.card,
          side: const BorderSide(color: MedBuddyColors.cardBorder),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: MedBuddyColors.divider,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MedBuddyColors.surface,
        hintStyle: const TextStyle(color: MedBuddyColors.textLight),
        border: OutlineInputBorder(
          borderRadius: MedBuddyRadii.control,
          borderSide: const BorderSide(color: MedBuddyColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: MedBuddyRadii.control,
          borderSide: const BorderSide(color: MedBuddyColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: MedBuddyRadii.control,
          borderSide: const BorderSide(color: MedBuddyColors.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MedBuddyColors.surface,
        selectedColor: MedBuddyColors.successSurface,
        side: const BorderSide(color: MedBuddyColors.outline),
        shape: RoundedRectangleBorder(borderRadius: MedBuddyRadii.pill),
        labelStyle: const TextStyle(
          color: MedBuddyColors.textBody,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: MedBuddyColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: MedBuddyColors.textStrong,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MedBuddyColors.primary,
        linearTrackColor: MedBuddyColors.mint,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: MedBuddyColors.textMuted,
        textColor: MedBuddyColors.textStrong,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: label,
          shape: shape,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: label,
          shape: shape,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MedBuddyColors.primaryDark,
          textStyle: label,
          shape: shape,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: MedBuddyColors.outline),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MedBuddyColors.primaryDark,
          textStyle: label,
          minimumSize: const Size(48, 48),
        ),
      ),
    );
  }
}
