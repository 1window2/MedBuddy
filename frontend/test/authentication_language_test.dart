// 파일명: authentication_language_test.dart
// 역할: 로그인 전 언어 선택, 인증 화면 번역, 메일 발송 언어 전달을 검증한다.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/authentication_gate.dart';
import 'package:medbuddy_frontend/boundaries/authentication_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/app_language_control.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_wordmark.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: _FirebaseAuth
// 역할: 실제 계정 생성이나 메일 전송 없이 인증 호출 순서와 언어를 기록하는 Firebase 대역이다.
// 주요 책임:
// - 메일 언어 설정 대기, 로그인 오류와 로그아웃 성공·실패를 재현한다.
// 속성:
// - calls (List<String>): 호출 순서와 메일 전송 언어.
// - user (_User): 고정 사용자 대역. language (String?): 적용된 메일 언어.
// - languageReady (Completer<void>?): 언어 설정 완료를 지연할 신호.
// - failDelivery, failSignOut (bool): 메일·로그아웃 실패 여부. signedOut (bool): 현재 사용자 제거 여부.
class _FirebaseAuth extends Fake implements FirebaseAuth {
  final calls = <String>[];
  late final _User user = _User(this);
  String? language;
  Completer<void>? languageReady;
  bool failDelivery = false;
  bool failSignOut = false;
  bool signedOut = false;

  // 함수이름: currentUser
  // 함수역할:
  // - 로그아웃 이후에는 사용자를 숨기고 그 전에는 고정 사용자 대역을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - User?; 로그인 상태의 user 또는 로그아웃 뒤 null.
  @override
  User? get currentUser => signedOut ? null : user;

  // 함수이름: signOut
  // 함수역할:
  // - 실패 설정이면 네트워크 오류를 발생시키고, 성공하면 호출을 기록하고 현재 사용자를 제거한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 실패 시 network-request-failed 코드의 FirebaseAuthException.
  @override
  Future<void> signOut() async {
    if (failSignOut) {
      throw FirebaseAuthException(code: 'network-request-failed');
    }
    calls.add('signOut');
    signedOut = true;
  }

  // 함수이름: setLanguageCode
  // 함수역할:
  // - 언어 설정 요청을 먼저 기록하고 선택적 대기 신호가 끝나면 메일 언어를 반영한다.
  // 매개변수:
  // - languageCode (String?): 적용할 언어 코드 또는 null.
  // 반환값:
  // - Future<void>; 대기 신호와 언어 반영이 완료되면 끝난다.
  @override
  Future<void> setLanguageCode(String? languageCode) async {
    calls.add('language:$languageCode');
    await languageReady?.future;
    language = languageCode;
  }

  // 함수이름: createUserWithEmailAndPassword
  // 함수역할:
  // - 가입 호출을 기록하고 고정 사용자 자격 증명을 반환하며 실제 계정을 생성하지 않는다.
  // 매개변수:
  // - email (String): 가입 인터페이스를 맞추기 위한 주소; 대역에서는 사용하지 않는다.
  // - password (String): 가입 인터페이스를 맞추기 위한 비밀번호; 대역에서는 사용하지 않는다.
  // 반환값:
  // - Future<UserCredential>; 고정 user를 담은 자격 증명.
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    calls.add('create');
    return _Credential(user);
  }

  // 함수이름: signInWithEmailAndPassword
  // 함수역할:
  // - 입력 내용과 무관하게 잘못된 비밀번호 오류를 발생시켜 로그인 실패 화면을 검증하게 한다.
  // 매개변수:
  // - email (String): 검증하지 않는 로그인 주소.
  // - password (String): 검증하지 않는 로그인 비밀번호.
  // 반환값:
  // - Future<UserCredential>; 정상 반환 없이 wrong-password 코드의 FirebaseAuthException.
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    throw FirebaseAuthException(code: 'wrong-password');
  }

  // 함수이름: sendPasswordResetEmail
  // 함수역할:
  // - 외부 메일 없이 비밀번호 재설정 요청에 적용된 현재 언어를 기록한다.
  // 매개변수:
  // - email (String): 재설정 수신 주소; 전송하지 않는다.
  // - actionCodeSettings (ActionCodeSettings?): 선택적 메일 설정; 대역에서는 사용하지 않는다.
  // 반환값:
  // - Future<void>; 요청 기록 후 완료한다.
  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    calls.add('reset:$language');
  }
}

