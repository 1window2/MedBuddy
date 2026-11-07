import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';

void main() {
  for (final transition in [
    'same',
    'other-account',
    'signed-out',
    'closed',
    'unavailable',
  ]) {
    test(
      'a delayed 401 only invalidates its current session: $transition',
      () async {
        String? token = 'account-a-token';
        var unavailable = false;
        var invalidations = 0;
        final started = Completer<void>();
        final response = Completer<http.Response>();
        final client = AuthenticatedApiClient(
          inner: MockClient((request) {
            expect(request.headers['authorization'], 'Bearer account-a-token');
            started.complete();
            return response.future;
          }),
          tokenProvider: () async {
            if (unavailable) throw StateError('token temporarily unavailable');
            return token;
          },
          appCheckRequired: false,
          onUnauthorized: () async {
            invalidations++;
          },
          trustedBaseUri: Uri.parse('https://api.example.test'),
        );
        addTearDown(client.close);
        final pending = client.get(
          Uri.parse('https://api.example.test/schedule'),
        );
        await started.future;
        if (transition == 'other-account') token = 'account-b-token';
        if (transition == 'signed-out') token = null;
        if (transition == 'closed') client.close();
        if (transition == 'unavailable') unavailable = true;
        response.complete(http.Response('{}', 401));

        expect((await pending).statusCode, 401);
        expect(invalidations, transition == 'same' ? 1 : 0);
      },
    );
  }

  test(
    'the global unauthorized handler also ignores another account response',
    () async {
      String? token = 'account-a-token';
      var invalidations = 0;
      final previous = AuthenticatedApiClient.defaultOnUnauthorized;
      AuthenticatedApiClient.defaultOnUnauthorized = () async {
        invalidations++;
      };
      addTearDown(
        () => AuthenticatedApiClient.defaultOnUnauthorized = previous,
      );
      final client = AuthenticatedApiClient(
        inner: MockClient((_) async {
          token = 'account-b-token';
          return http.Response('{}', 401);
        }),
        tokenProvider: () async => token,
        appCheckRequired: false,
        trustedBaseUri: Uri.parse('https://api.example.test'),
      );
      addTearDown(client.close);

      expect(
        (await client.get(Uri.parse('https://api.example.test'))).statusCode,
        401,
      );
      expect(invalidations, 0);
    },
  );
}
