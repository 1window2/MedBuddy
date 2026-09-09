// File Name: authenticated_api_client_test.dart
// Role: Regression coverage for authenticated HTTP/WebSocket headers, contract versions, and
//   credential failures.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/services/user_facing_error_message.dart';

// Function Name: main
// Description:
// - Register regression cases for authenticated HTTP/WebSocket headers, contract versions, and
//   credential failures.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - Firebase 인증, App Check, JSON 수신 및 API 계약 헤더가 요청에 함께 포함되는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('adds a Firebase bearer token to API requests', () async {
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - Firebase·App Check·JSON·API 계약 헤더를 검사하고 요청 성공을 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 빈 JSON 본문의 HTTP 200 응답.
    final inner = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer verified-token');
      expect(request.headers['x-firebase-appcheck'], 'verified-app-token');
      expect(request.headers['accept'], 'application/json');
      expect(request.headers['x-medbuddy-api-contract'], 'medbuddy-api-v1');
      return http.Response('{}', 200);
    });
    final client = AuthenticatedApiClient(
      inner: inner,
      // Function Name: tokenProvider callback
      // Description:
      // - Supply Firebase Auth test credentials 'verified-token' without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing 'verified-token'.
      tokenProvider: () async => 'verified-token',
      // Function Name: appCheckTokenProvider callback
      // Description:
      // - Supply App Check test credentials 'verified-app-token' without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing 'verified-app-token'.
      appCheckTokenProvider: () async => 'verified-app-token',
      trustedBaseUri: Uri.parse('https://api.example.test/api/v1/medication'),
    );

    final response = await client.get(Uri.parse('https://api.example.test'));

    expect(response.statusCode, 200);
    client.close();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 호환되지 않는 서버 API 계약 버전을 오류로 보고하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('rejects a response with an incompatible API contract', () async {
    final client = AuthenticatedApiClient(
      inner: MockClient(
        // 함수이름: MockClient 콜백
        // 함수역할:
        // - 클라이언트와 호환되지 않는 v2 계약 헤더를 응답에 붙인다.
        // 매개변수:
        // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청. 이 대역에서는 직접 사용하지 않는다.
        // 반환값:
        // - medbuddy-api-v2 헤더가 있는 HTTP 200 응답.
        (request) async => http.Response(
          '{}',
          200,
          headers: {'x-medbuddy-api-contract': 'medbuddy-api-v2'},
        ),
      ),
      // Function Name: tokenProvider callback
      // Description:
      // - Supply Firebase Auth absence without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing null.
      tokenProvider: () async => null,
      // Function Name: appCheckTokenProvider callback
      // Description:
      // - Supply App Check absence without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing null.
      appCheckTokenProvider: () async => null,
      trustedBaseUri: Uri.parse('http://localhost/api/v1/medication'),
    );

    await expectLater(
      client.get(Uri.parse('http://localhost/api/v1/medication/list')),
      throwsA(
        isA<ApiContractMismatchException>().having(
          // 함수이름: having 콜백
          // 함수역할:
          // - 오류의 호환되지 않는 서버 계약 버전를 추출해 해당 필드를 검증한다.
          // 매개변수:
          // - error (Object): 매처가 검사할 유형화된 예외.
          // 반환값:
          // - 예외의 serverVersion 값.
          (error) => error.serverVersion,
          'serverVersion',
          'medbuddy-api-v2',
        ),
      ),
    );

    client.close();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 인증 중 계약 버전 불일치를 앱 업데이트 안내로 변환하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('maps an incompatible auth handshake to an update instruction', () {
    const error = ApiContractMismatchException('medbuddy-api-v2');

    expect(
      AuthenticationControl.resolveBackendSessionError(error, isEnglish: false),
      '현재 앱 버전이 서버와 호환되지 않습니다. MedBuddy를 업데이트해주세요.',
    );
    expect(
      AuthenticationControl.resolveBackendSessionError(error, isEnglish: true),
      'This app version is not compatible with the server. Please update MedBuddy.',
    );
    expect(
      UserFacingErrorMessage.resolve(error, isEnglish: false),
      contains('업데이트'),
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: does not send an empty authorization header.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('does not send an empty authorization header', () async {
    // Function Name: MockClient callback
    // Description:
    // - Assert that missing or blank credentials do not produce authorization or App Check headers.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 with an empty JSON body.
    final inner = MockClient((request) async {
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.headers.containsKey('x-firebase-appcheck'), isFalse);
      return http.Response('{}', 200);
    });
    final client = AuthenticatedApiClient(
      inner: inner,
      // Function Name: tokenProvider callback
      // Description:
      // - Supply Firebase Auth absence without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing null.
      tokenProvider: () async => null,
      // Function Name: appCheckTokenProvider callback
      // Description:
      // - Supply App Check absence without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing null.
      appCheckTokenProvider: () async => null,
      trustedBaseUri: Uri.parse('http://localhost/api/v1/medication'),
    );

    await client.get(Uri.parse('http://localhost'));

    client.close();
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: omits blank credential headers without blocking the request.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('omits blank credential headers without blocking the request', () async {
    // Function Name: MockClient callback
    // Description:
    // - Assert that missing or blank credentials do not produce authorization or App Check headers.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 with an empty JSON body.
    final inner = MockClient((request) async {
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.headers.containsKey('x-firebase-appcheck'), isFalse);
      return http.Response('{}', 200);
    });
    final client = AuthenticatedApiClient(
      inner: inner,
      // Function Name: tokenProvider callback
      // Description:
      // - Supply Firebase Auth blank credentials without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing ' '.
      tokenProvider: () async => '   ',
      // Function Name: appCheckTokenProvider callback
      // Description:
      // - Supply App Check blank credentials without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing '\t'.
      appCheckTokenProvider: () async => '\t',
      trustedBaseUri: Uri.parse('http://localhost/api/v1/medication'),
    );

    final response = await client.get(Uri.parse('http://localhost'));

    expect(response.statusCode, 200);
    client.close();
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: refuses to send a bearer token to an untrusted origin.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('refuses to send a bearer token to an untrusted origin', () async {
    var requestWasSent = false;
    var tokenProviderWasCalled = false;
    var appCheckProviderWasCalled = false;
    // Function Name: MockClient callback
    // Description:
    // - Record any transport invocation so fail-closed tests can prove no request escaped credential
    //   checks.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
    //   consumed by this fixture.
    // Returns:
    // - HTTP 200 if the transport is reached.
    final inner = MockClient((request) async {
      requestWasSent = true;
      return http.Response('{}', 200);
    });
    final client = AuthenticatedApiClient(
      inner: inner,
      // Function Name: tokenProvider callback
      // Description:
      // - Supply Firebase Auth test credentials 'verified-token' without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing 'verified-token'.
      tokenProvider: () async {
        tokenProviderWasCalled = true;
        return 'verified-token';
      },
      // Function Name: appCheckTokenProvider callback
      // Description:
      // - Supply App Check test credentials 'verified-app-token' without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing 'verified-app-token'.
      appCheckTokenProvider: () async {
        appCheckProviderWasCalled = true;
        return 'verified-app-token';
      },
      trustedBaseUri: Uri.parse(
        'https://api.medbuddy.example/api/v1/medication',
      ),
    );

    await expectLater(
      client.get(Uri.parse('https://untrusted.example/collect')),
      throwsA(isA<StateError>()),
    );
    expect(requestWasSent, isFalse);
    expect(tokenProviderWasCalled, isFalse);
    expect(appCheckProviderWasCalled, isFalse);

    client.close();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 신뢰된 WebSocket 연결에도 HTTP와 동일한 인증 헤더를 구성하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'builds the same trusted authentication headers for WebSocket',
    () async {
      final client = AuthenticatedApiClient(
        // 함수이름: MockClient 콜백
        // 함수역할:
        // - 네트워크 없이 HTTP 200 상태와 빈 JSON 객체를 제공한다.
        // 매개변수:
        // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청. 이 대역에서는 직접 사용하지 않는다.
        // 반환값:
        // - HTTP 200 응답 Future.
        inner: MockClient((request) async => http.Response('{}', 200)),
        // Function Name: tokenProvider callback
        // Description:
        // - Supply Firebase Auth test credentials 'verified-token' without contacting Firebase.
        // Parameters:
        // - None.
        // Returns:
        // - Future<String?> containing 'verified-token'.
        tokenProvider: () async => 'verified-token',
        // Function Name: appCheckTokenProvider callback
        // Description:
        // - Supply App Check test credentials 'verified-app-token' without contacting Firebase.
        // Parameters:
        // - None.
        // Returns:
        // - Future<String?> containing 'verified-app-token'.
        appCheckTokenProvider: () async => 'verified-app-token',
        trustedBaseUri: Uri.parse(
          'https://api.medbuddy.example/api/v1/medication',
        ),
      );

      final headers = await client.buildAuthenticationHeaders(
        Uri.parse('wss://api.medbuddy.example/api/v1/chat/links/17/stream'),
      );

      expect(headers['Authorization'], 'Bearer verified-token');
      expect(headers['X-Firebase-AppCheck'], 'verified-app-token');
      expect(headers['X-MedBuddy-Api-Contract'], 'medbuddy-api-v1');
      client.close();
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 신뢰하지 않는 WebSocket 주소는 토큰 조회 전에 거부되는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('refuses to build WebSocket headers for an untrusted origin', () async {
    var tokenProviderWasCalled = false;
    final client = AuthenticatedApiClient(
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 네트워크 없이 HTTP 200 상태와 빈 JSON 객체를 제공한다.
      // 매개변수:
      // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청. 이 대역에서는 직접 사용하지 않는다.
      // 반환값:
      // - HTTP 200 응답 Future.
      inner: MockClient((request) async => http.Response('{}', 200)),
      // Function Name: tokenProvider callback
      // Description:
      // - Supply Firebase Auth test credentials 'verified-token' without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing 'verified-token'.
      tokenProvider: () async {
        tokenProviderWasCalled = true;
        return 'verified-token';
      },
      // Function Name: appCheckTokenProvider callback
      // Description:
      // - Supply App Check test credentials 'verified-app-token' without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing 'verified-app-token'.
      appCheckTokenProvider: () async => 'verified-app-token',
      trustedBaseUri: Uri.parse(
        'https://api.medbuddy.example/api/v1/medication',
      ),
    );

    await expectLater(
      client.buildAuthenticationHeaders(
        Uri.parse('wss://untrusted.example/api/v1/chat/links/17/stream'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(tokenProviderWasCalled, isFalse);
    client.close();
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: notifies the authentication control after a backend 401.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('notifies the authentication control after a backend 401', () async {
    var unauthorizedCount = 0;
    final client = AuthenticatedApiClient(
      // Function Name: MockClient callback
      // Description:
      // - Complete the mocked HTTP request with status 401 and an empty JSON object without network access.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
      //   consumed by this fixture.
      // Returns:
      // - Future<http.Response> with status 401.
      inner: MockClient((request) async => http.Response('{}', 401)),
      // Function Name: tokenProvider callback
      // Description:
      // - Supply Firebase Auth test credentials 'revoked-token' without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing 'revoked-token'.
      tokenProvider: () async => 'revoked-token',
      // Function Name: appCheckTokenProvider callback
      // Description:
      // - Supply App Check test credentials 'verified-app-token' without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing 'verified-app-token'.
      appCheckTokenProvider: () async => 'verified-app-token',
      // Function Name: onUnauthorized callback
      // Description:
      // - Count authentication invalidations so backend 401 and App Check 403 can be distinguished.
      // Parameters:
      // - None.
      // Returns:
      // - No value; the callback completes after its recorded side effects.
      onUnauthorized: () async {
        unauthorizedCount += 1;
      },
      trustedBaseUri: Uri.parse('https://api.example.test'),
    );

    final response = await client.get(Uri.parse('https://api.example.test'));

    expect(response.statusCode, 401);
    expect(unauthorizedCount, 1);
    client.close();
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: does not invalidate authentication after an App Check 403.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('does not invalidate authentication after an App Check 403', () async {
    var unauthorizedCount = 0;
    final client = AuthenticatedApiClient(
      // Function Name: MockClient callback
      // Description:
      // - Complete the mocked HTTP request with status 403 and an empty JSON object without network access.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
      //   consumed by this fixture.
      // Returns:
      // - Future<http.Response> with status 403.
      inner: MockClient((request) async => http.Response('{}', 403)),
      // Function Name: tokenProvider callback
      // Description:
      // - Supply Firebase Auth test credentials 'verified-token' without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing 'verified-token'.
      tokenProvider: () async => 'verified-token',
      // Function Name: appCheckTokenProvider callback
      // Description:
      // - Supply App Check test credentials 'invalid-app-token' without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing 'invalid-app-token'.
      appCheckTokenProvider: () async => 'invalid-app-token',
      // Function Name: onUnauthorized callback
      // Description:
      // - Count authentication invalidations so backend 401 and App Check 403 can be distinguished.
      // Parameters:
      // - None.
      // Returns:
      // - No value; the callback completes after its recorded side effects.
      onUnauthorized: () async {
        unauthorizedCount += 1;
      },
      trustedBaseUri: Uri.parse('https://api.example.test'),
    );

    final response = await client.get(Uri.parse('https://api.example.test'));

    expect(response.statusCode, 403);
    expect(unauthorizedCount, 0);
    client.close();
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: does not send a request when App Check acquisition fails.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('does not send a request when App Check acquisition fails', () async {
    var requestWasSent = false;
    final client = AuthenticatedApiClient(
      // Function Name: MockClient callback
      // Description:
      // - Record any transport invocation so fail-closed tests can prove no request escaped credential
      //   checks.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
      //   consumed by this fixture.
      // Returns:
      // - HTTP 200 if the transport is reached.
      inner: MockClient((request) async {
        requestWasSent = true;
        return http.Response('{}', 200);
      }),
      // Function Name: tokenProvider callback
      // Description:
      // - Supply Firebase Auth test credentials 'verified-token' without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing 'verified-token'.
      tokenProvider: () async => 'verified-token',
      // Function Name: appCheckTokenProvider callback
      // Description:
      // - Fail App Check token acquisition to exercise fail-closed request handling.
      // Parameters:
      // - None.
      // Returns:
      // - A Future that fails with the configured StateError.
      appCheckTokenProvider: () async => throw StateError('unavailable'),
      trustedBaseUri: Uri.parse('https://api.example.test'),
    );

    await expectLater(
      client.get(Uri.parse('https://api.example.test')),
      throwsA(isA<AppAttestationUnavailableException>()),
    );
    expect(requestWasSent, isFalse);
    client.close();
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: off-Play beta mode skips App Check without weakening Firebase Auth.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('off-Play beta mode skips App Check without weakening Firebase Auth', () async {
    var appCheckProviderWasCalled = false;
    // Function Name: MockClient callback
    // Description:
    // - Assert that off-Play requests retain Firebase authorization while omitting App Check.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 with an empty JSON body.
    final inner = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer verified-token');
      expect(request.headers.containsKey('x-firebase-appcheck'), isFalse);
      return http.Response('{}', 200);
    });
    final client = AuthenticatedApiClient(
      inner: inner,
      // Function Name: tokenProvider callback
      // Description:
      // - Supply Firebase Auth test credentials 'verified-token' without contacting Firebase.
      // Parameters:
      // - None.
      // Returns:
      // - Future<String?> containing 'verified-token'.
      tokenProvider: () async => 'verified-token',
      // Function Name: appCheckTokenProvider callback
      // Description:
      // - Detect unexpected App Check invocation in off-Play mode by recording the call and throwing.
      // Parameters:
      // - None.
      // Returns:
      // - A Future that fails with the configured StateError.
      appCheckTokenProvider: () async {
        appCheckProviderWasCalled = true;
        throw StateError('Play Integrity is unavailable');
      },
      appCheckRequired: false,
      trustedBaseUri: Uri.parse('https://api.example.test'),
    );

    final response = await client.get(Uri.parse('https://api.example.test'));

    expect(response.statusCode, 200);
    expect(appCheckProviderWasCalled, isFalse);
    client.close();
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: does not send a request when authentication acquisition fails.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'does not send a request when authentication acquisition fails',
    () async {
      var requestWasSent = false;
      final client = AuthenticatedApiClient(
        // Function Name: MockClient callback
        // Description:
        // - Record any transport invocation so fail-closed tests can prove no request escaped credential
        //   checks.
        // Parameters:
        // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
        //   consumed by this fixture.
        // Returns:
        // - HTTP 200 if the transport is reached.
        inner: MockClient((request) async {
          requestWasSent = true;
          return http.Response('{}', 200);
        }),
        // Function Name: tokenProvider callback
        // Description:
        // - Fail Firebase Auth token acquisition to exercise fail-closed request handling.
        // Parameters:
        // - None.
        // Returns:
        // - A Future that fails with the configured StateError.
        tokenProvider: () async => throw StateError('unavailable'),
        // Function Name: appCheckTokenProvider callback
        // Description:
        // - Supply App Check test credentials 'verified-app-token' without contacting Firebase.
        // Parameters:
        // - None.
        // Returns:
        // - Future<String?> containing 'verified-app-token'.
        appCheckTokenProvider: () async => 'verified-app-token',
        trustedBaseUri: Uri.parse('https://api.example.test'),
      );

      await expectLater(
        client.get(Uri.parse('https://api.example.test')),
        throwsA(isA<AuthenticationUnavailableException>()),
      );
      expect(requestWasSent, isFalse);
      client.close();
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: does not send a request when authentication acquisition times out.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'does not send a request when authentication acquisition times out',
    () async {
      var requestWasSent = false;
      var appCheckProviderWasCalled = false;
      final client = AuthenticatedApiClient(
        // Function Name: MockClient callback
        // Description:
        // - Record any transport invocation so fail-closed tests can prove no request escaped credential
        //   checks.
        // Parameters:
        // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
        //   consumed by this fixture.
        // Returns:
        // - HTTP 200 if the transport is reached.
        inner: MockClient((request) async {
          requestWasSent = true;
          return http.Response('{}', 200);
        }),
        // Function Name: tokenProvider callback
        // Description:
        // - Delay Firebase Auth token acquisition beyond the credential timeout.
        // Parameters:
        // - None.
        // Returns:
        // - A token Future that resolves after eleven seconds.
        tokenProvider: () => Future<String?>.delayed(
          const Duration(seconds: 11),
          // Function Name: Future<String?>.delayed callback
          // Description:
          // - Resolve the delayed credential after the request timeout has already elapsed.
          // Parameters:
          // - None.
          // Returns:
          // - The delayed token 'late-token'.
          () => 'late-token',
        ),
        // Function Name: appCheckTokenProvider callback
        // Description:
        // - Supply App Check test credentials 'verified-app-token' without contacting Firebase.
        // Parameters:
        // - None.
        // Returns:
        // - Future<String?> containing 'verified-app-token'.
        appCheckTokenProvider: () async {
          appCheckProviderWasCalled = true;
          return 'verified-app-token';
        },
        trustedBaseUri: Uri.parse('https://api.example.test'),
      );

      await expectLater(
        client.get(Uri.parse('https://api.example.test')),
        throwsA(isA<AuthenticationUnavailableException>()),
      );
      expect(requestWasSent, isFalse);
      expect(appCheckProviderWasCalled, isFalse);
      client.close();
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: does not send a request when App Check acquisition times out.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'does not send a request when App Check acquisition times out',
    () async {
      var requestWasSent = false;
      final client = AuthenticatedApiClient(
        // Function Name: MockClient callback
        // Description:
        // - Record any transport invocation so fail-closed tests can prove no request escaped credential
        //   checks.
        // Parameters:
        // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
        //   consumed by this fixture.
        // Returns:
        // - HTTP 200 if the transport is reached.
        inner: MockClient((request) async {
          requestWasSent = true;
          return http.Response('{}', 200);
        }),
        // Function Name: tokenProvider callback
        // Description:
        // - Supply Firebase Auth test credentials 'verified-token' without contacting Firebase.
        // Parameters:
        // - None.
        // Returns:
        // - Future<String?> containing 'verified-token'.
        tokenProvider: () async => 'verified-token',
        // Function Name: appCheckTokenProvider callback
        // Description:
        // - Delay App Check token acquisition beyond the credential timeout.
        // Parameters:
        // - None.
        // Returns:
        // - A token Future that resolves after eleven seconds.
        appCheckTokenProvider: () => Future<String?>.delayed(
          const Duration(seconds: 11),
          // Function Name: Future<String?>.delayed callback
          // Description:
          // - Resolve the delayed credential after the request timeout has already elapsed.
          // Parameters:
          // - None.
          // Returns:
          // - The delayed token 'late-app-token'.
          () => 'late-app-token',
        ),
        trustedBaseUri: Uri.parse('https://api.example.test'),
      );

      await expectLater(
        client.get(Uri.parse('https://api.example.test')),
        throwsA(isA<AppAttestationUnavailableException>()),
      );
      expect(requestWasSent, isFalse);
      client.close();
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}
