// 파일명: authentication_session_recovery_test.dart
// 역할: 세션 자동 복구와 정상 생명주기 전환에 따른 재시도 중단, 토큰 갱신 뒤 재동기화 실패의 세션 유지·종료 판정을 검증한다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/authentication_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/services/api_config.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';

// Class Name: _SessionControl
// Role: Emulate a session that recovers on its third retry without network calls.
// Attributes: retryable tracks recovery state; calls counts retry requests.
class _SessionControl extends ChangeNotifier implements AuthenticationControl {
  bool retryable = true;
  int calls = 0;
  // Function Name: shouldAutoRetryBackendSession
  // Description: Expose retry eligibility. Parameters: none. Returns: recovery state.
  @override
  bool get shouldAutoRetryBackendSession => retryable;
  // Function Name: canRetryBackendSession
  // Description: Expose manual retry eligibility. Parameters: none. Returns: recovery state.
  @override
  bool get canRetryBackendSession => retryable;
  // Function Name: isBusy
  // Description: Keep the fake idle. Parameters: none. Returns: false.
  @override
  bool get isBusy => false;
  // Function Name: isInitializing
  // Description: Skip initialization in this fake. Parameters: none. Returns: false.
  @override
  bool get isInitializing => false;
  // Function Name: retryBackendSession
  // Description: Count retries and notify recovery on attempt three.
  // Parameters: none. Returns: completion after listeners are notified.
  @override
  Future<void> retryBackendSession() async {
    calls++;
    if (calls == 3) {
      retryable = false;
    }
    notifyListeners();
  }

  // Function Name: noSuchMethod
  // Description: Supply unused authentication state for the screen fixture.
  // Parameters: invocation identifies the member. Returns: false flags or null.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (const {
      #configurationFailed,
      #initializationFailed,
      #emailVerificationRequired,
      #phoneAuthenticationEnabled,
      #smsCodeRequired,
    }.contains(invocation.memberName)) {
      return false;
    }
    return null;
  }
}

// Class Name: _Firebase
// Role: Stand in for the Firebase SDK with one signed-in user and a controllable token stream.
// Attributes: user is the signed-in identity; signedOut and signOuts record provider sign-out;
//   tokenChanges feeds the control's token listener.
class _Firebase extends Fake implements FirebaseAuth {
  final _FirebaseUser user = _FirebaseUser();
  final tokenChanges = StreamController<User?>.broadcast(sync: true);
  bool signedOut = false;
  int signOuts = 0;

  // Function Name: currentUser
  // Description: Expose the user until the provider signs out. Parameters: none. Returns: user or null.
  @override
  User? get currentUser => signedOut ? null : user;

  // Function Name: signOut
  // Description: Record a provider sign-out. Parameters: none. Returns: completion.
  @override
  Future<void> signOut() async {
    signOuts++;
    signedOut = true;
  }

  // Function Name: idTokenChanges
  // Description: Expose the controllable token stream. Parameters: none. Returns: the stream.
  @override
  Stream<User?> idTokenChanges() => tokenChanges.stream;
}

// Class Name: _FirebaseUser
// Role: Emulate a verified Firebase user whose token and reload calls can fail on demand.
// Attributes: tokenFailure and reloadFailure are thrown by the next calls; tokenGate delays the
//   token; tokenReads and reloads count SDK calls.
class _FirebaseUser extends Fake implements User {
  @override
  String uid = 'session-fixture';
  String? token = 'token-1';
  Object? tokenFailure;
  Object? reloadFailure;
  Completer<void>? tokenGate;
  int tokenReads = 0;
  int reloads = 0;

  @override
  String get email => 'session@example.test';
  @override
  bool get isAnonymous => false;
  @override
  bool get emailVerified => true;
  @override
  List<UserInfo> get providerData => const [];
  @override
  MultiFactor get multiFactor =>
      throw FirebaseAuthException(code: 'operation-not-allowed');

