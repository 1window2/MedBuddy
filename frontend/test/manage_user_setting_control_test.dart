// 파일명: manage_user_setting_control_test.dart
// 역할: 사용자 설정의 로컬 저장과 서버 동기화 규칙을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 파일명: manage_user_setting_control_test.dart
// 역할: 사용자 설정 저장/복원 control이 SharedPreferences와 올바르게 연결되는지 검증한다.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saveUserSetting updates all user setting fields', () async {
    SharedPreferences.setMockInitialValues({});
    final control = ManageUserSetting(useRemotePersistence: false);

    final result = await control.saveUserSetting(
      currentSetting: const UserSetting(),
      fontSizeOption: 'large',
      readingSpeedOption: 'fast',
      language: 'en',
    );
    final setting = result.setting;

    expect(result.synchronizedWithServer, isFalse);
    expect(setting.fontSize, 20);
    expect(setting.readingSpeed, 1.2);
    expect(setting.language, 'en');
    expect(setting.userHash, 'local_patient');
    expect(setting.fontSizeOption, 'large');
    expect(setting.readingSpeedOption, 'fast');
  });

  test('근처 운영 약국 실험 설정은 사용자별 기기에 저장된다', () async {
    SharedPreferences.setMockInitialValues({});
    final control = ManageUserSetting(
      userHash: 'user-a',
      useRemotePersistence: false,
    );

    final savedSetting = await control.saveNearbyPharmacyLabSetting(
      currentSetting: const UserSetting(),
      enabled: true,
    );
    final restoredSetting = await control.requestUserSetting();

    expect(savedSetting.nearbyPharmacyLabEnabled, isTrue);
    expect(restoredSetting.nearbyPharmacyLabEnabled, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool('user_setting_user-a_nearby_pharmacy_lab_enabled'),
      isTrue,
    );
  });

  test('복약 대화 실험 설정은 사용자별 기기에 저장된다', () async {
    SharedPreferences.setMockInitialValues({});
    final control = ManageUserSetting(
      userHash: 'user-a',
      useRemotePersistence: false,
    );

    final savedSetting = await control.saveLinkedMedicationChatLabSetting(
      currentSetting: const UserSetting(),
      enabled: true,
    );
    final restoredSetting = await control.requestUserSetting();

    expect(savedSetting.linkedMedicationChatLabEnabled, isTrue);
    expect(restoredSetting.linkedMedicationChatLabEnabled, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(
        'user_setting_user-a_linked_medication_chat_lab_enabled',
      ),
      isTrue,
    );
  });

  test('requestUserSetting restores saved values', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_font_size': 14,
      'user_setting_reading_speed': 0.8,
      'user_setting_language': 'en',
    });
    final control = ManageUserSetting(useRemotePersistence: false);

    final setting = await control.requestUserSetting();

    expect(setting.fontSizeOption, 'small');
    expect(setting.readingSpeedOption, 'slow');
    expect(setting.language, 'en');
  });

  test('requestUserSetting prefers scoped cache over legacy keys', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_user-a_font_size': 20,
      'user_setting_user-a_reading_speed': 1.2,
      'user_setting_user-a_language': 'en',
      'user_setting_font_size': 14,
      'user_setting_reading_speed': 0.8,
      'user_setting_language': 'ko',
    });
    final control = ManageUserSetting(
      userHash: 'user-a',
      useRemotePersistence: false,
    );

    final setting = await control.requestUserSetting();

    expect(setting.userHash, 'user-a');
    expect(setting.fontSizeOption, 'large');
    expect(setting.readingSpeedOption, 'fast');
    expect(setting.language, 'en');
  });

  test('requestUserSetting prefers backend setting and caches it', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_user-a_nearby_pharmacy_lab_enabled': true,
      'user_setting_user-a_linked_medication_chat_lab_enabled': true,
    });
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/settings/user');
      expect(request.url.queryParameters['user_hash'], 'user-a');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'user_hash': 'user-a',
            'font_size': 20,
            'reading_speed': 1.2,
            'language': 'en',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = ManageUserSetting(
      baseUrl: 'http://localhost',
      userHash: 'user-a',
      client: client,
    );

    final setting = await control.requestUserSetting();

    expect(setting.userHash, 'user-a');
    expect(setting.fontSizeOption, 'large');
    expect(setting.readingSpeedOption, 'fast');
    expect(setting.language, 'en');
    expect(setting.nearbyPharmacyLabEnabled, isTrue);
    expect(setting.linkedMedicationChatLabEnabled, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('user_setting_user-a_font_size'), 20);
    control.dispose();
  });

  test('saveUserSetting reports successful server synchronization', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((http.Request request) async {
      expect(request.method, 'PUT');
      final requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      expect(requestBody.containsKey('nearby_pharmacy_lab_enabled'), isFalse);
      expect(
        requestBody.containsKey('linked_medication_chat_lab_enabled'),
        isFalse,
      );
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'user_hash': 'user-a',
            'font_size': 20,
            'reading_speed': 1.2,
            'language': 'ko',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = ManageUserSetting(
      baseUrl: 'http://localhost',
      userHash: 'user-a',
      client: client,
    );

    final result = await control.saveUserSetting(
      currentSetting: const UserSetting(
        nearbyPharmacyLabEnabled: true,
        linkedMedicationChatLabEnabled: true,
      ),
      fontSizeOption: 'large',
      readingSpeedOption: 'fast',
      language: 'ko',
    );

    expect(result.synchronizedWithServer, isTrue);
    expect(result.setting.fontSizeOption, 'large');
    expect(result.setting.readingSpeedOption, 'fast');
    expect(result.setting.nearbyPharmacyLabEnabled, isTrue);
    expect(result.setting.linkedMedicationChatLabEnabled, isTrue);
    control.dispose();
  });

  test(
    'saveUserSetting falls back to local cache when backend fails',
    () async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((http.Request request) async {
        return http.Response('{"detail":"down"}', 500);
      });
      final control = ManageUserSetting(
        baseUrl: 'http://localhost',
        userHash: 'user-a',
        client: client,
      );

      final result = await control.saveUserSetting(
        currentSetting: const UserSetting(),
        fontSizeOption: 'small',
        readingSpeedOption: 'slow',
        language: 'ko',
      );
      final setting = result.setting;

      expect(result.synchronizedWithServer, isFalse);
      expect(setting.fontSize, 14);
      expect(setting.readingSpeed, 0.8);
      expect(setting.language, 'ko');
      expect(setting.userHash, 'user-a');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getInt('user_setting_user-a_font_size'), 14);
      control.dispose();
    },
  );
}