// 클래스명: _User
// 역할: 메일 인증 상태와 네트워크 지연·실패를 조절할 수 있는 고정 Firebase 사용자 대역이다.
// 주요 책임:
// - 인증 확인 횟수와 강제 토큰 갱신 횟수를 기록하고 메일 전송 언어·오류를 재현한다.
// 속성:
// - auth (_FirebaseAuth): 메일 언어와 전송 실패 설정을 가진 소유자.
// - reloads, tokenRefreshes (int): 사용자 재조회와 강제 토큰 갱신 횟수.
// - reloadReady (Completer<void>?): 재조회 완료 대기 신호.
// - failReload, verified (bool): 재조회 실패 여부와 현재 이메일 인증 상태.
class _User extends Fake implements User {
  final _FirebaseAuth auth;
  // 함수이름: _User
  // 함수역할:
  // - 메일 전송 설정과 호출 기록을 공유할 인증 대역을 연결한다.
  // 매개변수:
  // - auth (_FirebaseAuth): 사용자 대역이 참조할 인증 객체.
  // 반환값:
  // - _User; 미인증 상태와 초기화된 호출 횟수를 가진 사용자.
  _User(this.auth);
  int reloads = 0;
  Completer<void>? reloadReady;
  bool failReload = false;
  bool verified = false;
  int tokenRefreshes = 0;

  // 함수이름: uid
  // 함수역할:
  // - 인증 세션 검증에 사용할 고정 사용자 식별자를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String; auth-language-fixture.
  @override
  String get uid => 'auth-language-fixture';
  // 함수이름: email
  // 함수역할:
  // - 인증 안내에 표시할 고정 테스트 이메일 주소를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String; language@example.test.
  @override
  String get email => 'language@example.test';
  // 함수이름: isAnonymous
  // 함수역할:
  // - 익명 계정이 아닌 이메일 계정으로 판정되게 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool; 항상 false.
  @override
  bool get isAnonymous => false;
  // 함수이름: emailVerified
  // 함수역할:
  // - 테스트가 변경한 이메일 인증 여부를 그대로 노출한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool; 현재 verified 값.
  @override
  bool get emailVerified => verified;
  // 함수이름: getIdToken
  // 함수역할:
  // - 고정 토큰을 반환하며 강제 갱신 요청만 횟수에 포함한다.
  // 매개변수:
  // - forceRefresh (bool): true이면 tokenRefreshes를 증가시키며 기본값은 false.
  // 반환값:
  // - Future<String?>; 항상 test-token.
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    if (forceRefresh) tokenRefreshes++;
    return 'test-token';
  }

  // 함수이름: providerData
  // 함수역할:
  // - 비밀번호 로그인 공급자를 가진 계정으로 인식되도록 공급자 목록을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - List<UserInfo>; _ProviderInfo 한 건.
  @override
  List<UserInfo> get providerData => [_ProviderInfo()];
  // 함수이름: multiFactor
  // 함수역할:
  // - 다중 인증 기능을 지원하지 않는 계정 조회 오류를 재현한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - MultiFactor; 정상 반환 없이 operation-not-allowed 코드의 FirebaseAuthException.
  @override
  MultiFactor get multiFactor =>
      throw FirebaseAuthException(code: 'operation-not-allowed');

  // 함수이름: reload
  // 함수역할:
  // - 재조회 횟수를 늘리고 대기 신호 이후 성공하거나 설정된 네트워크 오류를 발생시킨다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; failReload가 true이면 FirebaseAuthException.
  @override
  Future<void> reload() async {
    reloads++;
    await reloadReady?.future;
    if (failReload) {
      throw FirebaseAuthException(code: 'network-request-failed');
    }
  }

  // 함수이름: sendEmailVerification
  // 함수역할:
  // - 전송 실패 설정이면 요청 제한 오류를 내고, 성공하면 현재 언어로 인증 메일 호출을 기록한다.
  // 매개변수:
  // - actionCodeSettings (ActionCodeSettings?): 선택적 링크 설정; 실제 메일은 전송하지 않는다.
  // 반환값:
  // - Future<void>; 실패 시 too-many-requests 코드의 FirebaseAuthException.
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

