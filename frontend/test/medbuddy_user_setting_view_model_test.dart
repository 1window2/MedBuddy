// 파일명: medbuddy_user_setting_view_model_test.dart
// 역할: 설정 뷰모델의 설정 전체 저장과 "기기 설정 따르기" 언어 재동기화를 검증한다.

import 'dart:async';
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
// 역할: 설정 저장·조회와 지연/실패를 재현하는 서버 대역.
// 주요 책임: 요청 횟수를 기록하고 대기 게이트·503 응답·성공 저장을 제어한다.
// 속성: stored (UserSetting): 서버 사본; puts (List<Map<String,dynamic>>): 성공 PUT 본문; available (bool): 서버 가용성; gets/putAttempts/putFailuresRemaining (int): 횟수·남은 실패; putReady (Completer<void>?): PUT 해제 게이트.
class _SettingServer {
  UserSetting stored;
  final puts = <Map<String, dynamic>>[];
  bool available = true;
  int gets = 0;
  int putAttempts = 0;
  int putFailuresRemaining = 0;
  Completer<void>? putReady;

  // Function Name: _SettingServer
  // Description: Stores the initial server-side settings for the HTTP fixture.
  // Parameters: stored (UserSetting): initial server copy.
  // Returns: A _SettingServer fixture.
  _SettingServer(this.stored);

