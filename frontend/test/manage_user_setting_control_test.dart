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
  _pendingSyncMain();

  test('홈 일정 설정은 기본값·계정별 복원·서버 왕복을 지원한다', () async {
    expect(const UserSetting().homeScheduleSource, 'self');
    expect(
      UserSetting.fromJson({
        'home_schedule_source': 'automatic',
      }).homeScheduleSource,
      'self',
    );
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['home_schedule_source'], 'patients');
      return http.Response(jsonEncode({'success': true, 'data': body}), 200);
    });
    final control = ManageUserSetting(userHash: 'user-a', client: client);
    addTearDown(control.dispose);
    final result = await control.saveUserSetting(
      const UserSetting()
          .updateUserSetting(
            fontSize: UserSetting.fontSizeFromOption('medium'),
            readingSpeed: UserSetting.readingSpeedFromOption('medium'),
            language: 'ko',
          )
          .copyWith(homeScheduleSource: 'patients'),
    );
    expect(result.synchronizedWithServer, isTrue);
    expect(result.setting.homeScheduleSource, 'patients');
    final restored = ManageUserSetting(
      userHash: 'user-a',
      useRemotePersistence: false,
    );
    final other = ManageUserSetting(
      userHash: 'user-b',
      useRemotePersistence: false,
    );
    addTearDown(restored.dispose);
    addTearDown(other.dispose);
    expect(
      (await restored.requestUserSetting()).homeScheduleSource,
      'patients',
    );
    expect((await other.requestUserSetting()).homeScheduleSource, 'self');
    expect(
      UserSetting.fromJson(result.setting.toJson()).homeScheduleSource,
      'patients',
    );
  });

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
      const UserSetting()
          .updateUserSetting(
            fontSize: UserSetting.fontSizeFromOption('large'),
            readingSpeed: UserSetting.readingSpeedFromOption('fast'),
            language: 'en',
          )
          .copyWith(
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
          ),
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
  // 함수역할: 구형 약국·채팅·다중 알약 스위치 값은 무시하고 알림 선호는 보존한다.
  // 매개변수: 없음. 반환값: 검증 완료.
  test('구형 실험실 설정은 현재 설정에 영향을 주지 않는다', () async {
    for (final legacyEnabled in [false, true]) {
      SharedPreferences.setMockInitialValues({
        'user_setting_user-a_nearby_pharmacy_lab_enabled': legacyEnabled,
        'user_setting_user-a_linked_medication_chat_lab_enabled': legacyEnabled,
        'user_setting_user-a_multi_pill_identification_lab_enabled':
            legacyEnabled,
        'user_setting_user-a_chat_notifications_enabled': false,
      });
      final control = ManageUserSetting(
        userHash: 'user-a',
        useRemotePersistence: false,
      );
      addTearDown(control.dispose);
      final restored = await control.requestUserSetting();
      expect(restored.chatNotificationsEnabled, isFalse);
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
        'multi_pill_identification_lab_enabled': legacyEnabled,
        'multiPillIdentificationLabEnabled': legacyEnabled,
      });
      expect(decoded.toJson(), restored.toJson());
    }
  });

  // 함수이름: 폐기된 설정 저장 방지 테스트
  // 함수역할: 일반 설정 저장·복원이 실험실 키를 다시 생성하지 않는지 확인한다.
  // 매개변수: 없음. 반환값: 저장 및 재조회 검증 완료.
  test('설정 저장은 폐기된 다중 알약 실험 키를 생성하지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final control = ManageUserSetting(
      userHash: 'user-a',
      useRemotePersistence: false,
    );

    addTearDown(control.dispose);
    final saved = await control.saveUserSetting(
      const UserSetting().updateUserSetting(
        fontSize: UserSetting.fontSizeFromOption('large'),
        readingSpeed: UserSetting.readingSpeedFromOption('slow'),
        language: 'en',
      ),
    );
    final restoredSetting = await control.requestUserSetting();

    expect(restoredSetting.toJson(), saved.setting.toJson());
    expect(restoredSetting.fontSize, 20);
    expect(restoredSetting.language, 'en');
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey(
        'user_setting_user-a_multi_pill_identification_lab_enabled',
      ),
      isFalse,
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
      const UserSetting()
          .updateUserSetting(
            fontSize: UserSetting.fontSizeFromOption('large'),
            readingSpeed: UserSetting.readingSpeedFromOption('fast'),
            language: 'ko',
          )
          .copyWith(
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
          ),
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
      const UserSetting().updateUserSetting(
        fontSize: UserSetting.fontSizeFromOption('small'),
        readingSpeed: UserSetting.readingSpeedFromOption('slow'),
        language: 'ko',
      ),
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
  // 캐시에서 읽은 언어도 서버 응답과 같은 기준으로 ko·en만 남아야 화면마다 다르게 판정되지 않는다.
  test('캐시의 언어 값은 ko·en으로 정규화해 복원한다', () async {
    for (final entry in const {
      'EN': 'en',
      'en-US': 'en',
      ' en ': 'en',
      'ko-KR': 'ko',
      'fr': 'ko',
      '': 'ko',
    }.entries) {
      SharedPreferences.setMockInitialValues({
        'user_setting_user-a_language': entry.key,
        'user_setting_language': entry.key,
      });
      final scoped = ManageUserSetting(
        userHash: 'user-a',
        useRemotePersistence: false,
      );
      final legacy = ManageUserSetting(
        userHash: 'user-b',
        useRemotePersistence: false,
      );
      addTearDown(scoped.dispose);
      addTearDown(legacy.dispose);
      expect((await scoped.requestUserSetting()).language, entry.value);
      expect((await legacy.requestUserSetting()).language, entry.value);
    }
  });

  // 설정 전체를 저장하는 경로는 값을 선택지 단계로 바꾸지 않고 그대로 저장·전송한다.
  test('saveUserSettingSnapshot은 설정 전체를 변환 없이 저장한다', () async {
    SharedPreferences.setMockInitialValues({});
    Map<String, dynamic>? sent;
    final control = ManageUserSetting(
      userHash: 'user-a',
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'success': true, 'data': sent}), 200);
      }),
    );
    addTearDown(control.dispose);
    const setting = UserSetting(
      userHash: 'another-user',
      fontSize: 18,
      readingSpeed: 0.9,
      language: 'en',
      languageMode: 'system',
      timeFormat: '12h',
      homeScheduleSource: 'patients',
      medicationNotificationsEnabled: false,
      caregiverNotificationsEnabled: false,
      chatNotificationsEnabled: false,
      notificationDetailMode: 'type_only',
      defaultMorningTime: '07:10',
      defaultLunchTime: '12:20',
      defaultEveningTime: '18:30',
      defaultBedtime: '22:40',
    );
    final result = await control.saveUserSetting(setting);
    final expected = {...setting.toJson(), 'user_hash': 'user-a'};
    expect(result.synchronizedWithServer, isTrue);
    expect(sent, {...expected, 'expected_revision': 0});
    expect(result.setting.toJson(), expected);
    final restored = ManageUserSetting(
      userHash: 'user-a',
      useRemotePersistence: false,
    );
    addTearDown(restored.dispose);
    expect((await restored.requestUserSetting()).toJson(), expected);
  });

  // 서버 사본을 받았는지 알아야 캐시만 가진 설정을 자동으로 올리지 않을 수 있다.
  test('lastLookupReachedServer는 최근 조회가 서버 응답이었는지 알려 준다', () async {
    SharedPreferences.setMockInitialValues({});
    var statusCode = 200;
    final control = ManageUserSetting(
      userHash: 'user-a',
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({'success': true, 'data': const UserSetting().toJson()}),
          statusCode,
        ),
      ),
    );
    addTearDown(control.dispose);
    expect(control.lastLookupReachedServer, isFalse);
    await control.requestUserSetting();
    expect(control.lastLookupReachedServer, isTrue);
    statusCode = 503;
    await control.requestUserSetting();
    expect(control.lastLookupReachedServer, isFalse);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: a failed remote save of a full non-default setting writes exactly the
  //   account-scoped preference keys below, built from the trimmed user hash.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the stored key set is checked and fails the test on mismatch.
  test('failed save writes exactly the scoped user setting keys', () async {
    SharedPreferences.setMockInitialValues({});
    final control = ManageUserSetting(
      baseUrl: 'http://localhost',
      userHash: ' usr_pin ',
      // Function Name: MockClient callback
      // Description:
      // - Rejects the remote save so the pending-sync marker stays stored.
      // Parameters:
      // - request (http.Request): Intercepted settings save request.
      // Returns:
      // - HTTP 500 with a FastAPI error body.
      client: MockClient((_) async => http.Response('{"detail":"down"}', 500)),
    );
    addTearDown(control.dispose);

    final result = await control.saveUserSetting(
      const UserSetting(
        fontSize: 20,
        readingSpeed: 1.2,
        language: 'en',
        languageMode: 'system',
        timeFormat: '12h',
        homeScheduleSource: 'patients',
        medicationNotificationsEnabled: false,
        caregiverNotificationsEnabled: false,
        chatNotificationsEnabled: false,
        notificationDetailMode: 'type_only',
        defaultMorningTime: '07:10',
        defaultLunchTime: '12:20',
        defaultEveningTime: '18:30',
        defaultBedtime: '22:40',
      ),
    );

    expect(result.synchronizedWithServer, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences
          .getKeys()
          .where((key) => key.startsWith('user_setting_'))
          .toSet(),
      {
        'user_setting_usr_pin_font_size',
        'user_setting_usr_pin_medication_search_mode',
        'user_setting_usr_pin_reading_speed',
        'user_setting_usr_pin_language',
        'user_setting_usr_pin_language_mode',
        'user_setting_usr_pin_time_format',
        'user_setting_usr_pin_home_schedule_source',
        'user_setting_usr_pin_medication_notifications_enabled',
        'user_setting_usr_pin_caregiver_notifications_enabled',
        'user_setting_usr_pin_chat_notifications_enabled',
        'user_setting_usr_pin_notification_detail_mode',
        'user_setting_usr_pin_default_morning_time',
        'user_setting_usr_pin_default_lunch_time',
        'user_setting_usr_pin_default_evening_time',
        'user_setting_usr_pin_default_bedtime',
        'user_setting_usr_pin_pending_sync',
        'user_setting_usr_pin_latest_intent',
        'user_setting_usr_pin_server_revision',
        'user_setting_usr_pin_snapshot',
      },
    );
  });
}