  // Function Name: getIdToken
  // Description: Return the scripted token or throw the scripted SDK failure.
  // Parameters: forceRefresh is ignored. Returns: the token.
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    tokenReads++;
    await tokenGate?.future;
    final failure = tokenFailure;
    if (failure != null) throw failure;
    return token;
  }

  // Function Name: reload
  // Description: Count the identity probe and throw the scripted SDK failure.
  // Parameters: none. Returns: completion.
  @override
  Future<void> reload() async {
    reloads++;
    final failure = reloadFailure;
    if (failure != null) throw failure;
  }
}

// Class Name: _SignedInFixture
// Role: Hold a control whose backend session was established through a scripted transport.
// Attributes: respond answers the next session request; requests counts them and requestedUrls
//   records where they went.
class _SignedInFixture {
  final firebase = _Firebase();
  late final AuthenticationControl control;
  FutureOr<http.Response> Function() respond = _sessionResponse;
  final requestedUrls = <String>{};
  int requests = 0;

  // Function Name: _SignedInFixture
  // Description: Build the control over the scripted transport. Parameters: observe subscribes
  //   to token changes as app start does. Returns: the fixture.
  _SignedInFixture({bool observe = false}) {
    control = AuthenticationControl.withFirebaseAuth(
      firebase,
      httpClient: MockClient((request) async {
        requestedUrls.add(request.url.toString());
        requests++;
        return respond();
      }),
      observeIdTokenChanges: observe,
    );
  }

  // Function Name: establish
  // Description: Complete the first handshake so later failures meet an established session.
  // Parameters: none. Returns: completion once the control is authenticated.
  Future<void> establish() async {
    await control.retryBackendSession();
    expect(control.isAuthenticated, isTrue);
    expect(control.errorMessage, isNull);
    expect(requestedUrls, {ApiConfig.authSessionUrl});
  }

  // Function Name: dispose
  // Description: Release the control and the token stream. Parameters: none. Returns: none.
  void dispose() {
    control.dispose();
    unawaited(firebase.tokenChanges.close());
  }
}

// Function Name: _sessionResponse
// Description: Build an authenticated session payload. Parameters: userHash names the session.
// Returns: HTTP 200 with the payload.
http.Response _sessionResponse([String userHash = 'session-hash']) {
  return http.Response(
    jsonEncode({
      'user_hash': userHash,
      'authenticated': true,
      'email_verified': true,
      'email': 'session@example.test',
    }),
    200,
  );
}

// Function Name: _status
// Description: Build a body-less server answer. Parameters: statusCode. Returns: a responder.
FutureOr<http.Response> Function() _status(int statusCode) =>
    () => http.Response('{}', statusCode);

// Function Name: _sdk
// Description: Build the SDK failure for a Firebase code. Parameters: code. Returns: the exception.
FirebaseAuthException _sdk(String code) => FirebaseAuthException(code: code);

