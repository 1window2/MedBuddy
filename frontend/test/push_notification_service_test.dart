// File Name: push_notification_service_test.dart
// Role: Verifies authenticated device-token cleanup during session teardown.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/services/push_notification_service.dart';

void main() {
  test('strict stop retries a push token after server rejection', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount += 1;
      expect(request.method, 'DELETE');
      return http.Response(
        requestCount == 1 ? 'rejected' : '{}',
        requestCount == 1 ? 503 : 200,
      );
    });
    final service = PushNotificationService(
      userHash: 'push-test-user',
      client: client,
    );
    service.setRegisteredTokenForTesting('device-token');

    await expectLater(
      service.stop(requireServerUnregistration: true),
      throwsStateError,
    );
    await service.stop(requireServerUnregistration: true);
    await service.stop(requireServerUnregistration: true);

    expect(requestCount, 2);
    client.close();
  });

  test('strict stop waits for an in-flight token registration', () async {
    final postStarted = Completer<void>();
    final allowPost = Completer<void>();
    final methods = <String>[];
    final client = MockClient((request) async {
      methods.add(request.method);
      if (request.method == 'POST') {
        postStarted.complete();
        await allowPost.future;
        return http.Response('{}', 200);
      }
      expect(request.method, 'DELETE');
      return http.Response('{}', 200);
    });
    final service = PushNotificationService(
      userHash: 'push-race-user',
      client: client,
    );

    final registration = service.registerTokenForTesting('race-token');
    await postStarted.future;
    var stopCompleted = false;
    final stopping = service
        .stop(requireServerUnregistration: true)
        .then((_) => stopCompleted = true);
    await Future<void>.delayed(Duration.zero);

    expect(stopCompleted, isFalse);
    expect(methods, ['POST']);

    allowPost.complete();
    await Future.wait([registration, stopping]);

    expect(methods, ['POST', 'DELETE']);
    expect(stopCompleted, isTrue);
    client.close();
  });
}
