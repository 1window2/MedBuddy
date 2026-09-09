// 파일명: manage_user_setting_control_test.dart
// 역할: 사용자 설정의 로컬 저장과 서버 동기화 규칙을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 함수이름: main
// 함수역할:
// - 사용자별 설정, 실험 기능, 서버 동기화와 로컬 대체 저장 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 사용자 설정에 따라 시각을 12시간제와 24시간제로 표시한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('사용자 설정에 따라 시각을 12시간제와 24시간제로 표시한다', () {
    const koreanSetting = UserSetting(language: 'ko', timeFormat: '12h');
    const englishSetting = UserSetting(language: 'en', timeFormat: '12h');
    const twentyFourHourSetting = UserSetting(timeFormat: '24h');

    expect(koreanSetting.formatTime(18, 5), '오후 6:05');
    expect(englishSetting.formatTime(18, 5), 'PM 6:05');
    expect(twentyFourHourSetting.formatTime(18, 5), '18:05');
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 사용자 설정 저장이 글씨, 읽기 속도와 언어 등 모든 지정 필드를 갱신하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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

  // 함수이름: 구형 실험실 설정 호환 테스트
  // 함수역할: 구형 약국·채팅 스위치 값과 무관하게 현재 설정을 복원하고 알림 선호는 보존한다.
  // 매개변수: 없음. 반환값: 검증 완료.
  test('구형 약국·채팅 실험 설정은 현재 설정에 영향을 주지 않는다', () async {
    for (final legacyEnabled in [false, true]) {
      SharedPreferences.setMockInitialValues({
        'user_setting_user-a_nearby_pharmacy_lab_enabled': legacyEnabled,
        'user_setting_user-a_linked_medication_chat_lab_enabled': legacyEnabled,
        'user_setting_user-a_chat_notifications_enabled': false,
      });
      final control = ManageUserSetting(
        userHash: 'user-a',
        useRemotePersistence: false,
      );
      addTearDown(control.dispose);
      final restored = await control.requestUserSetting();
      expect(restored.chatNotificationsEnabled, isFalse);
      expect(restored.multiPillIdentificationLabEnabled, isFalse);
      expect(
        restored.toJson(),
        const UserSetting(
          userHash: 'user-a',
          chatNotificationsEnabled: false,
        ).toJson(),
      );
      final decoded = UserSetting.fromJson({
        ...restored.toJson(),
        'nearby_pharmacy_lab_enabled': legacyEnabled,
        'linked_medication_chat_lab_enabled': legacyEnabled,
      });
      expect(decoded.toJson(), restored.toJson());
    }
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 다중 알약 식별 실험 설정은 사용자별 기기에 저장된다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestUserSetting restores saved values.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestUserSetting prefers scoped cache over legacy keys.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 설정 조회가 서버 값을 우선하고 사용자별 로컬 캐시에 반영하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('requestUserSetting prefers backend setting and caches it', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_user-a_nearby_pharmacy_lab_enabled': true,
      'user_setting_user-a_linked_medication_chat_lab_enabled': true,
      'user_setting_user-a_multi_pill_identification_lab_enabled': true,
    });
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 사용자별 설정 조회 경로를 검사하고 알림·언어·기본 복약 시각을 포함한 서버 설정을 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 전체 사용자 설정의 HTTP 200 응답.
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
    expect(setting.multiPillIdentificationLabEnabled, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('user_setting_user-a_font_size'), 20);
    control.dispose();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 설정 저장이 서버와 동기화되었음을 결과에 표시하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('saveUserSetting reports successful server synchronization', () async {
    SharedPreferences.setMockInitialValues({});
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 설정 PUT에서 기기 전용 실험 플래그가 빠지고 동기화 대상 필드만 전달되는지 검사한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 저장된 서버 설정을 담은 HTTP 200 응답.
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
    expect(result.setting.multiPillIdentificationLabEnabled, isTrue);
    control.dispose();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 서버 저장 실패 시 사용자별 로컬 캐시에 설정을 보존하고 기기 전용 저장을 보고하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('saveUserSetting falls back to local cache when backend fails', () async {
    SharedPreferences.setMockInitialValues({});
    // Function Name: MockClient callback
    // Description:
    // - Complete the mocked HTTP request with status 500 and the fixed response body without network
    //   access.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
    //   consumed by this fixture.
    // Returns:
    // - Future<http.Response> with status 500.
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
  });
}
