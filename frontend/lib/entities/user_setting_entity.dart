class UserSetting {
  final int fontSize;
  final double readingSpeed;
  final String language;

  const UserSetting({
    this.fontSize = 16,
    this.readingSpeed = 1.0,
    this.language = 'ko',
  });

  UserSetting getUserSetting() {
    return this;
  }

  UserSetting changeFontSize(int fontSize) {
    return UserSetting(
      fontSize: fontSize,
      readingSpeed: readingSpeed,
      language: language,
    );
  }

  UserSetting changeReadingSpeed(double readingSpeed) {
    return UserSetting(
      fontSize: fontSize,
      readingSpeed: readingSpeed,
      language: language,
    );
  }

  UserSetting changeLanguage(String language) {
    return UserSetting(
      fontSize: fontSize,
      readingSpeed: readingSpeed,
      language: language,
    );
  }
}
