import 'package:flutter/material.dart';

// 파일명: medbuddy_theme.dart
// 역할: MedBuddy 화면에서 반복 사용하는 색상, 모서리, 그림자 값을 모아 관리한다.

// 클래스명: MedBuddyColors
// 역할: 화면에서 함께 사용하는 의미별 색상 값을 제공한다.
// 주요 책임: 브랜드·본문·표면·상태·복용 시간대 색상을 일관되게 참조하게 한다.
// 속성: 모든 값은 정적 Color 상수이며 인스턴스 상태는 없다.
class MedBuddyColors {
  // A deeper pharmacy green keeps white labels above WCAG AA contrast.
  static const Color primary = Color(0xFF0E7C5A);
  static const Color primaryDark = Color(0xFF0A6347);
  static const Color topBar = Color(0xFF0E7C5A);
  static const Color onPrimaryMuted = Color(0xFFD9EEE4);
  static const Color mint = Color(0xFFD6EEE3);
  static const Color successBorder = Color(0xFFB9DCCB);
  static const Color successSurface = Color(0xFFEAF5EF);
  static const Color chatOutgoing = Color(0xFFDFF0E8);
  // 공유 내용은 송수신 말풍선과 구별되는 같은 회청색으로 표시한다.
  static const Color chatContentSurface = Color(0xFFF0F3F7);
  static const Color chatContentBorder = Color(0xFFCCD5E0);
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

// 클래스명: MedBuddySlotStyle
// 역할: 복용 시간대마다 색상·밝은 배경색·아이콘의 공통 조합을 제공한다.
// 주요 책임: 홈·일정·보호자 화면이 같은 시간대 표현을 사용하도록 한다.
// 속성: color: 강조색; tint: 밝은 배경; icon: 시간대 표시; 정적 값에는 필요시 복용도 포함된다.
class MedBuddySlotStyle {
  final Color color;
  final Color tint;
  final IconData icon;

  // Function Name: MedBuddySlotStyle._
  // Description: Stores one dose time's color, tint and icon.
  // Parameters: color, tint, icon: Slot visuals. Returns: A slot style.
  const MedBuddySlotStyle._(this.color, this.tint, this.icon);

  static const morning = MedBuddySlotStyle._(
    MedBuddyColors.slotMorning,
    Color(0xFFE7F0F4),
    Icons.wb_sunny_outlined,
  );
  static const lunch = MedBuddySlotStyle._(
    MedBuddyColors.slotLunch,
    Color(0xFFE5F2EF),
    Icons.local_cafe_outlined,
  );
  static const evening = MedBuddySlotStyle._(
    MedBuddyColors.slotEvening,
    Color(0xFFEEEDF7),
    Icons.wb_twilight_outlined,
  );
  static const bedtime = MedBuddySlotStyle._(
    MedBuddyColors.slotBedtime,
    Color(0xFFE9ECF1),
    Icons.nightlight_round,
  );

  static const asNeeded = MedBuddySlotStyle._(
    MedBuddyColors.slotBedtime,
    Color(0xFFE9ECF1),
    Icons.medication_outlined,
  );

  // 함수이름: of
  // 함수역할: 복용 구간 키에 해당하는 공통 스타일을 선택한다.
  // 매개변수: slotKey: morning/lunch/evening/as_needed 등의 구간 키.
  // 반환값: 해당 스타일; 등록되지 않은 키는 bedtime 스타일.
  static MedBuddySlotStyle of(String slotKey) => switch (slotKey) {
    'morning' => morning,
    'lunch' => lunch,
    'evening' => evening,
    'as_needed' => asNeeded,
    _ => bedtime,
  };
}

// Class Name: MedBuddyRadii
// Role: Provides shared corner radii for badges, controls and card surfaces.
// Responsibilities: Keep repeated shapes consistent across screens.
// Attributes: Static BorderRadius tokens: small, control, card, largeCard and pill.
class MedBuddyRadii {
  static const BorderRadius small = BorderRadius.all(Radius.circular(8));
  static const BorderRadius control = BorderRadius.all(Radius.circular(12));
  static const BorderRadius card = BorderRadius.all(Radius.circular(16));
  static const BorderRadius largeCard = BorderRadius.all(Radius.circular(20));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

// 클래스명: MedBuddySpacing
// 역할: 화면 여백과 정보 밀도의 공통 치수를 제공한다.
// 주요 책임: 페이지 좌우 여백과 최대 콘텐츠 폭을 일관되게 유지한다.
// 속성: pageHorizontal/contentMaxWidth: 정적 double 치수.
class MedBuddySpacing {
  static const double pageHorizontal = 20;
  static const double contentMaxWidth = 720;
}

// 클래스명: MedBuddyTextStyles
// 역할: 검색 메뉴와 약 등록·변경 화면의 글자 위계를 공유한다.
// 주요 책임: 반복되는 제목·보조 설명·폼 구역 제목의 크기와 굵기를 통일한다.
// 속성: menuTitle/menuBody/formSectionTitle: 정적 TextStyle 상수.
class MedBuddyTextStyles {
  // 검색 결과·선택 메뉴는 같은 제목과 보조 설명 위계를 사용한다.
  static const menuTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: 0,
  );
  static const menuBody = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.35,
    letterSpacing: 0,
  );
  static const formSectionTitle = TextStyle(
    color: MedBuddyColors.textStrong,
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );
}

// Class Name: MedBuddyShadows
// Role: Provides reusable surface-shadow presets.
// Responsibilities: Share color, blur and offset choices for subtle and card surfaces.
// Attributes: soft and card: Immutable BoxShadow lists.
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

// Class Name: MedBuddyTheme
// Role: Builds the application's shared Material theme.
// Responsibilities: Apply semantic colors, typography and common component defaults.
// Attributes: No instance state; light constructs a ThemeData from the shared token classes.
class MedBuddyTheme {
  // 함수이름: light
  // 함수역할: 브랜드 색상과 글자 위계 및 입력·버튼·대화상자 기본 스타일을 적용한 밝은 테마를 만든다.
  // 매개변수: 없음.
  // 반환값: Material 3 ThemeData; 화면이 직접 지정한 상태별 스타일을 변경하지 않는다.
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
        titleMedium: MedBuddyTextStyles.menuTitle,
        titleSmall: MedBuddyTextStyles.menuBody,
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
        titleTextStyle: MedBuddyTextStyles.menuTitle,
        subtitleTextStyle: MedBuddyTextStyles.menuBody,
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
          backgroundColor: MedBuddyColors.primary,
          foregroundColor: Colors.white,
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
