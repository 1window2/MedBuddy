import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 파일명: manage_user_setting_control_test.dart
// 역할: 사용자 설정 저장/복원 control이 SharedPreferences와 올바르게 연결되는지 검증한다.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('requestSettingSave updates all user setting fields', () async {
    SharedPreferences.setMockInitialValues({});
    final control = ManageUserSetting();

    final setting = await control.requestSettingSave(
      currentSetting: const UserSetting(),
      fontSizeOption: 'large',
      readingSpeedOption: 'fast',
      language: 'en',
    );

    expect(setting.fontSize, 20);
    expect(setting.readingSpeed, 1.2);
    expect(setting.language, 'en');
    expect(setting.fontSizeOption, 'large');
    expect(setting.readingSpeedOption, 'fast');
  });

  test('requestStoredUserSetting restores saved values', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_font_size': 14,
      'user_setting_reading_speed': 0.8,
      'user_setting_language': 'en',
    });
    final control = ManageUserSetting();

    final setting = await control.requestStoredUserSetting();

    expect(setting.fontSizeOption, 'small');
    expect(setting.readingSpeedOption, 'slow');
    expect(setting.language, 'en');
  });
}