  // 함수이름: client
  // 함수역할: GET·PUT 횟수를 기록하고 PUT 게이트를 기다린 뒤 가용성·예약 실패에 따라 503 또는 저장된 설정을 응답한다.
  // 매개변수: 없음.
  // 반환값: MockClient: 성공한 PUT만 본문 기록과 stored를 갱신하는 서버 대역.
  MockClient get client => MockClient((request) async {
    if (request.method == 'GET') gets++;
    if (request.method == 'PUT') {
      putAttempts++;
      await putReady?.future;
    }
    if (!available) {
      return http.Response('{"detail":"unavailable"}', 503);
    }
    if (request.method == 'PUT') {
      if (putFailuresRemaining > 0) {
        putFailuresRemaining--;
        return http.Response('{"detail":"unavailable"}', 503);
      }
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

// Class Name: _Fixture
// Role: Settings view-model fixture with observable side effects.
// Responsibilities: Connects persistence, recorded notifications and refresh/change counters for language synchronization tests.
// Attributes: server (_SettingServer): HTTP state; notifications (RecordingNotificationService): reminder calls; control (ManageUserSetting)/viewModel (MedBuddyUserSettingViewModel): tested objects; scheduleRefreshes/changes (int): effects.
class _Fixture {
  final _SettingServer server;
  final notifications = RecordingNotificationService();
  late final ManageUserSetting control;
  late final MedBuddyUserSettingViewModel viewModel;
  int scheduleRefreshes = 0;
  int changes = 0;

  // Function Name: _Fixture
  // Description: Connects the user-a controller and view model to the server and records schedule refreshes and subscriber notifications.
  // Parameters: server (_SettingServer): HTTP fixture; remote (bool): enable server persistence.
  // Returns: An initialized _Fixture.
  _Fixture(this.server, {bool remote = true}) {
    control = ManageUserSetting(
      userHash: 'user-a',
      useRemotePersistence: remote,
      client: server.client,
    );
    viewModel = MedBuddyUserSettingViewModel(
      manageUserSetting: control,
      notificationService: notifications,
      refreshMedicationOverview: ({Future<void>? startedTodayInfo}) async {},
      refreshMedicationSchedule: () async => scheduleRefreshes++,
      loadMedicationReminderSettings: ({bool notifyAfterLoad = true}) async {},
      onChanged: () => changes++,
      readEnglish: () => viewModel.userSetting.isEnglish,
    );
  }

  // Function Name: dispose
  // Description: Disposes the settings view model before its persistence controller.
  // Parameters: None.
  // Returns: None.
  void dispose() {
    viewModel.dispose();
    control.dispose();
  }
}

// 함수이름: main
// 함수역할: 설정 뷰모델 검증 사례를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // Function Name: useDeviceLanguage
  // Description: Overrides the device locale and registers restoration after the case.
  // Parameters: languageCode (String): simulated device language.
  // Returns: None.
  void useDeviceLanguage(String languageCode) {
    binding.platformDispatcher.localeTestValue = Locale(languageCode);
    addTearDown(binding.platformDispatcher.clearLocaleTestValue);
  }

  // Function Name: setUp
  // Description: Clears mocked device preferences before each synchronization case.
  // Parameters: None.
  // Returns: None; starts each case with an empty cache.
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

  // 함수이름: test: '기기 설정 따르기는 바뀐 기기 언어를 서버까지 다시 저장한다'
  // 함수역할: 기기 언어 따르기 설정에서 동일 언어·영어 변경·중복 호출·한국어 복귀를 순서대로 요청한다.
  // 매개변수: 없음.
  // 반환값: 실제 변경 때만 언어와 revision을 저장하고 일정/구독자는 한 번 갱신되며 system 모드는 유지된다.
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
      {...followsDevice.toJson(), 'language': 'en', 'expected_revision': 0},
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

  // Function Name: test: '겹친 기기 언어 재동기화는 한 번만 저장한다'
  // Description: Starts two device-language synchronization calls together after loading system-following settings.
  // Parameters: None.
  // Returns: Both report true while sharing exactly one server PUT.
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
    // Function Name: test: '명시한 언어 모드($mode)는 기기 언어를 따르지 않는다'
    // Description: Loads each explicit language mode while the device uses the opposite language.
    // Parameters: None.
    // Returns: Synchronization returns false, sends no PUT and retains the explicit language.
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

  // Function Name: test: '불러오지 않았거나 캐시만 가진 설정은 자동으로 저장하지 않는다'
  // Description: Attempts synchronization before loading, after a cache fallback and after a later successful server lookup.
  // Parameters: None.
  // Returns: No automatic save occurs without an authoritative loaded copy; one save occurs after lookup recovery.
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

  // Function Name: test: '로컬 저장 모드에서도 기기 언어를 따른다'
  // Description: Loads system-following Korean preferences with remote persistence disabled on an English device.
  // Parameters: None.
  // Returns: Only local language changes to en, system mode remains and the server receives no PUT.
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

  // 함수이름: test: 'saveUserSetting은 설정 전체를 저장하고 알림 후속 처리를 수행한다'
  // 함수역할: 전체 초안에서 복약 알림을 끄고 12시간 표기로 저장한다.
  // 매개변수: 없음.
  // 반환값: 전체 설정과 expected_revision이 전송되고 결과가 일치하며 예약 알림 취소와 민감정보 숨김이 적용된다.
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
    expect(fixture.server.puts.single, {
      ...edited.toJson(),
      'expected_revision': 0,
    });
    expect(fixture.viewModel.userSetting.toJson(), edited.toJson());
    expect(fixture.notifications.cancelAllScheduledMedicationRemindersCount, 1);
    expect(fixture.notifications.showSensitiveDetails, isFalse);
  });

  // 함수이름: test: '실패한 언어 저장은 반복하지 않고 복귀 시 같은 언어도 재시도한다'
  // 함수역할: 기기 언어 저장을 오프라인에서 실패시킨 뒤 일반 호출과 복귀 재시도를 각각 수행한다.
  // 매개변수: 없음.
  // 반환값: 일반 호출은 실패를 반복하지 않고 복귀 요청만 보류 저장을 재전송하며 성공 뒤 추가 PUT은 없다.
  test('실패한 언어 저장은 반복하지 않고 복귀 시 같은 언어도 재시도한다', () async {
    final fixture = _Fixture(_SettingServer(followsDevice));
    addTearDown(fixture.dispose);
    useDeviceLanguage('en');
    await fixture.viewModel.loadUserSetting();
    fixture.server.available = false;
    expect(await fixture.viewModel.synchronizeDeviceLanguage(), isTrue);
    expect(fixture.viewModel.userSetting.language, 'en');
    expect(fixture.server.putAttempts, 1);
    expect(await fixture.viewModel.synchronizeDeviceLanguage(), isFalse);
    expect(fixture.server.putAttempts, 1);

    fixture.server.available = true;
    expect(
      await fixture.viewModel.synchronizeDeviceLanguage(
        retryRemoteLookup: true,
      ),
      isTrue,
    );
    expect(fixture.server.stored.language, 'en');
    expect(fixture.server.putAttempts, 2);
    expect(fixture.server.gets, 1);
    expect(
      await fixture.viewModel.synchronizeDeviceLanguage(
        retryRemoteLookup: true,
      ),
      isFalse,
    );
    expect(fixture.server.putAttempts, 2);
  });

  // 함수이름: test: '시작 전 합쳐진 복귀 요청은 대기 중 실패한 수동 저장을 재시도한다'
  // 함수역할: 수동 저장이 대기 중 실패하도록 하고 시작 전 언어/복귀 요청을 합친다.
  // 매개변수: 없음.
  // 반환값: 합친 Future는 동일하고 복귀 요청이 실패한 전체 초안을 한 번 더 저장하여 최신 편집값을 보존한다.
  test('시작 전 합쳐진 복귀 요청은 대기 중 실패한 수동 저장을 재시도한다', () async {
    final fixed = followsDevice.copyWith(languageMode: 'ko');
    final fixture = _Fixture(_SettingServer(fixed));
    addTearDown(fixture.dispose);
    useDeviceLanguage('en');
    await fixture.viewModel.loadUserSetting();
    fixture.server.putReady = Completer<void>();
    fixture.server.putFailuresRemaining = 1;
    final edited = fixed.copyWith(fontSize: 24);
    final manual = fixture.viewModel.saveUserSetting(edited);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.server.putAttempts, 1);

    final locale = fixture.viewModel.synchronizeDeviceLanguage();
    final resume = fixture.viewModel.synchronizeDeviceLanguage(
      retryRemoteLookup: true,
    );
    expect(resume, same(locale));
    fixture.server.putReady!.complete();
    expect((await manual).synchronizedWithServer, isFalse);
    expect(await Future.wait([locale, resume]), [true, true]);
    expect(fixture.server.putAttempts, 2);
    expect(fixture.server.gets, 1);
    expect(fixture.server.stored.toJson(), edited.toJson());
    expect(fixture.viewModel.userSetting.toJson(), edited.toJson());
  });

