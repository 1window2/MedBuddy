// 파일명: user_setting_entity.dart
// 역할: 사용자 접근성/언어 설정 값을 표현하는 모델을 정의한다.

// 클래스명: UserSetting
// 역할: 글씨 크기, 읽기 속도, 언어 설정을 앱 전체에서 동일한 형식으로 사용하게 한다.
// 주요 책임:
// - 설정 화면 옵션 문자열과 실제 수치 값을 서로 변환한다.
// - 화면 텍스트 확대 비율을 계산한다.
// - 불변 객체 방식으로 변경된 설정 값을 생성한다.
class UserSetting {
  final int fontSize;
  final double readingSpeed;
  final String language;

  const UserSetting({
    this.fontSize = 16,
    this.readingSpeed = 1.0,
    this.language = 'ko',
  });

  String get fontSizeOption {
    if (fontSize <= 14) {
      return 'small';
    }
    if (fontSize >= 20) {
      return 'large';
    }
    return 'medium';
  }

  String get readingSpeedOption {
    if (readingSpeed < 1.0) {
      return 'slow';
    }
    if (readingSpeed > 1.0) {
      return 'fast';
    }
    return 'medium';
  }

  double get textScaleFactor => fontSize / 16.0;

  double get contentTextScale {
    if (fontSize <= 14) {
      return 0.92;
    }
    if (fontSize >= 20) {
      return 1.12;
    }
    return 1.0;
  }

  // 함수명: copyWith
  // 함수역할:
  // - 기존 설정을 유지하면서 일부 값만 바꾼 새 설정 객체를 만든다.
  // 반환값:
  // - 변경값이 반영된 UserSetting 인스턴스
  UserSetting copyWith({
    int? fontSize,
    double? readingSpeed,
    String? language,
  }) {
    return UserSetting(
      fontSize: fontSize ?? this.fontSize,
      readingSpeed: readingSpeed ?? this.readingSpeed,
      language: language ?? this.language,
    );
  }

  UserSetting changeFontSize(int fontSize) {
    return copyWith(fontSize: fontSize);
  }

  UserSetting changeReadingSpeed(double readingSpeed) {
    return copyWith(readingSpeed: readingSpeed);
  }

  UserSetting changeLanguage(String language) {
    return copyWith(language: language);
  }

  // 함수명: fontSizeFromOption
  // 함수역할:
  // - 설정 화면의 글씨 크기 옵션 문자열을 실제 font size 값으로 변환한다.
  // 매개변수:
  // - option: small, medium, large 중 하나
  // 반환값:
  // - 앱에서 사용할 font size 정수값
  static int fontSizeFromOption(String option) {
    return switch (option) {
      'small' => 14,
      'large' => 20,
      _ => 16,
    };
  }

  // 함수명: readingSpeedFromOption
  // 함수역할:
  // - 설정 화면의 읽기 속도 옵션 문자열을 실제 배속 값으로 변환한다.
  // 매개변수:
  // - option: slow, medium, fast 중 하나
  // 반환값:
  // - 음성/읽기 속도에 사용할 배속 값
  static double readingSpeedFromOption(String option) {
    return switch (option) {
      'slow' => 0.8,
      'fast' => 1.2,
      _ => 1.0,
    };
  }
}
