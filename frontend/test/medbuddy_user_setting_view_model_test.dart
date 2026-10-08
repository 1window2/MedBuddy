// 파일명: medbuddy_user_setting_view_model_test.dart
// 역할: 설정 뷰모델의 설정 전체 저장과 "기기 설정 따르기" 언어 재동기화를 검증한다.

import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_user_setting_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notification_service.dart';

// 클래스명: _SettingServer
// 역할: 한 사용자의 서버 설정을 메모리에 보관하고 조회·저장 요청을 기록한다.
// 속성:
// - stored (UserSetting): 서버에 저장된 설정.
// - puts (List<Map<String, dynamic>>): 받은 저장 요청 본문.
// - available (bool): false이면 모든 요청에 HTTP 503으로 답한다.
class _SettingServer {
  UserSetting stored;
  final puts = <Map<String, dynamic>>[];
  bool available = true;

  // 함수이름: _SettingServer
  // 함수역할: 초기 서버 설정을 보관한다. 매개변수: stored는 서버 설정. 반환값: 초기화된 인스턴스.
  _SettingServer(this.stored);

  // 함수이름: client
  // 함수역할: 설정 조회·저장 요청에 답하는 HTTP 대역을 만든다. 매개변수: 없음. 반환값: MockClient.
  MockClient get client => MockClient((request) async {
    if (!available) {
      return http.Response('{"detail":"unavailable"}', 503);
    }
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
}

// 클래스명: _Fixture
// 역할: 뷰모델과 그 의존 대역, 후속 처리 호출 기록을 묶는다.
// 속성:
// - scheduleRefreshes (int): 예약 알림을 새 언어로 다시 만들기 위한 일정 새로고침 횟수.
// - changes (int): 설정 구독자 알림 횟수.
class _Fixture {
  final _SettingServer server;
  final notifications = RecordingNotificationService();
  late final ManageUserSetting control;
  late final MedBuddyUserSettingViewModel viewModel;
  int scheduleRefreshes = 0;
  int changes = 0;

  // 함수이름: _Fixture
  // 함수역할: 서버 대역에 연결된 설정 컨트롤과 뷰모델을 만든다.
  // 매개변수: server는 서버 대역, remote는 서버 동기화 사용 여부. 반환값: 초기화된 인스턴스.
  _Fixture(this.server, {bool remote = true}) {
    control = ManageUserSetting(
      userHash: 'user-a',
      useRemotePersistence: remote,
      client: server.client,
    );
    viewModel = MedBuddyUserSettingViewModel(
      manageUserSetting: control,
      notificationService: notifications,
      refreshMedicationOverview: () async {},
      refreshMedicationSchedule: () async => scheduleRefreshes++,
      loadMedicationReminderSettings: ({bool notifyAfterLoad = true}) async {},
      onChanged: () => changes++,
      readEnglish: () => viewModel.userSetting.isEnglish,
    );
  }

  // 함수이름: dispose
  // 함수역할: 뷰모델과 컨트롤을 정리한다. 매개변수: 없음. 반환값: 없음.
  void dispose() {
    viewModel.dispose();
    control.dispose();
  }
}

// 함수이름: main
// 함수역할: 설정 뷰모델 검증 사례를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // 함수이름: useDeviceLanguage
  // 함수역할: 테스트 기기의 언어를 바꾸고 종료 시 되돌린다. 매개변수: languageCode. 반환값: 없음.
  void useDeviceLanguage(String languageCode) {
    binding.platformDispatcher.localeTestValue = Locale(languageCode);
    addTearDown(binding.platformDispatcher.clearLocaleTestValue);
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const followsDevice = UserSetting(
    userHash: 'user-a',
    fontSize: 18,
    readingSpeed: 0.9,
    language: 'ko',
    languageMode: 'system',
    notificationDetailMode: 'type_only',
    defaultMorningTime: '07:10',
  );

  // 기기 언어가 저장된 언어와 달라지면 언어만 바꿔 서버까지 다시 저장한다.
  test('기기 설정 따르기는 바뀐 기기 언어를 서버까지 다시 저장한다', () async {
    final fixture = _Fixture(_SettingServer(followsDevice));
    addTearDown(fixture.dispose);
    useDeviceLanguage('ko');
    await fixture.viewModel.loadUserSetting();
    expect(await fixture.viewModel.synchronizeDeviceLanguage(), isFalse);
    expect(fixture.server.puts, isEmpty);

    useDeviceLanguage('en');
    final changesBefore = fixture.changes;
    expect(await fixture.viewModel.synchronizeDeviceLanguage(), isTrue);
    expect(fixture.server.puts, [
      {...followsDevice.toJson(), 'language': 'en'},
    ]);
    expect(fixture.viewModel.userSetting.language, 'en');
    expect(fixture.viewModel.userSetting.languageMode, 'system');
    // 이미 예약된 알림도 새 언어로 다시 만든다.
    expect(fixture.scheduleRefreshes, 1);
    expect(fixture.changes, changesBefore + 1);

    // 같은 언어에서는 다시 저장하지 않고, 기기가 돌아오면 다시 따른다.
    expect(await fixture.viewModel.synchronizeDeviceLanguage(), isFalse);
    expect(fixture.server.puts, hasLength(1));
    useDeviceLanguage('ko');
    expect(await fixture.viewModel.synchronizeDeviceLanguage(), isTrue);
    expect(fixture.server.puts.last['language'], 'ko');
  });

  // 겹친 호출은 한 번만 저장한다.
  test('겹친 기기 언어 재동기화는 한 번만 저장한다', () async {
    final fixture = _Fixture(_SettingServer(followsDevice));
    addTearDown(fixture.dispose);
    useDeviceLanguage('en');
    await fixture.viewModel.loadUserSetting();
    final results = await Future.wait([
      fixture.viewModel.synchronizeDeviceLanguage(),
      fixture.viewModel.synchronizeDeviceLanguage(),
    ]);
    expect(results, [true, true]);
    expect(fixture.server.puts, hasLength(1));
  });

  // 사용자가 언어를 직접 고른 경우에는 기기 언어를 따르지 않는다.
  for (final mode in const ['ko', 'en']) {
    test('명시한 언어 모드($mode)는 기기 언어를 따르지 않는다', () async {
      final fixture = _Fixture(
        _SettingServer(
          followsDevice.copyWith(languageMode: mode, language: mode),
        ),
      );
      addTearDown(fixture.dispose);
      useDeviceLanguage(mode == 'ko' ? 'en' : 'ko');
      await fixture.viewModel.loadUserSetting();
      expect(await fixture.viewModel.synchronizeDeviceLanguage(), isFalse);
      expect(fixture.server.puts, isEmpty);
      expect(fixture.viewModel.userSetting.language, mode);
    });
  }

  // 설정을 불러오기 전의 기본값이나 캐시만 가진 설정을 자동으로 서버에 올리지 않는다.
  test('불러오지 않았거나 캐시만 가진 설정은 자동으로 저장하지 않는다', () async {
    final server = _SettingServer(followsDevice);
    final fixture = _Fixture(server);
    addTearDown(fixture.dispose);
    useDeviceLanguage('en');
    expect(await fixture.viewModel.synchronizeDeviceLanguage(), isFalse);

    await fixture.viewModel.loadUserSetting();
    server.available = false;
    await fixture.viewModel.loadUserSetting();
    expect(fixture.viewModel.userSetting.languageMode, 'system');
    expect(await fixture.viewModel.synchronizeDeviceLanguage(), isFalse);
    expect(server.puts, isEmpty);

    server.available = true;
    await fixture.viewModel.loadUserSetting();
    expect(await fixture.viewModel.synchronizeDeviceLanguage(), isTrue);
    expect(server.puts, hasLength(1));
  });

  // 서버 동기화를 쓰지 않는 로컬 모드에서는 기기 캐시만 갱신한다.
  test('로컬 저장 모드에서도 기기 언어를 따른다', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_user-a_language': 'ko',
      'user_setting_user-a_language_mode': 'system',
    });
    final fixture = _Fixture(_SettingServer(followsDevice), remote: false);
    addTearDown(fixture.dispose);
    useDeviceLanguage('en');
    await fixture.viewModel.loadUserSetting();
    expect(await fixture.viewModel.synchronizeDeviceLanguage(), isTrue);
    expect(fixture.server.puts, isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('user_setting_user-a_language'), 'en');
    expect(
      preferences.getString('user_setting_user-a_language_mode'),
      'system',
    );
  });

  // 설정 화면의 초안 저장: 값 변환 없이 전체를 저장하고 선택지별 저장과 같은 후속 처리를 한다.
  test('saveUserSetting은 설정 전체를 저장하고 알림 후속 처리를 수행한다', () async {
    final fixture = _Fixture(_SettingServer(followsDevice));
    addTearDown(fixture.dispose);
    await fixture.viewModel.loadUserSetting();
    final edited = followsDevice.copyWith(
      medicationNotificationsEnabled: false,
      timeFormat: '12h',
    );
    final result = await fixture.viewModel.saveUserSetting(edited);
    expect(result.synchronizedWithServer, isTrue);
    expect(fixture.server.puts.single, edited.toJson());
    expect(fixture.viewModel.userSetting.toJson(), edited.toJson());
    expect(
      fixture.notifications.cancelAllScheduledMedicationRemindersCount,
      1,
    );
    expect(fixture.notifications.showSensitiveDetails, isFalse);
  });
}