  // 함수이름: test: '시작 전 합쳐진 복귀 요청은 실패했던 서버 조회도 재시도한다'
  // 함수역할: 고정 언어 설정의 첫 GET을 실패시킨 후 실행 전 언어/복귀 요청을 합친다.
  // 매개변수: 없음.
  // 반환값: GET은 재시도되지만 언어 변경 결과는 false이고 PUT 없이 서버 고정 언어를 복원한다.
  test('시작 전 합쳐진 복귀 요청은 실패했던 서버 조회도 재시도한다', () async {
    final fixed = followsDevice.copyWith(languageMode: 'ko');
    final fixture = _Fixture(_SettingServer(fixed));
    addTearDown(fixture.dispose);
    useDeviceLanguage('en');
    fixture.server.available = false;
    await fixture.viewModel.loadUserSetting();
    fixture.server.available = true;

    final locale = fixture.viewModel.synchronizeDeviceLanguage();
    final resume = fixture.viewModel.synchronizeDeviceLanguage(
      retryRemoteLookup: true,
    );
    expect(resume, same(locale));
    expect(await Future.wait([locale, resume]), [false, false]);
    expect(fixture.server.gets, 2);
    expect(fixture.server.putAttempts, 0);
    expect(fixture.viewModel.userSetting.toJson(), fixed.toJson());
  });