// 클래스명: _ProviderInfo
// 역할: 고정 이메일 로그인 공급자 정보를 제공한다.
// 주요 책임:
// - 사용자 계정이 비밀번호 인증 경로로 처리되도록 공급자 식별자를 노출한다.
// 속성:
// - 없음.
class _ProviderInfo extends Fake implements UserInfo {
  // 함수이름: providerId
  // 함수역할:
  // - Firebase 이메일·비밀번호 공급자 식별자를 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String; EmailAuthProvider.PROVIDER_ID.
  @override
  String get providerId => EmailAuthProvider.PROVIDER_ID;
}

// 클래스명: _Credential
// 역할: 가입 성공 결과에 사용자 대역을 담는 자격 증명 객체다.
// 주요 책임:
// - 전달된 사용자를 UserCredential 인터페이스로 노출한다.
// 속성:
// - user (User): 가입 결과로 반환할 사용자.
class _Credential extends Fake implements UserCredential {
  @override
  final User user;
  // 함수이름: _Credential
  // 함수역할:
  // - 가입 결과에서 읽을 사용자를 저장한다.
  // 매개변수:
  // - user (User): 결과에 포함할 사용자 대역.
  // 반환값:
  // - _Credential; 전달된 사용자를 보관하는 자격 증명.
  _Credential(this.user);
}

// 함수이름: _showAuth
// 함수역할:
// - 지정 배율의 인증 화면을 표시하고 화면 제거를 정리 작업으로 등록한다. 부모 재생성 없이 내부 상태 갱신을 검사할 수 있다.
// 매개변수:
// - tester (WidgetTester): 화면 표시와 프레임 진행 도구.
// - control (AuthenticationControl): 인증 상태와 작업을 제공할 객체.
// - language (AppLanguageControl): 화면 번역과 언어 선택 상태.
// - scale (double): 텍스트 배율; 기본값 1.
// 반환값:
// - Future<void>; 초기 화면이 안정된 뒤 완료한다.
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

// 함수이름: _selectLanguage
// 함수역할:
// - 언어 아이콘과 선택 항목을 차례로 눌러 실제 사용자 경로로 화면 언어를 바꾼다.
// 매개변수:
// - tester (WidgetTester): 탭과 프레임 진행 도구.
// - language (String): 선택할 ko 또는 en 코드.
// 반환값:
// - Future<void>; 언어 선택 후 화면 갱신이 안정되면 완료한다.
Future<void> _selectLanguage(WidgetTester tester, String language) async {
  await tester.tap(find.byKey(const Key('authentication-language-toggle')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('authentication-language-$language')));
  await tester.pumpAndSettle();
}

