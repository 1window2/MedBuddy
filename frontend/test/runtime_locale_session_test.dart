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
  @override
  bool get isInitializing => false;
  @override
  bool get isAuthenticated => session != null;
  @override
  bool get emailVerificationRequired => false;
  @override
  String? get signedInEmail => null;
  @override
  void setBeforeSignOut(Future<void> Function()? callback) {}
  @override
  Future<void> handleUnauthorizedResponse() async {}

  void switchUser(String userHash) {
    session = AuthSession(userHash: userHash, authenticated: true);
    notifyListeners();
  }

  @override
  void dispose() {
    apiClient.close();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ViewModel extends MedBuddyViewModel {
  _ViewModel(ManageUserSetting settings)
    : super(
        patientHash: settings.userHash,
        manageUserSetting: settings,
        apiClient: MockClient((_) async => http.Response('{"data":[]}', 200)),
        notificationService: RecordingNotificationService(),
      );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
