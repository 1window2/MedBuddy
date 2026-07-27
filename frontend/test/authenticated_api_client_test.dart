import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';

void main() {
  test('adds a Firebase bearer token to API requests', () async {
    final inner = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer verified-token');
      expect(request.headers['accept'], 'application/json');
      return http.Response('{}', 200);
    });
    final client = AuthenticatedApiClient(
      inner: inner,
      tokenProvider: () async => 'verified-token',
      trustedBaseUri: Uri.parse('https://api.example.test/api/v1/medication'),
    );

    final response = await client.get(Uri.parse('https://api.example.test'));

    expect(response.statusCode, 200);
    client.close();
  });

  test('does not send an empty authorization header', () async {
    final inner = MockClient((request) async {
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response('{}', 200);
    });
    final client = AuthenticatedApiClient(
      inner: inner,
      tokenProvider: () async => null,
      trustedBaseUri: Uri.parse('http://localhost/api/v1/medication'),
    );

    await client.get(Uri.parse('http://localhost'));

    client.close();
  });

  test('refuses to send a bearer token to an untrusted origin', () async {
    var requestWasSent = false;
    final inner = MockClient((request) async {
      requestWasSent = true;
      return http.Response('{}', 200);
    });
    final client = AuthenticatedApiClient(
      inner: inner,
      tokenProvider: () async => 'verified-token',
      trustedBaseUri: Uri.parse(
        'https://api.medbuddy.example/api/v1/medication',
      ),
    );

    await expectLater(
      client.get(Uri.parse('https://untrusted.example/collect')),
      throwsA(isA<StateError>()),
    );
    expect(requestWasSent, isFalse);

    client.close();
  });

  test('notifies the authentication control after a backend 401', () async {
    var unauthorizedCount = 0;
    final client = AuthenticatedApiClient(
      inner: MockClient((request) async => http.Response('{}', 401)),
      tokenProvider: () async => 'revoked-token',
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
}
