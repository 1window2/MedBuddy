// 파일명: authentication_language_test.dart
// 역할: 로그인 전 언어 선택, 인증 화면 번역, 메일 발송 언어 전달을 검증한다.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/authentication_gate.dart';
import 'package:medbuddy_frontend/boundaries/authentication_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/app_language_control.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 실제 Firebase 계정 생성과 메일 발송 없이 호출 순서와 선택 언어를 기록한다.
class _FirebaseAuth extends Fake implements FirebaseAuth {
  final calls = <String>[];
  late final _User user = _User(this);
  String? language;
  Completer<void>? languageReady;
  bool failDelivery = false;
  bool failSignOut = false;
  bool signedOut = false;

  @override
  User? get currentUser => signedOut ? null : user;

  @override
  Future<void> signOut() async {
    if (failSignOut) {
      throw FirebaseAuthException(code: 'network-request-failed');
    }
    calls.add('signOut');
    signedOut = true;
  }

  @override
  Future<void> setLanguageCode(String? languageCode) async {
    calls.add('language:$languageCode');
    await languageReady?.future;
    language = languageCode;
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    calls.add('create');
    return _Credential(user);
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    throw FirebaseAuthException(code: 'wrong-password');
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    calls.add('reset:$language');
  }
}

// 미인증 이메일 계정으로 유지해 테스트가 실제 백엔드 세션을 요청하지 않게 한다.
class _User extends Fake implements User {
  final _FirebaseAuth auth;
  _User(this.auth);
  int reloads = 0;
  Completer<void>? reloadReady;
  bool failReload = false;
  bool verified = false;
  int tokenRefreshes = 0;

  @override
  String get uid => 'auth-language-fixture';
  @override
  String get email => 'language@example.test';
  @override
  bool get isAnonymous => false;
  @override
  bool get emailVerified => verified;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    if (forceRefresh) tokenRefreshes++;
    return 'test-token';
  }

  @override
  List<UserInfo> get providerData => [_ProviderInfo()];
  @override
  MultiFactor get multiFactor =>
      throw FirebaseAuthException(code: 'operation-not-allowed');

  @override
  Future<void> reload() async {
    reloads++;
    await reloadReady?.future;
    if (failReload) {
      throw FirebaseAuthException(code: 'network-request-failed');
    }
  }

  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    if (auth.failDelivery) {
      throw FirebaseAuthException(code: 'too-many-requests');
    }
    auth.calls.add('verify:${auth.language}');
  }
}

class _ProviderInfo extends Fake implements UserInfo {
  @override
  String get providerId => EmailAuthProvider.PROVIDER_ID;
}

class _Credential extends Fake implements UserCredential {
  @override
  final User user;
  _Credential(this.user);
}

// Navigator에 유지된 화면이 부모의 재생성 없이도 인증 상태를 직접 갱신해야 한다.
Future<void> _showAuth(
  WidgetTester tester,
  AuthenticationControl control,
  AppLanguageControl language, {
  double scale = 1,
}) async {
  addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: AuthenticationUI(control: control, languageControl: language),
    ),
  );
  await tester.pumpAndSettle();
}

