// File Name: push_notification_service_test.dart
// Role: Verifies push startup (subscriptions first, registration retried after a failure) and
//   authenticated device-token cleanup during session teardown.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/services/api_config.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/services/push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Class Name: _FakePushPlatform
// Role: Stands in for Firebase Messaging so startup can be driven without Firebase.
// Responsibilities:
// - Count permission prompts, token reads, handler registrations and stream subscriptions.
// - Let a test push a refreshed token or a foreground message, and fail any single call.
// Attributes: token - token returned by getToken; initialMessage - message that launched the app;
//   failTokenReads - number of getToken calls that throw before one succeeds; log - call order.
class _FakePushPlatform extends PushMessagingPlatform {
  final tokenRefresh = StreamController<String>.broadcast();
  final messages = StreamController<RemoteMessage>.broadcast();
  final opened = StreamController<RemoteMessage>.broadcast();
  final List<String> log = [];
  String? token = 'device-token';
  RemoteMessage? initialMessage;
  int failTokenReads = 0;
  int permissionRequests = 0;
  int tokenReads = 0;
  int initialMessageReads = 0;

  @override
  bool get enabled => true;

  @override
  void registerBackgroundHandler() => log.add('background-handler');

  @override
  Future<void> requestPermission() async {
    permissionRequests++;
    log.add('permission');
  }

  @override
  Future<String?> getToken() async {
    tokenReads++;
    log.add('token');
    if (failTokenReads > 0) {
      failTokenReads--;
      throw StateError('token unavailable');
    }
    return token;
  }

  @override
  Stream<String> get onTokenRefresh {
    log.add('listen-token-refresh');
    return tokenRefresh.stream;
  }

  @override
  Stream<RemoteMessage> get onMessage {
    log.add('listen-foreground');
    return messages.stream;
  }

  @override
  Stream<RemoteMessage> get onMessageOpenedApp {
    log.add('listen-opened');
    return opened.stream;
  }

  @override
  Future<RemoteMessage?> getInitialMessage() async {
    initialMessageReads++;
    log.add('initial-message');
    return initialMessage;
  }

  // Function Name: listening
  // Description: Reports whether all three subscriptions are attached.
  // Parameters: None. Returns: True when token-refresh, foreground and opened streams have a listener.
  bool get listening =>
      tokenRefresh.hasListener && messages.hasListener && opened.hasListener;

  // Function Name: subscriptions
  // Description: Counts how many times each stream was subscribed, to catch a second subscription.
  // Parameters: name - log label of the stream. Returns: Number of subscriptions made.
  int subscriptions(String name) => log.where((entry) => entry == name).length;
}

