// File Name: push_notification_service_test.dart
// Role: Verifies authenticated device-token cleanup during session teardown.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/services/push_notification_service.dart';

// Function Name: main
// Description:
// - Register regression cases for strict push-token cleanup after rejection or in-flight registration.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: test callback
  // Description:
  // - Verifies localized foreground copy for a server-originated missed-dose alert.
  // Parameters:
  // - None.
  // Returns:
  // - No value; synchronous assertions complete the test.
  test('missed-dose push uses the caregiver schedule copy', () {
    final korean =
        PushNotificationService.caregiverNotificationTextForTesting(
          type: 'caregiver_slot_missed',
          slotKey: 'evening',
          language: 'ko',
        );
    final english =
        PushNotificationService.caregiverNotificationTextForTesting(
          type: 'caregiver_slot_missed',
          slotKey: 'morning',
          language: 'en',
        );

    expect(korean.title, '미복용 일정 확인');
    expect(korean.body, contains('저녁'));
    expect(english.title, 'Medication not checked');
    expect(english.body, contains('morning'));
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: strict stop retries a push token after server rejection.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('strict stop retries a push token after server rejection', () async {
    var requestCount = 0;
    // Function Name: MockClient callback
    // Description:
    // - Count token-unregister attempts, reject the first DELETE, and accept the retry.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 503 on the first attempt; HTTP 200 thereafter.
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

  // Function Name: test callback
  // Description:
  // - Expected behavior: strict stop waits for an in-flight token registration.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('strict stop waits for an in-flight token registration', () async {
    final postStarted = Completer<void>();
    final allowPost = Completer<void>();
    final methods = <String>[];
    // Function Name: MockClient callback
    // Description:
    // - Record request order and hold token registration until the test permits unregistering.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 after controlled POST completion or a subsequent DELETE.
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
        // Function Name: then callback
        // Description:
        // - Record when strict push-service shutdown completes after the in-flight registration.
        // Parameters:
        // - _ (void): Unused completion value of strict shutdown.
        // Returns:
        // - The assigned completion flag; used only to record shutdown completion.
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