  for (final retrySucceeds in [true, false]) {
    // 함수이름: test: '진행 중 합쳐진 복귀 요청은 한 번만 추가 시도한다: $retrySucceeds'
    // 함수역할: 진행 중인 자동 저장에 복귀 재시도를 합치고 재시도 대기 중 복귀 요청을 세 번 더 보낸다.
    // 매개변수: 없음.
    // 반환값: 한 실행은 추가 PUT 한 번으로 제한되며 실패가 남은 경우에만 다음 독립 복귀에서 다시 저장한다.
    test('진행 중 합쳐진 복귀 요청은 한 번만 추가 시도한다: $retrySucceeds', () async {
      final fixture = _Fixture(_SettingServer(followsDevice));
      addTearDown(fixture.dispose);
      useDeviceLanguage('en');
      await fixture.viewModel.loadUserSetting();
      final firstReady = Completer<void>();
      final retryReady = Completer<void>();
      fixture.server.putReady = firstReady;
      fixture.server.putFailuresRemaining = retrySucceeds ? 1 : 2;
      final locale = fixture.viewModel.synchronizeDeviceLanguage();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.server.putAttempts, 1);
      final resume = fixture.viewModel.synchronizeDeviceLanguage(
        retryRemoteLookup: true,
      );
      expect(resume, same(locale));
      fixture.server.putReady = retryReady;
      firstReady.complete();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.server.putAttempts, 2);

      // 추가 시도 중 들어온 복귀 알림은 실패해도 세 번째 요청을 만들지 않는다.
      final repeatedResumes = List.generate(
        3,
        (_) => fixture.viewModel.synchronizeDeviceLanguage(
          retryRemoteLookup: true,
        ),
      );
      retryReady.complete();
      expect(
        await Future.wait([locale, resume, ...repeatedResumes]),
        everyElement(isTrue),
      );
      expect(fixture.server.putAttempts, 2);
      expect(fixture.server.gets, 1);
      expect(fixture.server.stored.language, retrySucceeds ? 'en' : 'ko');
      expect(fixture.viewModel.userSetting.language, 'en');
      expect(await fixture.viewModel.synchronizeDeviceLanguage(), isFalse);
      expect(fixture.server.putAttempts, 2);

      // 묶음이 끝난 뒤 별도로 복귀하면 남은 실패만 다시 보낸다.
      expect(
        await fixture.viewModel.synchronizeDeviceLanguage(
          retryRemoteLookup: true,
        ),
        !retrySucceeds,
      );
      expect(fixture.server.putAttempts, retrySucceeds ? 2 : 3);
      expect(fixture.server.stored.language, 'en');
    });
  }

  // 함수이름: test: '진행 중 추가된 재시도 뒤에도 대기한 수동 편집이 마지막으로 저장된다'
  // 함수역할: 자동 언어 저장 실패에 복귀 재시도를 추가한 동안 수동 고정 언어 편집을 대기시킨다.
  // 매개변수: 없음.
  // 반환값: 자동 재시도 뒤 수동 편집이 마지막에 저장되어 서버와 화면이 편집값으로 끝난다.
  test('진행 중 추가된 재시도 뒤에도 대기한 수동 편집이 마지막으로 저장된다', () async {
    final fixture = _Fixture(_SettingServer(followsDevice));
    addTearDown(fixture.dispose);
    useDeviceLanguage('en');
    await fixture.viewModel.loadUserSetting();
    fixture.server.putReady = Completer<void>();
    fixture.server.putFailuresRemaining = 1;
    final locale = fixture.viewModel.synchronizeDeviceLanguage();
    await Future<void>.delayed(Duration.zero);
    expect(fixture.server.putAttempts, 1);
    final edited = followsDevice.copyWith(languageMode: 'ko', fontSize: 24);
    final manual = fixture.viewModel.saveUserSetting(edited);
    final resume = fixture.viewModel.synchronizeDeviceLanguage(
      retryRemoteLookup: true,
    );
    fixture.server.putReady!.complete();

    expect(await Future.wait([locale, resume]), [true, true]);
    expect((await manual).synchronizedWithServer, isTrue);
    expect(fixture.server.putAttempts, 3);
    expect(fixture.server.puts.map((setting) => setting['language']), [
      'en',
      'ko',
    ]);
    expect(fixture.server.stored.toJson(), edited.toJson());
    expect(fixture.viewModel.userSetting.toJson(), edited.toJson());
  });

  for (final inFlight in [false, true]) {
    // 함수이름: test: '합쳐진 복귀 요청도 폐기 후에는 추가 요청을 하지 않는다: $inFlight'
    // 함수역할: 요청 시작 전 또는 진행 중에 복귀 요청을 합친 뒤 뷰모델을 폐기한다.
    // 매개변수: 없음.
    // 반환값: 이미 시작한 PUT 외 추가 통신·구독자 알림·화면 설정 변경이 없고 두 호출은 진행 여부에 맞는 결과를 공유한다.
    test('합쳐진 복귀 요청도 폐기 후에는 추가 요청을 하지 않는다: $inFlight', () async {
      final fixture = _Fixture(_SettingServer(followsDevice));
      addTearDown(fixture.dispose);
      useDeviceLanguage('en');
      await fixture.viewModel.loadUserSetting();
      final changesBefore = fixture.changes;
      fixture.server.putReady = Completer<void>();
      fixture.server.putFailuresRemaining = 1;
      final locale = fixture.viewModel.synchronizeDeviceLanguage();
      if (inFlight) {
        await Future<void>.delayed(Duration.zero);
        expect(fixture.server.putAttempts, 1);
      }
      final resume = fixture.viewModel.synchronizeDeviceLanguage(
        retryRemoteLookup: true,
      );
      fixture.viewModel.dispose();
      fixture.server.putReady!.complete();

      expect(await Future.wait([locale, resume]), [inFlight, inFlight]);
      expect(fixture.server.putAttempts, inFlight ? 1 : 0);
      expect(fixture.server.gets, 1);
      expect(fixture.changes, changesBefore);
      expect(fixture.viewModel.userSetting.toJson(), followsDevice.toJson());
    });
  }

  // 함수이름: test: '캐시 조회 실패 후 복귀는 서버의 고정 언어를 복원하고 자동 저장하지 않는다'
  // 함수역할: 캐시에는 system이 있지만 서버는 고정 한국어인 상태에서 GET 실패 후 복귀 재조회한다.
  // 매개변수: 없음.
  // 반환값: 서버 고정 모드를 복원하고 GET만 두 번 수행하며 자동 PUT은 없다.
  test('캐시 조회 실패 후 복귀는 서버의 고정 언어를 복원하고 자동 저장하지 않는다', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_user-a_language': 'ko',
      'user_setting_user-a_language_mode': 'system',
    });
    final fixture = _Fixture(
      _SettingServer(followsDevice.copyWith(languageMode: 'ko')),
    );
    addTearDown(fixture.dispose);
    useDeviceLanguage('en');
    fixture.server.available = false;
    await fixture.viewModel.loadUserSetting();
    expect(await fixture.viewModel.synchronizeDeviceLanguage(), isFalse);
    fixture.server.available = true;
    expect(
      await fixture.viewModel.synchronizeDeviceLanguage(
        retryRemoteLookup: true,
      ),
      isFalse,
    );
    expect(fixture.viewModel.userSetting.languageMode, 'ko');
    expect(fixture.server.gets, 2);
    expect(fixture.server.putAttempts, 0);
  });

  for (final mode in const ['ko', 'en']) {
    // 함수이름: test: '고정 언어($mode)의 실패한 설정 전체를 복귀마다 한 번 재시도한다'
    // 함수역할: 고정 언어의 전체 초안 저장을 실패시키고 반복 복귀 및 겹친 온라인 복귀를 수행한다.
    // 매개변수: 없음.
    // 반환값: 복귀마다 최대 한 번 재전송하고 초안을 유지하며 성공 뒤 추가 재시도 없이 다음 정상 GET이 가능하다.
    test('고정 언어($mode)의 실패한 설정 전체를 복귀마다 한 번 재시도한다', () async {
      final fixed = followsDevice.copyWith(languageMode: mode, language: mode);
      final fixture = _Fixture(_SettingServer(fixed));
      addTearDown(fixture.dispose);
      useDeviceLanguage(mode == 'ko' ? 'en' : 'ko');
      await fixture.viewModel.loadUserSetting();
      fixture.server.available = false;
      final edited = fixed.copyWith(
        fontSize: 24,
        readingSpeed: 1.2,
        chatNotificationsEnabled: false,
        timeFormat: '12h',
      );
      expect(
        (await fixture.viewModel.saveUserSetting(
          edited,
        )).synchronizedWithServer,
        isFalse,
      );
      await fixture.viewModel.loadUserSetting();
      expect(fixture.server.gets, 1);
      expect(await fixture.viewModel.synchronizeDeviceLanguage(), isFalse);
      expect(fixture.server.putAttempts, 1);

      for (var attempt = 2; attempt <= 3; attempt++) {
        expect(
          await fixture.viewModel.synchronizeDeviceLanguage(
            retryRemoteLookup: true,
          ),
          isTrue,
        );
        expect(fixture.server.putAttempts, attempt);
        expect(fixture.viewModel.userSetting.toJson(), edited.toJson());
      }

      fixture.server.available = true;
      expect(
        await Future.wait([
          fixture.viewModel.synchronizeDeviceLanguage(retryRemoteLookup: true),
          fixture.viewModel.synchronizeDeviceLanguage(retryRemoteLookup: true),
        ]),
        [true, true],
      );
      expect(fixture.server.putAttempts, 4);
      expect(fixture.server.puts.single, {
        ...edited.toJson(),
        'expected_revision': 0,
      });
      expect(fixture.server.gets, 1);
      expect(fixture.viewModel.userSetting.toJson(), edited.toJson());
      expect(
        await fixture.viewModel.synchronizeDeviceLanguage(
          retryRemoteLookup: true,
        ),
        isFalse,
      );
      expect(fixture.server.putAttempts, 4);
      await fixture.viewModel.loadUserSetting();
      expect(fixture.server.gets, 2);
    });
  }

  // 함수이름: test: '고정 언어의 재시도 뒤 대기한 새 편집이 마지막으로 저장된다'
  // 함수역할: 고정 언어의 실패 저장 재전송을 대기시키고 새 언어 편집을 저장 요청한다.
  // 매개변수: 없음.
  // 반환값: 재전송 뒤 새 편집이 직렬로 저장되어 서버·화면 모두 마지막 편집값을 갖는다.
  test('고정 언어의 재시도 뒤 대기한 새 편집이 마지막으로 저장된다', () async {
    final fixed = followsDevice.copyWith(languageMode: 'ko');
    final fixture = _Fixture(_SettingServer(fixed));
    addTearDown(fixture.dispose);
    useDeviceLanguage('en');
    await fixture.viewModel.loadUserSetting();
    fixture.server.available = false;
    await fixture.viewModel.saveUserSetting(fixed.copyWith(fontSize: 24));
    fixture.server.available = true;
    fixture.server.putReady = Completer<void>();
    final retry = fixture.viewModel.synchronizeDeviceLanguage(
      retryRemoteLookup: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(fixture.server.putAttempts, 2);
    final edited = fixed.copyWith(languageMode: 'en', language: 'en');
    final manual = fixture.viewModel.saveUserSetting(edited);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.server.putAttempts, 2);
    fixture.server.putReady!.complete();
    await retry;
    await manual;
    expect(fixture.server.putAttempts, 3);
    expect(fixture.viewModel.userSetting.toJson(), edited.toJson());
    expect(fixture.server.stored.toJson(), edited.toJson());
  });

  // 함수이름: test: '고정 언어의 실패한 설정도 폐기 뒤에는 재시도하지 않는다'
  // 함수역할: 고정 언어 저장 실패 후 뷰모델을 폐기하고 서버를 복구해 복귀 재시도를 요청한다.
  // 매개변수: 없음.
  // 반환값: 재시도는 false이고 최초 실패 PUT 이후 요청이 늘지 않는다.
  test('고정 언어의 실패한 설정도 폐기 뒤에는 재시도하지 않는다', () async {
    final fixture = _Fixture(
      _SettingServer(followsDevice.copyWith(languageMode: 'ko')),
    );
    addTearDown(fixture.dispose);
    await fixture.viewModel.loadUserSetting();
    fixture.server.available = false;
    await fixture.viewModel.saveUserSetting(fixture.viewModel.userSetting);
    fixture.viewModel.dispose();
    fixture.server.available = true;
    expect(
      await fixture.viewModel.synchronizeDeviceLanguage(
        retryRemoteLookup: true,
      ),
      isFalse,
    );
    expect(fixture.server.putAttempts, 1);
  });

  // 함수이름: test: '서버에 저장하지 못한 편집은 재조회와 언어 재시도로 사라지지 않는다'
  // 함수역할: 글씨 크기와 아침 시각의 오프라인 편집 뒤 재조회하고 기기 언어를 영어로 바꿔 재시도한다.
  // 매개변수: 없음.
  // 반환값: 보류 편집을 서버 사본으로 덮지 않으며 글씨 크기·시각·최신 언어가 함께 저장된다.
  test('서버에 저장하지 못한 편집은 재조회와 언어 재시도로 사라지지 않는다', () async {
    final fixture = _Fixture(_SettingServer(followsDevice));
    addTearDown(fixture.dispose);
    useDeviceLanguage('ko');
    await fixture.viewModel.loadUserSetting();
    fixture.server.available = false;
    final edited = followsDevice.copyWith(
      fontSize: 24,
      defaultMorningTime: '06:15',
    );
    expect(
      (await fixture.viewModel.saveUserSetting(edited)).synchronizedWithServer,
      isFalse,
    );
    fixture.server.available = true;
    await fixture.viewModel.loadUserSetting();
    expect(fixture.viewModel.userSetting.fontSize, 24);
    expect(fixture.server.gets, 1);
    useDeviceLanguage('en');
    await fixture.viewModel.synchronizeDeviceLanguage(retryRemoteLookup: true);
    expect(fixture.server.stored.fontSize, 24);
    expect(fixture.server.stored.defaultMorningTime, '06:15');
    expect(fixture.server.stored.language, 'en');
    expect(fixture.server.gets, 1);
  });

  // 함수이름: test: '느린 자동 저장 뒤 사용자가 고른 고정 언어가 마지막으로 저장된다'
  // 함수역할: 느린 system 언어 자동 저장 동안 고정 한국어와 글씨 크기 편집을 저장한다.
  // 매개변수: 없음.
  // 반환값: 자동 저장 뒤 수동 값이 마지막으로 반영되고 이후 기기 언어 동기화는 하지 않는다.
  test('느린 자동 저장 뒤 사용자가 고른 고정 언어가 마지막으로 저장된다', () async {
    final fixture = _Fixture(_SettingServer(followsDevice));
    addTearDown(fixture.dispose);
    useDeviceLanguage('en');
    await fixture.viewModel.loadUserSetting();
    fixture.server.putReady = Completer<void>();
    final automatic = fixture.viewModel.synchronizeDeviceLanguage();
    await Future<void>.delayed(Duration.zero);
    expect(fixture.server.putAttempts, 1);
    final manual = fixture.viewModel.saveUserSetting(
      followsDevice.copyWith(languageMode: 'ko', fontSize: 24),
    );
    await Future<void>.delayed(Duration.zero);
    expect(fixture.server.putAttempts, 1);
    fixture.server.putReady!.complete();
    await automatic;
    await manual;
    expect(fixture.server.stored.languageMode, 'ko');
    expect(fixture.viewModel.userSetting.languageMode, 'ko');
    expect(fixture.viewModel.userSetting.fontSize, 24);
    expect(await fixture.viewModel.synchronizeDeviceLanguage(), isFalse);
    expect(fixture.server.putAttempts, 2);
  });

  // 함수이름: test: '저장 요청 중 기기 언어가 다시 바뀌면 최신 언어까지 반영한다'
  // 함수역할: 영어 자동 저장 응답 대기 중 기기 언어를 한국어로 되돌려 동기화를 다시 요청한다.
  // 매개변수: 없음.
  // 반환값: 두 호출이 성공하고 en 다음 ko가 저장되어 최종 언어는 ko이다.
  test('저장 요청 중 기기 언어가 다시 바뀌면 최신 언어까지 반영한다', () async {
    final fixture = _Fixture(_SettingServer(followsDevice));
    addTearDown(fixture.dispose);
    useDeviceLanguage('en');
    await fixture.viewModel.loadUserSetting();
    fixture.server.putReady = Completer<void>();
    final first = fixture.viewModel.synchronizeDeviceLanguage();
    await Future<void>.delayed(Duration.zero);
    expect(fixture.server.putAttempts, 1);
    useDeviceLanguage('ko');
    final second = fixture.viewModel.synchronizeDeviceLanguage();
    fixture.server.putReady!.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(fixture.server.puts.map((setting) => setting['language']), [
      'en',
      'ko',
    ]);
    expect(fixture.viewModel.userSetting.language, 'ko');
  });

  // Function Name: test: '재시작 전에 남은 미반영 설정은 시작 조회 뒤 복귀 때 다시 저장한다'
  // Description: Restarts the fixture after an offline edit disabling medication reminders, then retries on resume when online.
  // Parameters: None.
  // Returns: Startup preserves the pending local edit without another GET; resume persists it and clears pending-save state.
  test('재시작 전에 남은 미반영 설정은 시작 조회 뒤 복귀 때 다시 저장한다', () async {
    final fixed = followsDevice.copyWith(languageMode: 'ko');
    final first = _Fixture(_SettingServer(fixed));
    addTearDown(first.dispose);
    await first.viewModel.loadUserSetting();
    first.server.available = false;
    final edited = fixed.copyWith(medicationNotificationsEnabled: false);
    expect(
      (await first.viewModel.saveUserSetting(edited)).synchronizedWithServer,
      isFalse,
    );

    final restarted = _Fixture(first.server);
    addTearDown(restarted.dispose);
    await restarted.viewModel.loadUserSetting();
    expect(
      restarted.viewModel.userSetting.medicationNotificationsEnabled,
      isFalse,
    );
    expect(first.server.gets, 1);

    first.server.available = true;
    expect(
      await restarted.viewModel.synchronizeDeviceLanguage(
        retryRemoteLookup: true,
      ),
      isTrue,
    );
    expect(first.server.stored.medicationNotificationsEnabled, isFalse);
    expect(restarted.control.hasPendingSave, isFalse);
  });

  // 함수이름: test 콜백
  // 함수역할: 오늘 일정 로드가 설정 응답을 기다리지 않고 시작되고, 개요 갱신은 그 로드를 이어받는지 검증한다.
  // 매개변수: 없음.
  // 반환값: Future<void>; 기대와 다르면 테스트가 실패한다.
  test('오늘 일정 로드는 설정 요청과 함께 시작되고 개요 갱신이 이어받는다', () async {
    final settingResponse = Completer<void>();
    final control = ManageUserSetting(
      userHash: 'user-a',
      client: MockClient((request) async {
        await settingResponse.future;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': const UserSetting(userHash: 'user-a').toJson(),
          }),
          200,
        );
      }),
    );
    addTearDown(control.dispose);
    final todayInfo = Completer<void>();
    var todayStarts = 0;
    Future<void>? joined;
    late final MedBuddyUserSettingViewModel viewModel;
    viewModel = MedBuddyUserSettingViewModel(
      manageUserSetting: control,
      notificationService: RecordingNotificationService(),
      startTodayMedicationInfo: () {
        todayStarts++;
        return todayInfo.future;
      },
      refreshMedicationOverview: ({Future<void>? startedTodayInfo}) async {
        joined = startedTodayInfo;
        await startedTodayInfo;
      },
      refreshMedicationSchedule: () async {},
      loadMedicationReminderSettings: ({bool notifyAfterLoad = true}) async {},
      onChanged: () {},
      readEnglish: () => viewModel.userSetting.isEnglish,
    );
    addTearDown(viewModel.dispose);

    final load = viewModel.loadUserSetting();
    await Future<void>.delayed(Duration.zero);
    expect(todayStarts, 1);
    expect(joined, isNull);

    settingResponse.complete();
    todayInfo.complete();
    await load;

    expect(todayStarts, 1);
    expect(joined, same(todayInfo.future));
  });
}