// Function Name: main
// Description:
// - Register regression cases for strict push-token cleanup after rejection or in-flight registration.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Group: startup and registration retry
  // Description:
  // - A failed token registration must not leave push dead for the whole process: the subscriptions
  //   stay attached and registration is retried, without subscribing, prompting or registering twice.
  group('start', () {
    late _FakePushPlatform platform;
    late List<http.Request> requests;
    late int failingPosts;
    late MockClient client;

    // Function Name: build
    // Description: Creates the service under test on the fake platform and the recording client.
    // Parameters: retryMaxDelay - cap of the retry delay. Returns: The push service.
    PushNotificationService build({
      Duration retryMaxDelay = const Duration(minutes: 5),
    }) => PushNotificationService(
      userHash: 'push-start-user',
      client: client,
      platform: platform,
      retryMaxDelay: retryMaxDelay,
    );

    // Function Name: posts
    // Description: Returns the token registration requests received so far.
    List<http.Request> posts() => [
      for (final request in requests)
        if (request.method == 'POST') request,
    ];

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      platform = _FakePushPlatform();
      requests = [];
      failingPosts = 0;
      client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST' && failingPosts > 0) {
          failingPosts--;
          return http.Response('unavailable', 503);
        }
        return http.Response('{}', 200);
      });
    });

    tearDown(() {
      NotificationService.setNotificationSelectionHandler(null);
      client.close();
      // Checked here because expect may not run inside a request made while the test clock is pumped.
      for (final request in requests) {
        expect(request.url.toString(), ApiConfig.pushTokenUrl);
      }
    });

    // Function Name: failed first registration test
    // Description: The first POST fails. Subscriptions and the launch message are already handled,
    //   the retry five seconds later registers the token, and nothing is repeated.
    testWidgets('a failed registration keeps the subscriptions and is retried', (
      tester,
    ) async {
      final selections = <MedicationNotificationSelection>[];
      NotificationService.setNotificationSelectionHandler(selections.add);
      platform.initialMessage = const RemoteMessage(
        data: {
          'type': 'linked_chat_message',
          'link_id': '7',
          'recipient_hash': 'push-start-user',
        },
      );
      failingPosts = 1;
      final service = build();

      unawaited(service.start());
      await tester.pump();

      expect(posts(), hasLength(1));
      expect(platform.listening, isTrue);
      expect(selections, hasLength(1));
      // Subscriptions come before the permission prompt and the token request.
      expect(platform.log, [
        'background-handler',
        'listen-token-refresh',
        'listen-foreground',
        'listen-opened',
        'initial-message',
        'permission',
        'token',
      ]);

      await tester.pump(const Duration(seconds: 4));
      expect(posts(), hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(posts(), hasLength(2));
      expect(jsonDecode(posts().last.body), containsPair('token', 'device-token'));

      // Nothing is subscribed, prompted or dispatched a second time, and no retry remains.
      for (final stream in [
        'listen-token-refresh',
        'listen-foreground',
        'listen-opened',
        'background-handler',
      ]) {
        expect(platform.subscriptions(stream), 1);
      }
      expect(platform.permissionRequests, 1);
      expect(platform.initialMessageReads, 1);
      expect(selections, hasLength(1));
      await tester.pump(const Duration(hours: 1));
      await service.retryRegistration();
      expect(posts(), hasLength(2));

      // The retried token is the one unregistered at sign-out.
      unawaited(service.stop(requireServerUnregistration: true));
      await tester.pump();
      expect(requests.last.method, 'DELETE');
      expect(jsonDecode(requests.last.body), containsPair('token', 'device-token'));
      expect(platform.listening, isFalse);
    });

    // Function Name: growing delay test
    // Description: While the server keeps failing, attempts are spaced 5 s, 10 s, 20 s and then held
    //   at the configured cap.
    testWidgets('retries back off up to the cap while registration keeps failing', (
      tester,
    ) async {
      failingPosts = 1000;
      final service = build(retryMaxDelay: const Duration(seconds: 30));

      unawaited(service.start());
      await tester.pump();
      expect(posts(), hasLength(1));

      for (final (delay, expected) in [(5, 2), (10, 3), (20, 4), (30, 5), (30, 6)]) {
        await tester.pump(Duration(seconds: delay - 1));
        expect(posts(), hasLength(expected - 1));
        await tester.pump(const Duration(seconds: 1));
        expect(posts(), hasLength(expected));
      }
      expect(platform.permissionRequests, 1);
      expect(platform.subscriptions('listen-foreground'), 1);

      // Stopping cancels the scheduled retry and detaches the subscriptions.
      unawaited(service.stop());
      await tester.pump();
      await tester.pump(const Duration(hours: 1));
      expect(posts(), hasLength(6));
      expect(platform.listening, isFalse);
    });

    // Function Name: resume trigger test
    // Description: retryRegistration (called when the app returns to the foreground) retries at once,
    //   concurrent calls share one attempt, and success cancels the scheduled retry.
    testWidgets('retryRegistration retries immediately without duplicating the attempt', (
      tester,
    ) async {
      failingPosts = 1;
      final service = build();

      // Before start there is nothing to retry.
      await service.retryRegistration();
      expect(requests, isEmpty);
      expect(platform.log, isEmpty);

      unawaited(service.start());
      await tester.pump();
      expect(posts(), hasLength(1));

      unawaited(service.retryRegistration());
      unawaited(service.retryRegistration());
      // A repeated start behaves like a retry and joins the same attempt.
      unawaited(service.start());
      await tester.pump();
      expect(posts(), hasLength(2));
      unawaited(service.start());
      await tester.pump();
      expect(posts(), hasLength(2));
      expect(platform.subscriptions('listen-foreground'), 1);

      await tester.pump(const Duration(hours: 1));
      expect(posts(), hasLength(2));
      expect(platform.permissionRequests, 1);
      unawaited(service.stop());
      await tester.pump();
    });

    // Function Name: token read failure test
    // Description: A failure before the POST (no token yet) is retried the same way.
    testWidgets('a failed token read is retried', (tester) async {
      platform.failTokenReads = 1;
      final service = build();

      unawaited(service.start());
      await tester.pump();
      expect(posts(), isEmpty);
      expect(platform.listening, isTrue);

      await tester.pump(const Duration(seconds: 5));
      expect(platform.tokenReads, 2);
      expect(posts(), hasLength(1));
      unawaited(service.stop());
      await tester.pump();
    });

    // Function Name: duplicate token test
    // Description: Firebase reports the current token on the refresh stream while the first
    //   registration is still in flight; the same token is sent to the server once.
    test('a refresh of the token being registered does not register it twice', () async {
      final allowPost = Completer<void>();
      final postStarted = Completer<void>();
      client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          if (!postStarted.isCompleted) postStarted.complete();
          await allowPost.future;
        }
        return http.Response('{}', 200);
      });
      final service = build();

      final starting = service.start();
      await postStarted.future;
      platform.tokenRefresh.add('device-token');
      await pumpEventQueue();
      allowPost.complete();
      await starting;
      await pumpEventQueue();
      expect(posts(), hasLength(1));

      // A different token is registered.
      platform.tokenRefresh.add('rotated-token');
      await pumpEventQueue();
      expect(posts(), hasLength(2));
      expect(jsonDecode(posts().last.body), containsPair('token', 'rotated-token'));
      await service.stop();
      expect(jsonDecode(requests.last.body), containsPair('token', 'rotated-token'));
    });

    // Function Name: failed refresh test
    // Description: A refreshed token whose registration fails is registered by a later retry.
    testWidgets('a failed refreshed-token registration is retried', (tester) async {
      final service = build();
      unawaited(service.start());
      await tester.pump();
      expect(posts(), hasLength(1));

      failingPosts = 1;
      platform.token = 'rotated-token';
      platform.tokenRefresh.add('rotated-token');
      await tester.pump();
      expect(posts(), hasLength(2));

      await tester.pump(const Duration(seconds: 5));
      expect(posts(), hasLength(3));
      expect(jsonDecode(posts().last.body), containsPair('token', 'rotated-token'));
      await tester.pump(const Duration(hours: 1));
      expect(posts(), hasLength(3));
      unawaited(service.stop());
      await tester.pump();
    });

    // Function Name: stored privacy mode test
    // Description: The content-hidden mode stored on this device is applied by start, so a caregiver
    //   message received right after startup is shown without its details.
    test('start applies the stored type_only mode to foreground caregiver alerts', () async {
      SharedPreferences.setMockInitialValues({
        'user_setting_push-start-user_notification_detail_mode': 'type_only',
      });
      const channel = MethodChannel('dexterous.com/flutter/local_notifications');
      final shown = <Map<dynamic, dynamic>>[];
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'show') {
              shown.add(Map<dynamic, dynamic>.from(call.arguments as Map));
            }
            return call.method == 'initialize' ? true : null;
          });
      addTearDown(() {
        NotificationService.instance.setShowSensitiveDetails(true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      NotificationService.instance.setShowSensitiveDetails(true);
      final service = build();

      await service.start();
      // The stored mode is read before any subscription is made.
      expect(platform.log.first, 'background-handler');
      platform.messages.add(
        const RemoteMessage(
          messageId: 'completed-1',
          data: {
            'type': 'caregiver_slot_completed',
            'slot_key': 'morning',
            'patient_hash': 'patient-a',
            'recipient_hash': 'push-start-user',
          },
        ),
      );
      await pumpEventQueue();

      expect(shown.single['body'], '연동된 환자의 복약 상태가 변경되었습니다.');
      await service.stop();
    });
  });

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
  // Function Name: token registration platform test
  // Description: Verifies that only Android registers the caregiver action capability, because
  //   the notification action buttons exist only there.
  // Parameters: None. Returns: Future<void>; completes when the assertions pass.
  test('only Android registers the caregiver action capability', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(request.url.toString(), ApiConfig.pushTokenUrl);
      bodies.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await PushNotificationService(
      userHash: 'push-android-user',
      client: client,
    ).registerTokenForTesting('android-token');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await PushNotificationService(
      userHash: 'push-ios-user',
      client: client,
    ).registerTokenForTesting('ios-token');
    debugDefaultTargetPlatformOverride = null;

    expect(bodies[0]['platform'], 'android');
    expect(bodies[0]['supports_caregiver_actions'], isTrue);
    expect(bodies[1]['platform'], 'ios');
    expect(bodies[1]['supports_caregiver_actions'], isFalse);
  });

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
      expect(request.url.toString(), ApiConfig.pushTokenUrl);
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
      expect(request.url.toString(), ApiConfig.pushTokenUrl);
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
