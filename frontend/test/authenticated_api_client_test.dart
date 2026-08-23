// 파일명: authenticated_api_client_test.dart
// 역할: API 계약, 인증과 App Check 헤더 적용을 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/services/user_facing_error_message.dart';

void main() {
  test('adds a Firebase bearer token to API requests', () async {
    final inner = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer verified-token');
      expect(request.headers['x-firebase-appcheck'], 'verified-app-token');
      expect(request.headers['accept'], 'application/json');
      expect(request.headers['x-medbuddy-api-contract'], 'medbuddy-api-v1');
      return http.Response('{}', 200);
    });
    final client = AuthenticatedApiClient(
      inner: inner,
      tokenProvider: () async => 'verified-token',
      appCheckTokenProvider: () async => 'verified-app-token',
      trustedBaseUri: Uri.parse('https://api.example.test/api/v1/medication'),
    );

    final response = await client.get(Uri.parse('https://api.example.test'));

    expect(response.statusCode, 200);
    client.close();
  });

  test('rejects a response with an incompatible API contract', () async {
    final client = AuthenticatedApiClient(
      inner: MockClient(
        (request) async => http.Response(
          '{}',
          200,
          headers: {'x-medbuddy-api-contract': 'medbuddy-api-v2'},
        ),
      ),
      tokenProvider: () async => null,
      appCheckTokenProvider: () async => null,
      trustedBaseUri: Uri.parse('http://localhost/api/v1/medication'),
    );

    await expectLater(
      client.get(Uri.parse('http://localhost/api/v1/medication/list')),
      throwsA(
        isA<ApiContractMismatchException>().having(
          (error) => error.serverVersion,
          'serverVersion',
          'medbuddy-api-v2',
        ),
      ),
    );

    client.close();
  });

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

  test('does not send an empty authorization header', () async {
    final inner = MockClient((request) async {
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.headers.containsKey('x-firebase-appcheck'), isFalse);
      return http.Response('{}', 200);
    });
    final client = AuthenticatedApiClient(
      inner: inner,
      tokenProvider: () async => null,
      appCheckTokenProvider: () async => null,
      trustedBaseUri: Uri.parse('http://localhost/api/v1/medication'),
    );

    await client.get(Uri.parse('http://localhost'));

    client.close();
  });

  test('omits blank credential headers without blocking the request', () async {
    final inner = MockClient((request) async {
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.headers.containsKey('x-firebase-appcheck'), isFalse);
      return http.Response('{}', 200);
    });
    final client = AuthenticatedApiClient(
      inner: inner,
      tokenProvider: () async => '   ',
      appCheckTokenProvider: () async => '\t',
      trustedBaseUri: Uri.parse('http://localhost/api/v1/medication'),
    );

    final response = await client.get(Uri.parse('http://localhost'));

    expect(response.statusCode, 200);
    client.close();
  });

  test('refuses to send a bearer token to an untrusted origin', () async {
    var requestWasSent = false;
    var tokenProviderWasCalled = false;
    var appCheckProviderWasCalled = false;
    final inner = MockClient((request) async {
      requestWasSent = true;
      return http.Response('{}', 200);
    });
    final client = AuthenticatedApiClient(
      inner: inner,
      tokenProvider: () async {
        tokenProviderWasCalled = true;
        return 'verified-token';
      },
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

  test(
    'builds the same trusted authentication headers for WebSocket',
    () async {
      final client = AuthenticatedApiClient(
        inner: MockClient((request) async => http.Response('{}', 200)),
        tokenProvider: () async => 'verified-token',
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

  test('refuses to build WebSocket headers for an untrusted origin', () async {
    var tokenProviderWasCalled = false;
    final client = AuthenticatedApiClient(
      inner: MockClient((request) async => http.Response('{}', 200)),
      tokenProvider: () async {
        tokenProviderWasCalled = true;
        return 'verified-token';
      },
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

  test('notifies the authentication control after a backend 401', () async {
    var unauthorizedCount = 0;
    final client = AuthenticatedApiClient(
      inner: MockClient((request) async => http.Response('{}', 401)),
      tokenProvider: () async => 'revoked-token',
      appCheckTokenProvider: () async => 'verified-app-token',
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

  test('does not invalidate authentication after an App Check 403', () async {
    var unauthorizedCount = 0;
    final client = AuthenticatedApiClient(
      inner: MockClient((request) async => http.Response('{}', 403)),
      tokenProvider: () async => 'verified-token',
      appCheckTokenProvider: () async => 'invalid-app-token',
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

  test('does not send a request when App Check acquisition fails', () async {
    var requestWasSent = false;
    final client = AuthenticatedApiClient(
      inner: MockClient((request) async {
        requestWasSent = true;
        return http.Response('{}', 200);
      }),
      tokenProvider: () async => 'verified-token',
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

  test(
    'does not send a request when authentication acquisition fails',
    () async {
      var requestWasSent = false;
      final client = AuthenticatedApiClient(
        inner: MockClient((request) async {
          requestWasSent = true;
          return http.Response('{}', 200);
        }),
        tokenProvider: () async => throw StateError('unavailable'),
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

  test(
    'does not send a request when authentication acquisition times out',
    () async {
      var requestWasSent = false;
      var appCheckProviderWasCalled = false;
      final client = AuthenticatedApiClient(
        inner: MockClient((request) async {
          requestWasSent = true;
          return http.Response('{}', 200);
        }),
        tokenProvider: () => Future<String?>.delayed(
          const Duration(seconds: 11),
          () => 'late-token',
        ),
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

  test(
    'does not send a request when App Check acquisition times out',
    () async {
      var requestWasSent = false;
      final client = AuthenticatedApiClient(
        inner: MockClient((request) async {
          requestWasSent = true;
          return http.Response('{}', 200);
        }),
        tokenProvider: () async => 'verified-token',
        appCheckTokenProvider: () => Future<String?>.delayed(
          const Duration(seconds: 11),
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
