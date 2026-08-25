// 파일명: manage_user_setting_control_test.dart
// 역할: 사용자 설정의 로컬 저장과 서버 동기화 규칙을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('사용자 설정에 따라 시각을 12시간제와 24시간제로 표시한다', () {
    const koreanSetting = UserSetting(language: 'ko', timeFormat: '12h');
    const englishSetting = UserSetting(language: 'en', timeFormat: '12h');
    const twentyFourHourSetting = UserSetting(timeFormat: '24h');

    expect(koreanSetting.formatTime(18, 5), '오후 6:05');
    expect(englishSetting.formatTime(18, 5), 'PM 6:05');
    expect(twentyFourHourSetting.formatTime(18, 5), '18:05');
  });

  test('saveUserSetting updates all user setting fields', () async {
    SharedPreferences.setMockInitialValues({});
    final control = ManageUserSetting(useRemotePersistence: false);

    final result = await control.saveUserSetting(
      currentSetting: const UserSetting(),
      fontSizeOption: 'large',
      readingSpeedOption: 'fast',
      language: 'en',
      languageMode: 'system',
      timeFormat: '12h',
      medicationNotificationsEnabled: false,
      caregiverNotificationsEnabled: false,
      chatNotificationsEnabled: false,
      notificationDetailMode: 'type_only',
      defaultMorningTime: '07:30',
      defaultLunchTime: '12:30',
      defaultEveningTime: '19:10',
      defaultBedtime: '23:20',
    );
    final setting = result.setting;

    expect(result.synchronizedWithServer, isFalse);
    expect(setting.fontSize, 20);
    expect(setting.readingSpeed, 1.2);
    expect(setting.language, 'en');
    expect(setting.userHash, 'local_patient');
    expect(setting.fontSizeOption, 'large');
    expect(setting.readingSpeedOption, 'fast');
    expect(setting.languageMode, 'system');
    expect(setting.timeFormat, '12h');
    expect(setting.medicationNotificationsEnabled, isFalse);
    expect(setting.caregiverNotificationsEnabled, isFalse);
    expect(setting.chatNotificationsEnabled, isFalse);
    expect(setting.notificationDetailMode, 'type_only');
    expect(setting.defaultMorningTime, '07:30');
    expect(setting.defaultLunchTime, '12:30');
    expect(setting.defaultEveningTime, '19:10');
    expect(setting.defaultBedtime, '23:20');
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

  test('다중 알약 식별 실험 설정은 사용자별 기기에 저장된다', () async {
    SharedPreferences.setMockInitialValues({});
    final control = ManageUserSetting(
      userHash: 'user-a',
      useRemotePersistence: false,
    );

    final savedSetting = await control.saveMultiPillIdentificationLabSetting(
      currentSetting: const UserSetting(),
      enabled: true,
    );
    final restoredSetting = await control.requestUserSetting();

    expect(savedSetting.multiPillIdentificationLabEnabled, isTrue);
    expect(restoredSetting.multiPillIdentificationLabEnabled, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(
        'user_setting_user-a_multi_pill_identification_lab_enabled',
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
      'user_setting_user-a_multi_pill_identification_lab_enabled': true,
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
            'language_mode': 'system',
            'time_format': '12h',
            'medication_notifications_enabled': false,
            'caregiver_notifications_enabled': false,
            'chat_notifications_enabled': false,
            'notification_detail_mode': 'type_only',
            'default_morning_time': '07:10',
            'default_lunch_time': '12:10',
            'default_evening_time': '19:10',
            'default_bedtime': '23:10',
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
    expect(setting.languageMode, 'system');
    expect(setting.timeFormat, '12h');
    expect(setting.medicationNotificationsEnabled, isFalse);
    expect(setting.caregiverNotificationsEnabled, isFalse);
    expect(setting.chatNotificationsEnabled, isFalse);
    expect(setting.notificationDetailMode, 'type_only');
    expect(setting.defaultMorningTime, '07:10');
    expect(setting.defaultLunchTime, '12:10');
    expect(setting.defaultEveningTime, '19:10');
    expect(setting.defaultBedtime, '23:10');
    expect(setting.nearbyPharmacyLabEnabled, isTrue);
    expect(setting.linkedMedicationChatLabEnabled, isTrue);
    expect(setting.multiPillIdentificationLabEnabled, isTrue);
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
      expect(
        requestBody.containsKey('multi_pill_identification_lab_enabled'),
        isFalse,
      );
      expect(requestBody['language_mode'], 'system');
      expect(requestBody['time_format'], '12h');
      expect(requestBody['medication_notifications_enabled'], isFalse);
      expect(requestBody['caregiver_notifications_enabled'], isFalse);
      expect(requestBody['chat_notifications_enabled'], isFalse);
      expect(requestBody['notification_detail_mode'], 'type_only');
      expect(requestBody['default_morning_time'], '07:15');
      expect(requestBody['default_lunch_time'], '12:15');
      expect(requestBody['default_evening_time'], '19:15');
      expect(requestBody['default_bedtime'], '23:15');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'user_hash': 'user-a',
            'font_size': 20,
            'reading_speed': 1.2,
            'language': 'ko',
            'language_mode': 'system',
            'time_format': '12h',
            'medication_notifications_enabled': false,
            'caregiver_notifications_enabled': false,
            'chat_notifications_enabled': false,
            'notification_detail_mode': 'type_only',
            'default_morning_time': '07:15',
            'default_lunch_time': '12:15',
            'default_evening_time': '19:15',
            'default_bedtime': '23:15',
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
        multiPillIdentificationLabEnabled: true,
      ),
      fontSizeOption: 'large',
      readingSpeedOption: 'fast',
      language: 'ko',
      languageMode: 'system',
      timeFormat: '12h',
      medicationNotificationsEnabled: false,
      caregiverNotificationsEnabled: false,
      chatNotificationsEnabled: false,
      notificationDetailMode: 'type_only',
      defaultMorningTime: '07:15',
      defaultLunchTime: '12:15',
      defaultEveningTime: '19:15',
      defaultBedtime: '23:15',
    );

    expect(result.synchronizedWithServer, isTrue);
    expect(result.setting.fontSizeOption, 'large');
    expect(result.setting.readingSpeedOption, 'fast');
    expect(result.setting.languageMode, 'system');
    expect(result.setting.timeFormat, '12h');
    expect(result.setting.medicationNotificationsEnabled, isFalse);
    expect(result.setting.caregiverNotificationsEnabled, isFalse);
    expect(result.setting.chatNotificationsEnabled, isFalse);
    expect(result.setting.notificationDetailMode, 'type_only');
    expect(result.setting.nearbyPharmacyLabEnabled, isTrue);
    expect(result.setting.linkedMedicationChatLabEnabled, isTrue);
    expect(result.setting.multiPillIdentificationLabEnabled, isTrue);
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