// 함수이름: main
// 함수역할: 세션 복구 회귀 테스트를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  // Server answers and transport failures after a session was established. "kept" means the
  // session, the Firebase identity, and the error-free state all survive the failed re-sync.
  final keptServerFailures = <String, FutureOr<http.Response> Function()>{
    'HTTP 408': _status(408),
    'HTTP 429': _status(429),
    'HTTP 500': _status(500),
    'HTTP 502': _status(502),
    'HTTP 503': _status(503),
    'HTTP 504': _status(504),
    'request timeout': () => throw TimeoutException('session request'),
    'transport failure': () => throw http.ClientException('offline'),
    'TLS handshake failure': () =>
        throw const HandshakeException('captive portal'),
    'App Check unavailable': () =>
        throw const AppAttestationUnavailableException(),
    'token unavailable at send': () =>
        throw const AuthenticationUnavailableException(),
  };
  for (final entry in keptServerFailures.entries) {
    // Function Name: kept server failure test
    // Description: Verify a failure without a server verdict keeps the session.
    // Parameters: none. Returns: completed assertions.
    test('re-sync failure keeps the session: ${entry.key}', () async {
      final fixture = _SignedInFixture();
      addTearDown(fixture.dispose);
      await fixture.establish();
      final session = fixture.control.session;
      fixture.respond = entry.value;
      await fixture.control.retryBackendSession();
      expect(fixture.requests, 2);
      expect(fixture.control.session, same(session));
      expect(fixture.control.errorMessage, isNull);
      expect(fixture.control.shouldAutoRetryBackendSession, isFalse);
      expect(fixture.firebase.signOuts, 0);
    });
  }

  final refusedServerAnswers = <String, FutureOr<http.Response> Function()>{
    'HTTP 400': _status(400),
    'HTTP 403': _status(403),
    'HTTP 404': _status(404),
    'contract mismatch': () => http.Response(
      '{}',
      200,
      headers: const {'x-medbuddy-api-contract': 'incompatible-contract'},
    ),
    'malformed payload': () => http.Response('[]', 200),
    'unauthenticated payload': () => http.Response(
      jsonEncode({'user_hash': 'session-hash', 'authenticated': false}),
      200,
    ),
    'payload without a user key': () =>
        http.Response(jsonEncode({'authenticated': true}), 200),
    'unexpected failure': () => throw StateError('unexpected'),
  };
  for (final entry in refusedServerAnswers.entries) {
    // Function Name: refused server answer test
    // Description: Verify a server verdict ends the session without a provider sign-out.
    // Parameters: none. Returns: completed assertions.
    test('server verdict ends the session: ${entry.key}', () async {
      final fixture = _SignedInFixture();
      addTearDown(fixture.dispose);
      await fixture.establish();
      fixture.respond = entry.value;
      await fixture.control.retryBackendSession();
      expect(fixture.control.isAuthenticated, isFalse);
      expect(fixture.control.errorMessage, isNotNull);
      expect(fixture.control.shouldAutoRetryBackendSession, isFalse);
      expect(fixture.firebase.signOuts, 0);
    });
  }

  // Function Name: unauthorized answer test
  // Description: Verify HTTP 401 runs cleanup and signs the provider out exactly once.
  // Parameters: none. Returns: completed assertions.
  test('HTTP 401 signs the rejected session out', () async {
    final fixture = _SignedInFixture();
    addTearDown(fixture.dispose);
    await fixture.establish();
    final events = <String>[];
    fixture.control.setBeforeSignOut(() async => events.add('cleanup'));
    fixture.respond = _status(401);
    await fixture.control.retryBackendSession();
    expect(fixture.control.isAuthenticated, isFalse);
    expect(fixture.control.errorMessage, contains('expired'));
    expect(
      fixture.control.errorMessageForLanguage(isEnglish: false),
      '로그인 정보가 만료되었습니다. 다시 로그인해 주세요.',
    );
    expect(events, ['cleanup']);
    expect(fixture.firebase.signOuts, 1);
  });

  // The SDK codes that say the account or its refresh token is gone.
  for (final code in const [
    'user-token-expired',
    'user-disabled',
    'user-not-found',
    'invalid-user-token',
    'no-current-user',
  ]) {
    // Function Name: rejected identity test
    // Description: Verify a rejected identity ends the session without asking the server.
    // Parameters: none. Returns: completed assertions.
    test('token failure signs the rejected identity out: $code', () async {
      final fixture = _SignedInFixture();
      addTearDown(fixture.dispose);
      await fixture.establish();
      final events = <String>[];
      fixture.control.setBeforeSignOut(() async => events.add('cleanup'));
      fixture.firebase.user.tokenFailure = _sdk(code);
      await fixture.control.retryBackendSession();
      expect(fixture.requests, 1);
      expect(fixture.firebase.user.reloads, 0);
      expect(fixture.control.isAuthenticated, isFalse);
      expect(fixture.control.errorMessage, contains('expired'));
      expect(fixture.control.canRetryBackendSession, isFalse);
      expect(events, ['cleanup']);
      expect(fixture.firebase.signOuts, 1);
    });
  }

  // The SDK failures that say the refresh could not be attempted.
  final unavailableTokenFailures = <String, Object>{
    'network-request-failed': _sdk('network-request-failed'),
    'too-many-requests': _sdk('too-many-requests'),
    'api-not-available': _sdk('api-not-available'),
    'timeout': TimeoutException('token'),
  };
  for (final entry in unavailableTokenFailures.entries) {
    // Function Name: unavailable token test
    // Description: Verify an unattempted refresh keeps the session without probing or a request.
    // Parameters: none. Returns: completed assertions.
    test('token failure keeps the session: ${entry.key}', () async {
      final fixture = _SignedInFixture();
      addTearDown(fixture.dispose);
      await fixture.establish();
      final session = fixture.control.session;
      fixture.firebase.user.tokenFailure = entry.value;
      await fixture.control.retryBackendSession();
      expect(fixture.requests, 1);
      expect(fixture.firebase.user.reloads, 0);
      expect(fixture.control.session, same(session));
      expect(fixture.control.errorMessage, isNull);
      expect(fixture.firebase.signOuts, 0);
    });
  }

  // Codes that do not identify the cause (the Android plugin reports a rejected getIdToken as
  // `unknown`) are settled by reloading the user.
  final ambiguousTokenFailures = <String, Object>{
    'unknown': _sdk('unknown'),
    'internal-error': _sdk('internal-error'),
    'unlisted code': _sdk('keychain-error'),
    'platform failure': PlatformException(code: 'channel-error'),
  };
  for (final entry in ambiguousTokenFailures.entries) {
    for (final rejection in const [
      'user-token-expired',
      'user-disabled',
      'user-not-found',
      'invalid-user-token',
    ]) {
      // Function Name: probed rejection test
      // Description: Verify an ambiguous token failure ends the session once reload names a
      //   rejection. Parameters: none. Returns: completed assertions.
      test(
        'ambiguous token failure (${entry.key}) ends the session when reload '
        'reports $rejection',
        () async {
          final fixture = _SignedInFixture();
          addTearDown(fixture.dispose);
          await fixture.establish();
          fixture.firebase.user
            ..tokenFailure = entry.value
            ..reloadFailure = _sdk(rejection);
          await fixture.control.retryBackendSession();
          expect(fixture.firebase.user.reloads, 1);
          expect(fixture.requests, 1);
          expect(fixture.control.isAuthenticated, isFalse);
          expect(fixture.control.errorMessage, contains('expired'));
          expect(fixture.firebase.signOuts, 1);
        },
      );
    }

    final inconclusiveProbes = <String, Object?>{
      'succeeds': null,
      'fails with network-request-failed': _sdk('network-request-failed'),
      'fails with unknown': _sdk('unknown'),
      'times out': TimeoutException('reload'),
    };
    for (final probe in inconclusiveProbes.entries) {
      // Function Name: inconclusive probe test
      // Description: Verify an ambiguous token failure keeps the session unless reload names a
      //   rejection. Parameters: none. Returns: completed assertions.
      test(
        'ambiguous token failure (${entry.key}) keeps the session when reload '
        '${probe.key}',
        () async {
          final fixture = _SignedInFixture();
          addTearDown(fixture.dispose);
          await fixture.establish();
          final session = fixture.control.session;
          fixture.firebase.user
            ..tokenFailure = entry.value
            ..reloadFailure = probe.value;
          await fixture.control.retryBackendSession();
          expect(fixture.firebase.user.reloads, 1);
          expect(fixture.requests, 1);
          expect(fixture.control.session, same(session));
          expect(fixture.control.errorMessage, isNull);
          expect(fixture.firebase.signOuts, 0);
        },
      );
    }
  }

  // Function Name: missing token test
  // Description: Verify a token call that returns nothing is settled by the identity probe.
  // Parameters: none. Returns: completed assertions.
  test('a missing token is settled by the identity probe', () async {
    final fixture = _SignedInFixture();
    addTearDown(fixture.dispose);
    await fixture.establish();
    final session = fixture.control.session;
    fixture.firebase.user.token = null;
    await fixture.control.retryBackendSession();
    expect(fixture.firebase.user.reloads, 1);
    expect(fixture.control.session, same(session));
    fixture.firebase.user.reloadFailure = _sdk('user-disabled');
    await fixture.control.retryBackendSession();
    expect(fixture.control.isAuthenticated, isFalse);
    expect(fixture.firebase.signOuts, 1);
  });

  // Function Name: hanging token test
  // Description: Verify a token call that never answers is bounded and keeps the session.
  // Parameters: tester controls the clock. Returns: completed assertions.
  testWidgets('a token refresh that never answers keeps the session', (
    tester,
  ) async {
    final fixture = _SignedInFixture();
    await fixture.establish();
    final session = fixture.control.session;
    fixture.firebase.user.tokenGate = Completer<void>();
    final retry = fixture.control.retryBackendSession();
    await tester.pump(const Duration(seconds: 11));
    await retry;
    expect(fixture.requests, 1);
    expect(fixture.control.session, same(session));
    expect(fixture.control.errorMessage, isNull);
    expect(fixture.firebase.signOuts, 0);
    fixture.dispose();
  });

  // Function Name: changed identity test
  // Description: Verify a transient failure never keeps a session that belongs to another uid.
  // Parameters: none. Returns: completed assertions.
  test('a transient failure for a different identity ends the session', () async {
    final fixture = _SignedInFixture();
    addTearDown(fixture.dispose);
    await fixture.establish();
    fixture.firebase.user.uid = 'another-identity';
    fixture.respond = _status(503);
    await fixture.control.retryBackendSession();
    expect(fixture.control.isAuthenticated, isFalse);
    expect(fixture.control.errorMessage, isNotNull);
    expect(fixture.control.shouldAutoRetryBackendSession, isTrue);
  });

  // Function Name: provider sign-out test
  // Description: Verify a provider-side sign-out and a provider that no longer holds the user
  //   both end the session. Parameters: none. Returns: completed assertions.
  test('a signed-out provider ends the session', () async {
    final fixture = _SignedInFixture(observe: true);
    addTearDown(fixture.dispose);
    await fixture.establish();
    fixture.respond = _status(503);
    fixture.firebase.signedOut = true;
    fixture.firebase.tokenChanges.add(fixture.firebase.user);
    await pumpEventQueue();
    expect(fixture.control.isAuthenticated, isFalse);

    fixture.firebase.signedOut = false;
    fixture.respond = _sessionResponse;
    await fixture.control.retryBackendSession();
    expect(fixture.control.isAuthenticated, isTrue);
    fixture.firebase.tokenChanges.add(null);
    await pumpEventQueue();
    expect(fixture.control.isAuthenticated, isFalse);
    expect(fixture.control.errorMessage, isNull);
  });

  // Function Name: first handshake failure test
  // Description: Verify a failure without an established session still reports the error and
  //   leaves automatic recovery to the sign-in screen. Parameters: none. Returns: assertions.
  test('a failed first handshake has no session to keep', () async {
    final fixture = _SignedInFixture();
    addTearDown(fixture.dispose);
    fixture.respond = _status(503);
    await fixture.control.retryBackendSession();
    expect(fixture.control.isAuthenticated, isFalse);
    expect(fixture.control.errorMessage, isNotNull);
    expect(fixture.control.shouldAutoRetryBackendSession, isTrue);

    fixture.firebase.user.tokenFailure = _sdk('network-request-failed');
    await fixture.control.retryBackendSession();
    expect(fixture.requests, 1);
    expect(fixture.control.isAuthenticated, isFalse);
    expect(fixture.control.shouldAutoRetryBackendSession, isTrue);

    fixture.firebase.user.tokenFailure = _sdk('user-disabled');
    await fixture.control.retryBackendSession();
    expect(fixture.control.shouldAutoRetryBackendSession, isFalse);
    expect(fixture.control.errorMessage, contains('expired'));
    expect(fixture.firebase.signOuts, 1);
  });

  // Function Name: token refresh listener test
  // Description: Verify the hourly token-refresh path keeps the session through an outage and
  //   confirms it with a bounded backoff. Parameters: tester controls the clock. Returns: assertions.
  testWidgets('a kept session is re-checked with a bounded backoff', (
    tester,
  ) async {
    final fixture = _SignedInFixture(observe: true);
    await fixture.establish();
    final session = fixture.control.session;
    fixture.respond = _status(503);
    fixture.firebase.user.token = 'token-2';
    fixture.firebase.tokenChanges.add(fixture.firebase.user);
    await tester.pump();
    expect(fixture.requests, 2);
    expect(fixture.control.session, same(session));
    expect(fixture.control.errorMessage, isNull);

    for (final seconds in const [5, 15, 30, 60, 120]) {
      final before = fixture.requests;
      await tester.pump(Duration(seconds: seconds));
      await tester.pump();
      expect(fixture.requests, before + 1);
      expect(fixture.control.session, same(session));
    }
    await tester.pump(const Duration(minutes: 10));
    expect(fixture.requests, 7);
    expect(fixture.control.session, same(session));

    // The next token refresh starts a new series, and a success ends it.
    fixture.firebase.user.token = 'token-3';
    fixture.firebase.tokenChanges.add(fixture.firebase.user);
    await tester.pump();
    expect(fixture.requests, 8);
    fixture.respond = () => _sessionResponse('session-hash-refreshed');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(fixture.requests, 9);
    expect(fixture.control.session?.userHash, 'session-hash-refreshed');
    await tester.pump(const Duration(minutes: 10));
    expect(fixture.requests, 9);
    fixture.dispose();
  });

  // Function Name: backoff rejection test
  // Description: Verify a scheduled re-check still ends the session once the server refuses it.
  // Parameters: tester controls the clock. Returns: completed assertions.
  testWidgets('a scheduled re-check ends a session the server refuses', (
    tester,
  ) async {
    final fixture = _SignedInFixture(observe: true);
    await fixture.establish();
    fixture.respond = _status(503);
    fixture.firebase.tokenChanges.add(fixture.firebase.user);
    await tester.pump();
    expect(fixture.control.isAuthenticated, isTrue);
    fixture.respond = _status(403);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(fixture.control.isAuthenticated, isFalse);
    await tester.pump(const Duration(minutes: 10));
    expect(fixture.requests, 3);
    fixture.dispose();
  });

  // Function Name: joined handshake test
  // Description: Verify a token event that overlaps an explicit synchronization for the same
  //   token shares its request, and the operation ends only with the session in place.
  // Parameters: none. Returns: completed assertions.
  test('overlapping synchronizations share one session request', () async {
    final fixture = _SignedInFixture(observe: true);
    addTearDown(fixture.dispose);
    final response = Completer<http.Response>();
    fixture.respond = () => response.future;
    final published = <String>[];
    fixture.control.addListener(() {
      published.add(
        '${fixture.control.isBusy ? 'busy' : 'idle'}:'
        '${fixture.control.isAuthenticated ? 'session' : 'none'}',
      );
    });
    final operation = fixture.control.retryBackendSession();
    await pumpEventQueue();
    expect(fixture.requests, 1);
    fixture.firebase.tokenChanges.add(fixture.firebase.user);
    await pumpEventQueue();
    expect(fixture.requests, 1);
    response.complete(_sessionResponse());
    await operation;
    expect(fixture.requests, 1);
    expect(fixture.control.isAuthenticated, isTrue);
    expect(published, isNot(contains('idle:none')));
    expect(published.last, 'idle:session');
  });

  // Function Name: superseded synchronization test
  // Description: Verify a synchronization superseded by a new token waits for the newer result
  //   instead of releasing the caller without a session. Parameters: none. Returns: assertions.
  test('a superseded synchronization waits for the newer one', () async {
    final fixture = _SignedInFixture(observe: true);
    addTearDown(fixture.dispose);
    final responses = [Completer<http.Response>(), Completer<http.Response>()];
    fixture.respond = () => responses[fixture.requests - 1].future;
    var finished = false;
    final operation = fixture.control.retryBackendSession().whenComplete(
      () => finished = true,
    );
    await pumpEventQueue();
    fixture.firebase.user.token = 'token-2';
    fixture.firebase.tokenChanges.add(fixture.firebase.user);
    await pumpEventQueue();
    expect(fixture.requests, 2);
    responses[0].complete(_sessionResponse('stale-hash'));
    await pumpEventQueue();
    expect(finished, isFalse);
    expect(fixture.control.isBusy, isTrue);
    expect(fixture.control.isAuthenticated, isFalse);
    responses[1].complete(_sessionResponse('current-hash'));
    await operation;
    expect(fixture.control.isBusy, isFalse);
    expect(fixture.control.session?.userHash, 'current-hash');
  });

  // Function Name: public unauthorized hook test
  // Description: Verify clients created outside the control can report HTTP 401 through the
  //   public hook. Parameters: none. Returns: completed assertions.
  test('handleUnauthorizedResponse invalidates the session once', () async {
    final fixture = _SignedInFixture();
    addTearDown(fixture.dispose);
    await fixture.establish();
    final cleanup = Completer<void>();
    var cleanups = 0;
    fixture.control.setBeforeSignOut(() {
      cleanups++;
      return cleanup.future;
    });
    final first = fixture.control.handleUnauthorizedResponse();
    final second = fixture.control.handleUnauthorizedResponse();
    cleanup.complete();
    await Future.wait([first, second]);
    expect(cleanups, 1);
    expect(fixture.firebase.signOuts, 1);
    expect(fixture.control.isAuthenticated, isFalse);
    expect(fixture.control.errorMessage, contains('expired'));
  });

  // Function Name: automatic recovery test
  // Description: Verify retry backoff and termination after successful recovery.
  // Parameters: tester controls the widget and clock. Returns: completed assertions.
  testWidgets('auth screen recovers with backoff without a retry-button tap', (
    tester,
  ) async {
    final control = _SessionControl();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(home: AuthenticationUI(control: control)),
    );
    await tester.pump();
    expect(control.calls, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(control.calls, 2);
    await tester.pump(const Duration(seconds: 15));
    expect(control.calls, 3);
    await tester.pump(const Duration(minutes: 3));
    expect(control.calls, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    control.dispose();
  });

  // 함수이름: 백그라운드·화면 종료 재시도 테스트
  // 함수역할: 정상 상태 전환을 거쳐 재시도가 멈추고 복귀 시 재개되는지 검증한다.
  // 매개변수: tester: 화면·시간 제어기. 반환값: 비동기 검증 완료.
  testWidgets('background and disposed auth screens stop retrying', (
    tester,
  ) async {
    final control = _SessionControl();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(home: AuthenticationUI(control: control)),
    );
    await tester.pump();
    expect(control.calls, 1);
    // Flutter 생명주기의 중간 상태를 생략하지 않고 백그라운드 이동을 재현한다.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 3));
    expect(control.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(control.calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 3));
    expect(control.calls, 2);
    control.dispose();
  });
}
