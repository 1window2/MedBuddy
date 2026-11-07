// 파일명: runtime_locale_session_test.dart
// 역할: 실행 중 기기 언어 변경과 세션별 언어 초기화 경합을 검증한다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/app_language_control.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/auth_session_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/main.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notification_service.dart';

// 클래스명: _Authentication
// 역할: 계정 교체 알림을 발생시키는 즉시 인증 완료 상태의 대역이다.
// 주요 책임:
// - 외부 인증 없이 세션을 바꾸고 앱의 언어 초기화 경합을 유도한다.
// 속성:
// - session(AuthSession?): 현재 인증 세션; 처음에는 user-a이다.
// - apiClient(AuthenticatedApiClient): 빈 데이터 응답을 제공하고 폐기 시 닫는 클라이언트.
class _Authentication extends ChangeNotifier implements AuthenticationControl {
  @override
  AuthSession? session = const AuthSession(
    userHash: 'user-a',
    authenticated: true,
  );
  @override
  final apiClient = AuthenticatedApiClient(
    tokenProvider: () async => null,
    inner: MockClient((_) async => http.Response('{"data":[]}', 200)),
  );
  // 함수이름: isInitializing
  // 함수역할:
  // - 인증 준비 대기를 생략하여 앱의 설정 초기화만 시험한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 항상 false.
  @override
  bool get isInitializing => false;
  // 함수이름: isAuthenticated
  // 함수역할:
  // - 세션 존재 여부를 앱의 인증 상태로 노출한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: session이 있으면 true, 없으면 false.
  @override
  bool get isAuthenticated => session != null;
  // 함수이름: emailVerificationRequired
  // 함수역할:
  // - 이메일 인증 화면이 언어 테스트 경로에 끼어들지 않게 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 항상 false.
  @override
  bool get emailVerificationRequired => false;
  // 함수이름: signedInEmail
  // 함수역할:
  // - 이 테스트가 다루지 않는 이메일 표시 정보를 비운다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String?: 항상 null.
  @override
  String? get signedInEmail => null;
  // 함수이름: setBeforeSignOut
  // 함수역할:
  // - 앱의 정리 훅 등록을 받아들이되 이 대역에서는 저장하거나 실행하지 않는다.
  // 매개변수:
  // - callback(Future<void> Function()?): 인터페이스 호환용 로그아웃 전 정리 훅.
  // 반환값:
  // - 없음; 로그아웃 흐름은 이 파일에서 재현하지 않는다.
  @override
  void setBeforeSignOut(Future<void> Function()? callback) {}
  // 함수이름: handleUnauthorizedResponse
  // 함수역할:
  // - 외부 인증 실패 처리를 생략하여 언어 초기화에만 테스트 범위를 제한한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 세션 변경 없는 즉시 완료.
  @override
  Future<void> handleUnauthorizedResponse() async {}

  // 함수이름: switchUser
  // 함수역할:
  // - 새 인증 세션으로 교체하고 구독자에게 알려 앱이 계정별 설정을 다시 읽게 한다.
  // 매개변수:
  // - userHash(String): 새 활성 계정 식별자.
  // 반환값:
  // - 없음; session이 바뀌고 변경 알림이 발생한다.
  void switchUser(String userHash) {
    session = AuthSession(userHash: userHash, authenticated: true);
    notifyListeners();
  }

  // 함수이름: dispose
  // 함수역할:
  // - 대역의 인증 HTTP 클라이언트를 닫고 ChangeNotifier 자원을 정리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 이후 대역을 재사용하지 않는다.
  @override
  void dispose() {
    apiClient.close();
    super.dispose();
  }