// 함수이름: _pendingSyncMain
// 함수역할:
// - 오프라인 저장의 서버 반영 대기 표시가 재조회·재시작·백그라운드 조회에서 유지되고 재전송되는지 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void _pendingSyncMain() {
  // 오프라인에서 끈 복약 알림이 다음 서버 조회로 다시 켜지지 않고, 대기한 저장이 재전송되어야 한다.
  test('오프라인 저장은 다음 조회가 서버 사본으로 덮지 않고 다시 보낸다', () async {
    SharedPreferences.setMockInitialValues({});
    var available = false;
    var stored = const UserSetting(userHash: 'user-a');
    final puts = <Map<String, dynamic>>[];
    var gets = 0;
    // 함수이름: MockClient 콜백
    // 함수역할: available이 false면 503, 아니면 서버 사본을 조회·저장한다.
    // 매개변수: request는 가로챈 요청. 반환값: 대역 응답.
    final client = MockClient((request) async {
      if (!available) return http.Response('{"detail":"down"}', 503);
      if (request.method == 'GET') gets++;
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        puts.add(body);
        stored = UserSetting.fromJson(body);
      }
      return http.Response(
        jsonEncode({'success': true, 'data': stored.toJson()}),
        200,
      );
    });
    final foreground = ManageUserSetting(userHash: 'user-a', client: client);
    addTearDown(foreground.dispose);
    final saved = await foreground.saveUserSetting(
      const UserSetting(
        medicationNotificationsEnabled: false,
        notificationDetailMode: 'type_only',
      ),
    );
    expect(saved.synchronizedWithServer, isFalse);
    expect(foreground.hasPendingSave, isTrue);

    // 앱 재시작이나 12시간 작업처럼 새 인스턴스가 서버 연결 없이 읽어도 기기 값을 쓴다.
    final restartedOffline = ManageUserSetting(
      userHash: 'user-a',
      client: client,
    );
    addTearDown(restartedOffline.dispose);
    final offlineRead = await restartedOffline.requestUserSetting();
    expect(offlineRead.medicationNotificationsEnabled, isFalse);
    expect(restartedOffline.hasPendingSave, isTrue);
    expect(restartedOffline.lastLookupReachedServer, isFalse);

    available = true;
    final worker = ManageUserSetting(userHash: 'user-a', client: client);
    addTearDown(worker.dispose);
    final onlineRead = await worker.requestUserSetting();
    expect(gets, 0);
    expect(puts, hasLength(1));
    expect(puts.single['medication_notifications_enabled'], isFalse);
    expect(puts.single['notification_detail_mode'], 'type_only');
    expect(onlineRead.medicationNotificationsEnabled, isFalse);
    expect(worker.hasPendingSave, isFalse);
    expect(worker.lastLookupReachedServer, isTrue);

    // 반영이 끝나면 다시 서버 사본을 기준으로 읽는다.
    stored = stored.copyWith(fontSize: 24);
    final afterSync = await worker.requestUserSetting();
    expect(gets, 1);
    expect(puts, hasLength(1));
    expect(afterSync.fontSize, 24);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('user_setting_user-a_font_size'), 24);
    expect(preferences.getString('user_setting_user-a_pending_sync'), isNull);
  });

  // 대기 표시는 계정별이라 다른 계정의 조회는 평소처럼 서버 사본을 캐시한다.
  test('서버 반영 대기 표시는 계정별로 적용된다', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_user-a_pending_sync': 'token',
      'user_setting_user-a_font_size': 24,
    });
    final requests = <String>[];
    // 함수이름: MockClient 콜백
    // 함수역할: 요청을 기록하고 PUT은 본문을, GET은 user-b의 서버 사본을 돌려준다.
    // 매개변수: request는 가로챈 요청. 반환값: 대역 응답.
    final client = MockClient((request) async {
      requests.add(
        '${request.method} ${request.url.queryParameters['user_hash']}',
      );
      final setting = request.method == 'PUT'
          ? jsonDecode(request.body) as Map<String, dynamic>
          : const UserSetting(userHash: 'user-b', fontSize: 14).toJson();
      return http.Response(jsonEncode({'success': true, 'data': setting}), 200);
    });
    final other = ManageUserSetting(userHash: 'user-b', client: client);
    addTearDown(other.dispose);
    expect((await other.requestUserSetting()).fontSize, 14);
    expect(other.hasPendingSave, isFalse);
    expect(requests, ['GET user-b']);
    final owner = ManageUserSetting(userHash: 'user-a', client: client);
    addTearDown(owner.dispose);
    expect((await owner.requestUserSetting()).fontSize, 24);
    expect(requests, ['GET user-b', 'PUT user-a']);
  });
}
