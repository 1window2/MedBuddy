// File Name: push_notification_service_test.dart
// Role: Verifies authenticated device-token cleanup during session teardown.

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
}