// 함수이름: main
// 함수역할:
// - 환경설정 저장소를 테스트마다 초기화하고 인증 번역·메일 순서·자동 인증·오류 처리 테스트를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - void; 테스트 실행은 Flutter 테스트 러너가 수행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 함수이름: setUp
  // 함수역할:
  // - 각 테스트 전에 환경설정 대역을 비워 이전 언어 선택이 다음 테스트에 영향을 주지 않게 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 메모리 환경설정 저장소를 초기화한다.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scenario in [
    (size: const Size(390, 844), scale: 1.0, safeTop: 0.0),
    (size: const Size(390, 844), scale: 1.0, safeTop: 24.0),
    (size: const Size(320, 568), scale: 2.0, safeTop: 24.0),
  ]) {
    // 함수이름: login header and inputs fit ${scenario.size} at ${scenario.scale}x
    // 함수역할:
    // - 일반 화면과 작은 화면·2배 글자에서 로고와 언어 버튼이 겹치지 않고 입력란 조작 및 접근성 이름이 유지되는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
    testWidgets(
      'login header and inputs fit ${scenario.size} at ${scenario.scale}x with ${scenario.safeTop} top inset',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scenario.size;
        tester.view.padding = FakeViewPadding(top: scenario.safeTop);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        final auth = AuthenticationControl.development();
        final language = AppLanguageControl(loadPersisted: false);
        addTearDown(auth.dispose);
        addTearDown(language.dispose);
        await _showAuth(tester, auth, language, scale: scenario.scale);

        final logo = find.byType(MedBuddyWordmark);
        final languageButton = find.byKey(
          const Key('authentication-language-toggle'),
        );
        expect(logo, findsOneWidget);
        expect(languageButton, findsOneWidget);
        final logoRect = tester.getRect(logo);
        final buttonRect = tester.getRect(languageButton);
        expect(logoRect.left, closeTo(32, 0.1));
        expect(logoRect.top - scenario.safeTop, closeTo(logoRect.left, 0.1));
        expect(logoRect.center.dy, closeTo(buttonRect.center.dy, 0.1));
        expect(logoRect.right, lessThanOrEqualTo(buttonRect.left));
        expect(logoRect.overlaps(buttonRect), isFalse);
        expect(
          logoRect.bottom,
          lessThanOrEqualTo(
            tester.getTopLeft(find.byType(TextFormField).first).dy,
          ),
        );
        expect(find.bySemanticsLabel('MedBuddy'), findsOneWidget);

        await tester.tap(languageButton);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('authentication-language-en')),
          findsOneWidget,
        );
        Navigator.pop(
          tester.element(find.byKey(const Key('authentication-language-en'))),
        );
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        expect(fields, findsNWidgets(2));
        await tester.ensureVisible(fields.first);
        await tester.tap(fields.first);
        await tester.enterText(fields.first, 'user@example.test');
        await tester.ensureVisible(fields.last);
        await tester.tap(fields.last);
        await tester.enterText(fields.last, 'test-password');
        expect(
          tester.widget<TextFormField>(fields.first).controller!.text,
          'user@example.test',
        );
        expect(
          tester.widget<TextFormField>(fields.last).controller!.text,
          'test-password',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  // 함수이름: fresh launch defaults to Korean and picker can be dismissed
  // 함수역할:
  // - 영어 기기에서도 저장된 선택이 없으면 한국어로 시작하고 언어 선택창을 닫아도 현재 언어가 유지되는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

  // 함수이름: retained sign-in screen updates authentication errors
  // 함수역할:
  // - 보존된 로그인 화면에 실패 안내가 즉시 나타나며 언어 변경만으로 기존 오류도 번역되는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

  // 함수이름: language selection preserves signup inputs and persists
  // 함수역할:
  // - 가입 입력과 모드를 언어 변경 뒤에도 유지·복원하고 선택 언어로 인증 메일을 보내며 뒤로가기 시 이메일만 남긴 로그인 화면으로 돌아오는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
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
    // 함수이름: unverified refresh shows progress and guidance: $code
    // 함수역할:
    // - 한국어·영어 재확인 중 중복 확인과 뒤로가기를 막고 진행 표시 뒤 미인증 안내를 제공하되 앱 진입은 허용하지 않는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

  // 함수이름: verification refresh recovers after a network failure
  // 함수역할:
  // - 인증 재조회 통신 실패를 미인증 안내와 구분하고 재시도 성공 뒤 정상 미인증 안내로 교체하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

  // 함수이름: verification back button returns to sign in after retry
  // 함수역할:
  // - 인증 화면의 뒤로가기 실패 시 상태를 보존하고, 언어를 바꾼 뒤 재시도하면 계정을 삭제하지 않고 로그인 화면으로 돌아오는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

  // 함수이름: automatic verification pauses, resumes, and stops on back
  // 함수역할:
  // - 자동 인증 확인이 앱 비활성 중 멈추고 복귀 시 즉시 재개되며 로그인 화면으로 돌아온 뒤에는 더 호출되지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

  // 함수이름: automatic verification does not overlap a manual request
  // 함수역할:
  // - 느린 수동 확인과 자동 조회가 겹치지 않고 자동 조회가 수동 안내를 지우지 않으며 화면 제거 후에는 중단되는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

  // 함수이름: verified account enters the app automatically after server approval
  // 함수역할:
  // - 메일 인증 완료 후 토큰을 갱신해도 서버 승인 전에는 진입을 막고, 승인되면 자동 진입하면서 재조회가 멈추는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

  // 함수이름: verification errors follow the selected language
  // 함수역할:
  // - 인증 메일 요청 제한 오류가 현재 언어로 표시되고 재선택한 언어로 즉시 바뀌는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

  // 함수이름: password reset uses the selected language and localized feedback
  // 함수역할:
  // - 빈 이메일에는 입력 안내를 표시하고 재설정 메일 언어와 전송 완료 안내가 한국어·영어 선택을 따르는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
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
    // 함수이름: verification fits a narrow screen at large text: $code
    // 함수역할:
    // - 320px 화면과 2배 글자에서도 두 언어의 인증 안내에 오류가 없고 재발송·뒤로가기·언어 선택을 조작할 수 있는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

  // 함수이름: mail operations await Firebase language before dispatch
  // 함수역할:
  // - 가입·재발송·비밀번호 재설정 메일이 언어 적용 완료를 기다리고 언어 미지정 시 한국어를 사용하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

  // Function Name: every authentication error code has its own guidance
  // Description:
  // - Require nonempty Korean and English guidance for every error code, preserving coded StateError messages and distinct Korean guidance for non-generic failures.
  // Parameters:
  // - None.
  // Returns:
  // - void; assertions verify each error-code mapping.
  test('every authentication error code has its own guidance', () {
    for (final code in AuthenticationErrorCode.values) {
      expect(code.english.trim(), isNotEmpty, reason: code.name);
      expect(code.korean.trim(), isNotEmpty, reason: code.name);
      expect(code.messageFor(true), code.english);
      expect(code.messageFor(false), code.korean);
      final error = AuthenticationStateError(code);
      expect(error, isA<StateError>());
      expect(error.message, code.english);
      expect(error.messageFor(false), code.korean);
      if (code != AuthenticationErrorCode.requestFailed) {
        expect(
          code.korean,
          isNot(AuthenticationErrorCode.requestFailed.korean),
          reason: code.name,
        );
      }
    }
  });

  // Function Name: operation failures are localized by code
  // Description:
  // - Map coded operation failures and signed-out session retries to both languages while retaining uncoded StateError text in English and generic Korean fallback guidance.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('operation failures are localized by code', () async {
    final failures = <AuthenticationErrorCode>[
      AuthenticationErrorCode.googleIdentityTokenMissing,
      AuthenticationErrorCode.firebaseUnavailable,
      AuthenticationErrorCode.mfaSignInExpired,
      AuthenticationErrorCode.mfaEnrollmentExpired,
      AuthenticationErrorCode.deletionRequiresRecentSignIn,
    ];
    for (final code in failures) {
      final auth = AuthenticationControl.withFirebaseAuth(_FirebaseAuth());
      addTearDown(auth.dispose);
      await auth.runAuthOperationForTest(
        () async => throw AuthenticationStateError(code),
      );
      expect(auth.errorMessage, code.english);
      expect(auth.errorMessageForLanguage(isEnglish: true), code.english);
      expect(auth.errorMessageForLanguage(isEnglish: false), code.korean);
    }

    // A signed-out session retry requires sign-in, with guidance in both languages.
    final firebase = _FirebaseAuth()..signedOut = true;
    final auth = AuthenticationControl.withFirebaseAuth(firebase);
    addTearDown(auth.dispose);
    await auth.retryBackendSession();
    expect(auth.errorMessage, 'Sign in before retrying the secure session.');
    expect(
      auth.errorMessageForLanguage(isEnglish: false),
      '보안 세션을 다시 연결하려면 먼저 로그인해 주세요.',
    );

    // An uncoded StateError keeps its English text and uses generic Korean guidance.
    await auth.runAuthOperationForTest(
      () async => throw StateError('push token unregister failed'),
    );
    expect(auth.errorMessage, 'push token unregister failed');
    expect(
      auth.errorMessageForLanguage(isEnglish: false),
      '인증 요청을 처리하지 못했습니다. 다시 시도해 주세요.',
    );
  });

  // Function Name: a canceled Google prompt is not an error
  // Description:
  // - Treat Google prompt cancellation as a non-error and map other plugin failures to stable localized guidance without exposing provider details.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('a canceled Google prompt is not an error', () async {
    final auth = AuthenticationControl.withFirebaseAuth(_FirebaseAuth());
    addTearDown(auth.dispose);
    await auth.runAuthOperationForTest(
      () async => throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
        description: 'activity is cancelled by the user.',
      ),
    );
    expect(auth.errorMessage, isNull);
    expect(auth.errorMessageForLanguage(isEnglish: false), isNull);
    expect(auth.isBusy, isFalse);

    for (final code in const [
      GoogleSignInExceptionCode.interrupted,
      GoogleSignInExceptionCode.clientConfigurationError,
      GoogleSignInExceptionCode.providerConfigurationError,
      GoogleSignInExceptionCode.uiUnavailable,
      GoogleSignInExceptionCode.userMismatch,
      GoogleSignInExceptionCode.unknownError,
    ]) {
      await auth.runAuthOperationForTest(
        () async => throw GoogleSignInException(
          code: code,
          description: 'androidx.credentials provider detail',
        ),
      );
      expect(auth.errorMessage, 'Google sign-in was not completed.');
      expect(
        auth.errorMessageForLanguage(isEnglish: false),
        'Google 로그인을 완료하지 못했습니다. 다시 시도해 주세요.',
      );
    }
  });

  // Function Name: strict operations throw coded errors for the caller
  // Description:
  // - Require strict operations to throw the mapped authentication code for cancellation, provider, network, timeout, unknown, and already-running failures.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('strict operations throw coded errors for the caller', () async {
    final auth = AuthenticationControl.withFirebaseAuth(_FirebaseAuth());
    addTearDown(auth.dispose);

    // Function Name: failWith
    // Description:
    // - Run an injected strict-operation failure and extract its typed authentication code.
    // Parameters:
    // - failure (Object): exception or error thrown by the fake provider operation.
    // Returns:
    // - Future<AuthenticationErrorCode>; mapped failure code, or StateError if the operation unexpectedly succeeds.
    Future<AuthenticationErrorCode> failWith(Object failure) async {
      try {
        await auth.runAuthOperationForTest(
          () async => throw failure,
          strict: true,
        );
      } on AuthenticationStateError catch (error) {
        return error.code;
      }
      throw StateError('The strict operation did not fail.');
    }

    expect(
      await failWith(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      ),
      AuthenticationErrorCode.googleSignInCanceled,
    );
    expect(auth.errorMessage, isNull);
    expect(
      await failWith(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'provider detail',
        ),
      ),
      AuthenticationErrorCode.googleSignInIncomplete,
    );
    expect(auth.errorMessage, 'Google sign-in was not completed.');
    expect(
      await failWith(FirebaseAuthException(code: 'network-request-failed')),
      AuthenticationErrorCode.network,
    );
    expect(
      await failWith(TimeoutException('provider')),
      AuthenticationErrorCode.timeout,
    );
    expect(
      await failWith(Exception('unexpected')),
      AuthenticationErrorCode.requestFailed,
    );
    expect(
      auth.errorMessageForLanguage(isEnglish: false),
      '인증 요청을 처리하지 못했습니다. 다시 시도해 주세요.',
    );

    // A second strict operation must not start while the first is still running.
    final gate = Completer<void>();
    final running = auth.runAuthOperationForTest(() => gate.future);
    expect(
      await failWith(Exception('never started')),
      AuthenticationErrorCode.operationInProgress,
    );
    gate.complete();
    await running;
  });

  // Function Name: signOut runs cleanup, then the provider, then clears the session
  // Description:
  // - Run cleanup before provider sign-out and clear authentication only on success; preserve the active session and report a localized error when provider sign-out fails.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test(
    'signOut runs cleanup, then the provider, then clears the session',
    () async {
      final firebase = _FirebaseAuth();
      firebase.user.verified = true;
      final client = AuthenticatedApiClient(
        inner: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'user_hash': 'sign-out-fixture',
              'authenticated': true,
              'email_verified': true,
            }),
            200,
          ),
        ),
        tokenProvider: () async => 'test-token',
        appCheckRequired: false,
      );
      final auth = AuthenticationControl.withFirebaseAuth(
        firebase,
        apiClient: client,
      );
      addTearDown(auth.dispose);
      await auth.retryBackendSession();
      expect(auth.isAuthenticated, isTrue);
      firebase.calls.clear();
      auth.setBeforeSignOut(() async {
        expect(auth.isAuthenticated, isTrue);
        firebase.calls.add('cleanup');
      });
      await auth.signOut();
      expect(firebase.calls, ['cleanup', 'signOut']);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.errorMessage, isNull);
      expect(auth.isBusy, isFalse);

      // Provider sign-out failure preserves the session and is reported to the caller.
      firebase.signedOut = false;
      await auth.retryBackendSession();
      expect(auth.isAuthenticated, isTrue);
      firebase.failSignOut = true;
      await expectLater(auth.signOut(), throwsStateError);
      expect(auth.isAuthenticated, isTrue);
      expect(
        auth.errorMessageForLanguage(isEnglish: false),
        '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
      );
    },
  );
}