// 아이콘을 눌러 명시적으로 언어를 선택하는 실제 사용자 경로를 재사용한다.
Future<void> _selectLanguage(WidgetTester tester, String language) async {
  await tester.tap(find.byKey(const Key('authentication-language-toggle')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('authentication-language-$language')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 영어 기기에서도 저장된 선택이 없으면 한국어로 시작하며 자동 선택창은 띄우지 않는다.
  testWidgets('fresh launch defaults to Korean and picker can be dismissed', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    final auth = AuthenticationControl.development();
    final language = AppLanguageControl();
    addTearDown(auth.dispose);
    addTearDown(language.dispose);
    await _showAuth(tester, auth, language);
    expect(find.text('로그인'), findsNWidgets(2));
    expect(find.text('한국어'), findsNothing);
    expect(find.text('English'), findsNothing);
    await tester.tap(find.byKey(const Key('authentication-language-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('한국어'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(language.language, 'ko');
    Navigator.pop(tester.element(find.text('English')));
    await tester.pumpAndSettle();
    expect(language.language, 'ko');
  });

  // 로그인 실패 뒤 부모가 화면을 새로 만들지 않아도 오류가 즉시 보여야 한다.
  testWidgets('retained sign-in screen updates authentication errors', (
    tester,
  ) async {
    final auth = AuthenticationControl.withFirebaseAuth(_FirebaseAuth());
    final language = AppLanguageControl(loadPersisted: false);
    addTearDown(auth.dispose);
    addTearDown(language.dispose);
    await _showAuth(tester, auth, language);
    await tester.enterText(
      find.byType(TextFormField).first,
      'language@example.test',
    );
    await tester.enterText(find.byType(TextFormField).last, 'wrong-password');
    final signInButton = find.widgetWithText(FilledButton, '로그인');
    await tester.ensureVisible(signInButton);
    await tester.tap(signInButton);
    await tester.pumpAndSettle();
    expect(find.text('이메일 또는 비밀번호가 올바르지 않습니다.'), findsOneWidget);
    await _selectLanguage(tester, 'en');
    expect(find.text('The email or password is incorrect.'), findsOneWidget);
  });

  // 언어 변경이 입력값·가입 모드를 지우지 않고 다음 앱 실행에도 복원되는지 확인한다.
  testWidgets('language selection preserves signup inputs and persists', (
    tester,
  ) async {
    final firebase = _FirebaseAuth();
    final auth = AuthenticationControl.withFirebaseAuth(firebase);
    final language = AppLanguageControl(loadPersisted: false);
    addTearDown(auth.dispose);
    addTearDown(language.dispose);
    await _showAuth(tester, auth, language);
    await tester.tap(find.text('MedBuddy가 처음이신가요? 회원가입'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'language@example.test',
    );
    await tester.enterText(find.byType(TextFormField).last, 'fixture-password');
    await _selectLanguage(tester, 'en');
    expect(find.text('Create a secure account'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'language@example.test',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller!
          .text,
      'fixture-password',
    );
    final restored = AppLanguageControl(loadPersisted: false);
    await restored.load();
    expect(restored.language, 'en');
    restored.dispose();
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(firebase.calls, ['create', 'language:en', 'verify:en']);
    expect(find.text('Verify your email'), findsOneWidget);
    await _selectLanguage(tester, 'ko');
    expect(find.text('이메일을 인증해 주세요'), findsOneWidget);
    await tester.tap(find.text('인증 메일 다시 보내기'));
    await tester.pumpAndSettle();
    expect(firebase.calls.last, 'verify:ko');
    await tester.tap(find.text('인증 상태 다시 확인'));
    await tester.pumpAndSettle();
    expect(firebase.user.reloads, 1);
    expect(find.text('이메일을 인증해 주세요'), findsOneWidget);
    expect(
      find.text('아직 인증되지 않았어요. 메일의 인증 링크를 누른 뒤 다시 확인해 주세요.'),
      findsOneWidget,
    );
    // 실제 가입 폼에서 출발해도 뒤로가기는 가입 화면이 아닌 로그인으로 돌아온다.
    await tester.tap(find.byKey(const Key('authentication-back')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '회원가입'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'language@example.test',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller!
          .text,
      isEmpty,
    );
  });

  // 재확인 중 중복 입력을 막고, 미인증이면 안내만 표시하며 앱 진입을 허용하지 않는다.
  for (final code in ['ko', 'en']) {
    testWidgets('unverified refresh shows progress and guidance: $code', (
      tester,
    ) async {
      final firebase = _FirebaseAuth();
      final auth = AuthenticationControl.withFirebaseAuth(firebase);
      final language = AppLanguageControl(
        initialLanguage: code,
        loadPersisted: false,
      );
      addTearDown(auth.dispose);
      addTearDown(language.dispose);
      await auth.createAccount(
        email: 'language@example.test',
        password: 'fixture-password',
      );
      await _showAuth(tester, auth, language);
      firebase.user.reloadReady = Completer<void>();
      final confirmation = code == 'ko'
          ? '인증 상태 다시 확인'
          : 'Check verification status';
      // 자동 안내가 기본이고 수동 확인은 채워진 주 버튼이 아닌 보조 버튼이어야 한다.
      expect(find.byType(FilledButton), findsNothing);
      expect(
        find.text(
          code == 'ko'
              ? '메일의 인증 링크를 누른 뒤 앱으로 돌아오면 자동으로 로그인됩니다.'
              : 'Open the link in your email, then return to the app to sign in automatically.',
        ),
        findsOneWidget,
      );
      final guidance = code == 'ko'
          ? '아직 인증되지 않았어요. 메일의 인증 링크를 누른 뒤 다시 확인해 주세요.'
          : 'Email verification is not complete yet. Open the link in your email, then try again.';
      await tester.tap(find.text(confirmation));
      await tester.pump();
      expect(
        find.text(code == 'ko' ? '인증 확인 중…' : 'Checking verification…'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('email-verification-check')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('authentication-back')))
            .onPressed,
        isNull,
      );
      await auth.refreshEmailVerification();
      expect(firebase.user.reloads, 1);
      firebase.user.reloadReady!.complete();
      await tester.pumpAndSettle();
      expect(find.text(guidance), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(auth.emailVerificationRequired, isTrue);
      expect(auth.isAuthenticated, isFalse);
      await tester.tap(find.text(confirmation));
      await tester.pumpAndSettle();
      expect(firebase.user.reloads, 2);
      expect(find.text(guidance), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // 통신 실패를 미인증으로 오인하지 않고, 재시도하면 정상 조회 결과로 바뀌어야 한다.
  testWidgets('verification refresh recovers after a network failure', (
    tester,
  ) async {
    final firebase = _FirebaseAuth();
    final auth = AuthenticationControl.withFirebaseAuth(firebase);
    final language = AppLanguageControl(loadPersisted: false);
    addTearDown(auth.dispose);
    addTearDown(language.dispose);
    await auth.createAccount(
      email: 'language@example.test',
      password: 'fixture-password',
    );
    await _showAuth(tester, auth, language);
    firebase.user.failReload = true;
    await tester.tap(find.text('인증 상태 다시 확인'));
    await tester.pumpAndSettle();
    expect(find.text('인터넷 연결을 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);
    expect(find.textContaining('아직 인증되지'), findsNothing);
    expect(auth.isAuthenticated, isFalse);
    firebase.user.failReload = false;
    await tester.tap(find.text('인증 상태 다시 확인'));
    await tester.pumpAndSettle();
    expect(find.text('인터넷 연결을 확인한 뒤 다시 시도해 주세요.'), findsNothing);
    expect(find.textContaining('아직 인증되지'), findsOneWidget);
  });

  // 뒤로가기는 미인증 계정을 삭제하지 않고 로그인으로 복귀하며, 실패 시 재시도할 수 있다.
  testWidgets('verification back button returns to sign in after retry', (
    tester,
  ) async {
    final firebase = _FirebaseAuth();
    final auth = AuthenticationControl.withFirebaseAuth(firebase);
    final language = AppLanguageControl(loadPersisted: false);
    addTearDown(auth.dispose);
    addTearDown(language.dispose);
    await auth.createAccount(
      email: 'language@example.test',
      password: 'fixture-password',
    );
    await _showAuth(tester, auth, language);
    final back = find.byKey(const Key('authentication-back'));
    expect(tester.widget<IconButton>(back).tooltip, '로그인 화면으로 돌아가기');
    expect(find.text('다른 계정으로 로그인'), findsNothing);
    firebase.failSignOut = true;
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('인터넷 연결을 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);
    expect(auth.emailVerificationRequired, isTrue);
    expect(tester.takeException(), isNull);
    await _selectLanguage(tester, 'en');
    expect(tester.widget<IconButton>(back).tooltip, 'Back to sign in');
    expect(find.text('Use another account'), findsNothing);
    firebase.failSignOut = false;
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(firebase.calls.last, 'signOut');
    expect(auth.emailVerificationRequired, isFalse);
    expect(auth.signedInEmail, isNull);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(back, findsNothing);
    expect(language.language, 'en');
    expect(tester.takeException(), isNull);
  });

  // 자동 조회는 미인증 경고를 새로 띄우지 않고, 복귀 시 즉시 확인하며 화면 종료 후 멈춘다.
  testWidgets('automatic verification pauses, resumes, and stops on back', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final firebase = _FirebaseAuth();
    final auth = AuthenticationControl.withFirebaseAuth(firebase);
    final language = AppLanguageControl(loadPersisted: false);
    addTearDown(auth.dispose);
    addTearDown(language.dispose);
    await auth.createAccount(
      email: 'language@example.test',
      password: 'fixture-password',
    );
    await _showAuth(tester, auth, language);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(firebase.user.reloads, 1);
    expect(auth.errorMessage, isNull);
    expect(auth.isAuthenticated, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 20));
    expect(firebase.user.reloads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(firebase.user.reloads, 2);
    await tester.tap(find.byKey(const Key('authentication-back')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 20));
    expect(firebase.user.reloads, 2);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  // 느린 수동 확인과 자동 조회를 겹치지 않고 수동 확인 결과도 자동 조회가 지우지 않는다.
  testWidgets('automatic verification does not overlap a manual request', (
    tester,
  ) async {
    final firebase = _FirebaseAuth();
    final auth = AuthenticationControl.withFirebaseAuth(firebase);
    final language = AppLanguageControl(loadPersisted: false);
    addTearDown(auth.dispose);
    addTearDown(language.dispose);
    await auth.createAccount(
      email: 'language@example.test',
      password: 'fixture-password',
    );
    await _showAuth(tester, auth, language);
    firebase.user.reloadReady = Completer<void>();
    await tester.tap(find.text('인증 상태 다시 확인'));
    await tester.pump(const Duration(seconds: 10));
    expect(firebase.user.reloads, 1);
    firebase.user.reloadReady!.complete();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(firebase.user.reloads, 2);
    expect(find.textContaining('아직 인증되지'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 20));
    expect(firebase.user.reloads, 2);
  });

  // 메일 인증 이후 토큰을 갱신하고 서버가 세션을 승인해야만 버튼 없이 앱을 연다.
  testWidgets(
    'verified account enters the app automatically after server approval',
    (tester) async {
      final firebase = _FirebaseAuth();
      final response = Completer<http.Response>();
      final client = AuthenticatedApiClient(
        inner: MockClient((_) => response.future),
        tokenProvider: () async => 'test-token',
        appCheckRequired: false,
      );
      final auth = AuthenticationControl.withFirebaseAuth(
        firebase,
        apiClient: client,
      );
      final language = AppLanguageControl(loadPersisted: false);
      addTearDown(auth.dispose);
      addTearDown(language.dispose);
      await auth.createAccount(
        email: 'language@example.test',
        password: 'fixture-password',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AuthenticationGate(
            state: auth,
            unauthenticatedChild: AuthenticationUI(
              control: auth,
              languageControl: language,
            ),
            authenticatedChild: const Scaffold(body: Text('인증된 앱 화면')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      firebase.user.verified = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(firebase.user.tokenRefreshes, 1);
      expect(auth.isAuthenticated, isFalse);
      expect(find.text('인증된 앱 화면'), findsNothing);
      response.complete(
        http.Response(
          jsonEncode({
            'user_hash': 'verified-fixture',
            'authenticated': true,
            'email_verified': true,
            'email': 'language@example.test',
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(auth.isAuthenticated, isTrue);
      expect(find.text('인증된 앱 화면'), findsOneWidget);
      final reloads = firebase.user.reloads;
      await tester.pump(const Duration(seconds: 20));
      expect(firebase.user.reloads, reloads);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  // 발송 오류도 현재 언어로 표시하며 재선택한 언어로 즉시 다시 표시한다.
  testWidgets('verification errors follow the selected language', (
    tester,
  ) async {
    final firebase = _FirebaseAuth();
    final auth = AuthenticationControl.withFirebaseAuth(firebase);
    final language = AppLanguageControl(loadPersisted: false);
    addTearDown(auth.dispose);
    addTearDown(language.dispose);
    await auth.createAccount(
      email: 'language@example.test',
      password: 'fixture-password',
    );
    firebase.failDelivery = true;
    await _showAuth(tester, auth, language);
    await tester.tap(find.text('인증 메일 다시 보내기'));
    await tester.pumpAndSettle();
    expect(find.text('요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    await _selectLanguage(tester, 'en');
    expect(
      find.text('Too many attempts. Please wait and try again.'),
      findsOneWidget,
    );
  });

  // 비밀번호 찾기의 발송과 완료 안내도 화면 언어와 일치해야 한다.
  testWidgets(
    'password reset uses the selected language and localized feedback',
    (tester) async {
      final firebase = _FirebaseAuth();
      final auth = AuthenticationControl.withFirebaseAuth(firebase);
      final language = AppLanguageControl(loadPersisted: false);
      addTearDown(auth.dispose);
      addTearDown(language.dispose);
      await _showAuth(tester, auth, language);
      await tester.tap(find.text('비밀번호 찾기'));
      await tester.pumpAndSettle();
      expect(find.text('먼저 이메일 주소를 입력해 주세요.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'language@example.test',
      );
      await tester.tap(find.text('비밀번호 찾기'));
      await tester.pumpAndSettle();
      expect(find.text('비밀번호 재설정 메일을 보냈습니다.'), findsOneWidget);
      expect(firebase.calls, ['language:ko', 'reset:ko']);
      await _selectLanguage(tester, 'en');
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(
        find.text('Password reset instructions were sent by email.'),
        findsOneWidget,
      );
      expect(firebase.calls.last, 'reset:en');
    },
  );

  // 작은 화면·큰 글씨에서도 인증 버튼과 언어 선택지를 스크롤해 누를 수 있어야 한다.
  for (final code in ['ko', 'en']) {
    testWidgets('verification fits a narrow screen at large text: $code', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = AuthenticationControl.withFirebaseAuth(_FirebaseAuth());
      final language = AppLanguageControl(
        initialLanguage: code,
        loadPersisted: false,
      );
      addTearDown(auth.dispose);
      addTearDown(language.dispose);
      await auth.createAccount(
        email: 'language@example.test',
        password: 'fixture-password',
      );
      await _showAuth(tester, auth, language, scale: 2);
      expect(tester.takeException(), isNull);
      await auth.refreshEmailVerification();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final resendButton = find.text(
        code == 'ko' ? '인증 메일 다시 보내기' : 'Resend verification email',
      );
      await tester.ensureVisible(resendButton);
      expect(resendButton.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('authentication-back')).hitTestable(),
        findsOneWidget,
      );
      await _selectLanguage(tester, code == 'ko' ? 'en' : 'ko');
      expect(tester.takeException(), isNull);
    });
  }

  // 모든 메일 발송이 언어 설정 완료를 기다리는지와 기본 한국어를 검증한다.
  test('mail operations await Firebase language before dispatch', () async {
    final firebase = _FirebaseAuth();
    final auth = AuthenticationControl.withFirebaseAuth(firebase);
    addTearDown(auth.dispose);
    await auth.createAccount(
      email: 'language@example.test',
      password: 'fixture-password',
    );
    expect(firebase.calls, ['create', 'language:ko', 'verify:ko']);
    firebase.calls.clear();
    firebase.languageReady = Completer<void>();
    final resend = auth.resendEmailVerification(language: 'en');
    await Future<void>.delayed(Duration.zero);
    expect(firebase.calls, ['language:en']);
    expect(auth.isBusy, isTrue);
    firebase.languageReady!.complete();
    await resend;
    expect(firebase.calls, ['language:en', 'verify:en']);
    expect(auth.isBusy, isFalse);
    expect(await auth.sendPasswordReset('language@example.test'), isTrue);
    expect(firebase.calls.sublist(2), ['language:ko', 'reset:ko']);
  });
}
