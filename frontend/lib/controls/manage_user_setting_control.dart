import '../entities/user_setting_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 파일명: manage_user_setting_control.dart
// 역할: 사용자 환경설정을 로컬 저장소에 저장하고 불러온다.

// 클래스명: ManageUserSetting
// 역할: 글씨 크기, 읽기 속도, 언어 설정을 SharedPreferences에 영구 저장한다.
// 주요 책임:
// - 앱 실행 시 저장된 환경설정을 불러온다.
// - 설정 화면에서 선택한 값을 UserSetting으로 변환한다.
// - 앱을 재시작해도 설정이 유지되도록 로컬 저장소에 저장한다.
class ManageUserSetting {
  static const String _fontSizeKey = 'user_setting_font_size';
  static const String _readingSpeedKey = 'user_setting_reading_speed';
  static const String _languageKey = 'user_setting_language';

  // 함수명: requestUserSetting
  // 함수역할:
  // - 현재 메모리에 있는 사용자 설정을 반환한다.
  // 매개변수:
  // - currentSetting: ViewModel이 보관 중인 현재 설정
  // 반환값:
  // - 현재 사용자 설정
  UserSetting requestUserSetting(UserSetting currentSetting) {
    return currentSetting;
  }

  // 함수명: requestStoredUserSetting
  // 함수역할:
  // - SharedPreferences에 저장된 사용자 설정을 불러온다.
  // 반환값:
  // - 저장값이 없으면 기본값으로 채운 UserSetting
  Future<UserSetting> requestStoredUserSetting() async {
    final preferences = await SharedPreferences.getInstance();

    return UserSetting(
      fontSize: preferences.getInt(_fontSizeKey) ?? 16,
      readingSpeed: preferences.getDouble(_readingSpeedKey) ?? 1.0,
      language: preferences.getString(_languageKey) ?? 'ko',
    );
  }

  // 함수명: requestSettingSave
  // 함수역할:
  // - 설정 화면에서 선택한 옵션을 실제 설정값으로 변환한 뒤 저장한다.
  // 매개변수:
  // - currentSetting: 현재 사용자 설정
  // - fontSizeOption: small, medium, large 중 선택된 글씨 크기 옵션
  // - readingSpeedOption: slow, medium, fast 중 선택된 읽기 속도 옵션
  // - language: ko 또는 en 언어 코드
  // 반환값:
  // - 저장 완료된 새 UserSetting
  Future<UserSetting> requestSettingSave({
    required UserSetting currentSetting,
    required String fontSizeOption,
    required String readingSpeedOption,
    required String language,
  }) async {
    final nextSetting = currentSetting
        .changeFontSize(UserSetting.fontSizeFromOption(fontSizeOption))
        .changeReadingSpeed(
          UserSetting.readingSpeedFromOption(readingSpeedOption),
        )
        .changeLanguage(language);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_fontSizeKey, nextSetting.fontSize);
    await preferences.setDouble(_readingSpeedKey, nextSetting.readingSpeed);
    await preferences.setString(_languageKey, nextSetting.language);

    return nextSetting;
  }
}