  // 함수이름: noSuchMethod
  // 함수역할:
  // - 구현하지 않은 인증 기능이 호출되면 기본 미구현 오류로 예상 밖 사용을 드러낸다.
  // 매개변수:
  // - invocation(Invocation): 지원하지 않는 멤버 호출 정보.
  // 반환값:
  // - 정상 반환 없이 NoSuchMethodError를 발생시킨다.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// 클래스명: _ViewModel
// 역할: 계정 설정 제어기를 실제 뷰모델의 초기화 흐름에 연결한다.
// 주요 책임:
// - 비설정 API와 알림을 대역으로 바꾸어 언어 동기화만 관찰한다.
// 속성:
// - 별도 필드 없음; 계정과 설정 제어기·HTTP·알림은 상위 뷰모델에 주입한다.
class _ViewModel extends MedBuddyViewModel {
  // 함수이름: _ViewModel
  // 함수역할:
  // - 주어진 계정 설정 제어기와 빈 API 응답·기록용 알림 대역으로 뷰모델을 구성한다.
  // 매개변수:
  // - settings(ManageUserSetting): 계정과 저장 응답을 제어할 설정 제어기.
  // 반환값:
  // - _ViewModel: 외부 알림 플랫폼 없이 설정 초기화를 수행하는 뷰모델.
  _ViewModel(ManageUserSetting settings)
    : super(
        patientHash: settings.userHash,
        manageUserSetting: settings,
        apiClient: MockClient((_) async => http.Response('{"data":[]}', 200)),
        notificationService: RecordingNotificationService(),
      );
}

// 함수이름: main
// 함수역할:
// - 자동·명시 언어 모드, 계정 교체 중 초기화와 중복 설정 저장 방지 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  // 함수이름: setUp 콜백
  // 함수역할:
  // - 계정별 언어 캐시와 공통 언어 설정을 각 사례 전에 비운다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 초기 설정은 개별 테스트가 구성한다.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 함수이름: showApp
  // 함수역할:
  // - 인증·언어·뷰모델 대역으로 앱을 열고 초기 프레임을 안정화하며 폐기 훅을 등록한다.
  // 매개변수:
  // - tester(WidgetTester): 앱 장착과 화면 안정화 도구.
  // - auth(_Authentication): 계정 교체를 알리는 인증 대역.
  // - language(AppLanguageControl): 앱 전체 언어 상태.
  // - factory(MedBuddyViewModel Function()): 세션별 뷰모델 생성 함수.
  // 반환값:
  // - Future<void>: 초기 화면 안정화 완료; 지연된 네트워크 요청까지 기다리는 것은 아니다.
  Future<void> showApp(
    WidgetTester tester,
    _Authentication auth,
    AppLanguageControl language,
    MedBuddyViewModel Function() factory,
  ) async {
    addTearDown(auth.dispose);
    addTearDown(language.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MedBuddyApp(
        authenticationControl: auth,
        appLanguageControl: language,
        viewModelFactory: factory,
        sessionReminderCleanup: () async {},
        notificationSelectionRegistrar: (_) {},
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final mode in ['system', 'ko', 'en']) {
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기기 언어를 영어로 바꾸면 시스템 모드만 한 번 저장하고 명시 언어는 유지하며 같은 로케일을 재통지해도 중복 저장하지 않는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets('runtime device locale honors $mode without repeated saves', (
      tester,
    ) async {
      tester.binding.platformDispatcher.localeTestValue = const Locale('ko');
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
      final auth = _Authentication();
      final language = AppLanguageControl(loadPersisted: false);
      final puts = <Map<String, dynamic>>[];
      var setting = UserSetting(
        userHash: 'user-a',
        language: mode == 'en' ? 'en' : 'ko',
        languageMode: mode,
      );
      final model = _ViewModel(
        ManageUserSetting(
          userHash: 'user-a',
          client: MockClient((request) async {
            if (request.method == 'PUT') {
              puts.add(jsonDecode(request.body) as Map<String, dynamic>);
              setting = UserSetting.fromJson(puts.last);
            }
            return http.Response(jsonEncode({'data': setting.toJson()}), 200);
          }),
        ),
      );
      await showApp(tester, auth, language, () => model);
      tester.binding.platformDispatcher.localeTestValue = const Locale('en');
      await tester.pumpAndSettle();
      expect(model.userSetting.language, mode == 'ko' ? 'ko' : 'en');
      expect(model.userSetting.languageMode, mode);
      expect(language.languageMode, mode);
      expect(puts, hasLength(mode == 'system' ? 1 : 0));
      tester.binding.platformDispatcher.localeTestValue = const Locale('en');
      await tester.pumpAndSettle();
      expect(puts, hasLength(mode == 'system' ? 1 : 0));
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 이전 계정의 설정 응답을 지연한 채 새 계정 영어 설정을 적용하면 늦은 응답이 앱 언어와 저장된 언어 모드를 되돌리지 않는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('late old-account bootstrap cannot replace the new language', (
    tester,
  ) async {
    final auth = _Authentication();
    final language = AppLanguageControl(loadPersisted: false);
    final oldResponse = Completer<http.Response>();
    await showApp(tester, auth, language, () {
      final owner = auth.session!.userHash;
      return _ViewModel(
        ManageUserSetting(
          userHash: owner,
          client: MockClient((_) async {
            if (owner == 'user-a') return oldResponse.future;
            return http.Response(
              jsonEncode({
                'data': UserSetting(
                  userHash: owner,
                  language: 'en',
                  languageMode: 'en',
                ).toJson(),
              }),
              200,
            );
          }),
        ),
      );
    });
    auth.switchUser('user-b');
    await tester.pumpAndSettle();
    expect(language.languageMode, 'en');
    oldResponse.complete(
      http.Response(
        jsonEncode({'data': const UserSetting(userHash: 'user-a').toJson()}),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(language.languageMode, 'en');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(AppLanguageControl.preferenceKey), 'en');
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 첫 설정 조회가 503이면 캐시 모드를 사용하고 앱 복귀 후 조회를 재시도해 서버 모드를 적용하되 설정 쓰기는 하지 않는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets(
    'resume retries a cached bootstrap and restores the server mode',
    (tester) async {
      tester.binding.platformDispatcher.localeTestValue = const Locale('en');
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
      SharedPreferences.setMockInitialValues({
        'user_setting_user-a_language': 'ko',
        'user_setting_user-a_language_mode': 'system',
      });
      final auth = _Authentication();
      final language = AppLanguageControl(loadPersisted: false);
      var available = false;
      var gets = 0;
      var puts = 0;
      final model = _ViewModel(
        ManageUserSetting(
          userHash: 'user-a',
          client: MockClient((request) async {
            if (request.method == 'GET') gets++;
            if (request.method == 'PUT') puts++;
            return available
                ? http.Response(
                    jsonEncode({
                      'data': const UserSetting(
                        userHash: 'user-a',
                        languageMode: 'ko',
                      ).toJson(),
                    }),
                    200,
                  )
                : http.Response('{}', 503);
          }),
        ),
      );
      await showApp(tester, auth, language, () => model);
      expect(language.languageMode, 'system');
      expect(puts, 0);
      available = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(gets, 2);
      expect(puts, 0);
      expect(language.languageMode, 'ko');
      expect(model.userSetting.languageMode, 'ko');
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 시스템 모드의 시작 언어를 기기에 맞춘 저장이 실패하면 복귀 때 한 번 재전송하고 성공 뒤 추가 복귀에서는 저장을 반복하지 않는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets(
    'startup reconciles system language and retries failed PUT on resume',
    (tester) async {
      tester.binding.platformDispatcher.localeTestValue = const Locale('en');
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
      final auth = _Authentication();
      final language = AppLanguageControl(loadPersisted: false);
      var setting = const UserSetting(
        userHash: 'user-a',
        languageMode: 'system',
      );
      var available = false;
      var puts = 0;
      final model = _ViewModel(
        ManageUserSetting(
          userHash: 'user-a',
          client: MockClient((request) async {
            if (request.method == 'PUT') {
              puts++;
              if (!available) return http.Response('{}', 503);
              setting = UserSetting.fromJson(
                jsonDecode(request.body) as Map<String, dynamic>,
              );
            }
            return http.Response(jsonEncode({'data': setting.toJson()}), 200);
          }),
        ),
      );
      await showApp(tester, auth, language, () => model);
      expect(puts, 1);
      expect(language.languageMode, 'system');
      expect(model.userSetting.language, 'en');
      expect(setting.language, 'ko');
      available = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(puts, 2);
      expect(setting.language, 'en');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(puts, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
