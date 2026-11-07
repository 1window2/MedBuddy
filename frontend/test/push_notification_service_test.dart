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
// Role: Controllable Firebase Messaging substitute for push lifecycle tests.
// Responsibilities: Expose injected token/message streams, record platform calls, and fail a configured number of token reads.
// Attributes:
// - tokenRefresh, messages, opened: Broadcast controllers for refresh, foreground, and opened-message events.
// - token, initialMessage: Results returned by token and launch-message reads.
// - failTokenReads: Remaining token reads that throw StateError.
// - permissionRequests, tokenReads, initialMessageReads: Per-operation counters; log records call order.
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

  // Function Name: enabled
  // Description: Enables push startup in tests without checking the device platform.
  // Parameters: None.
  // Returns: bool; always true.
  @override
  bool get enabled => true;

  // Function Name: registerBackgroundHandler
  // Description: Records background-handler setup without registering Firebase callbacks.
  // Parameters: None.
  // Returns: void; appends background-handler to log.
  @override
  void registerBackgroundHandler() => log.add('background-handler');

  // Function Name: requestPermission
  // Description: Counts and logs a permission request without displaying a system prompt.
  // Parameters: None.
  // Returns: Future<void>; completes after updating the counter and log.
  @override
  Future<void> requestPermission() async {
    permissionRequests++;
    log.add('permission');
  }

  // Function Name: deleteToken
  // Description: Records a token-discard request without clearing the configured token or contacting Firebase.
  // Parameters: None.
  // Returns: Future<void>; completes after appending delete-token to log.
  @override
  Future<void> deleteToken() async => log.add('delete-token');

  // Function Name: getToken
  // Description: Counts and logs each read; consumes one configured failing read and throws StateError, otherwise returns token.
  // Parameters: None.
  // Returns: Future<String?>; the configured device token, including null.
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

  // Function Name: onTokenRefresh
  // Description: Logs access to the token-refresh stream so tests can detect repeated subscriptions.
  // Parameters: None.
  // Returns: Stream<String>; events injected through tokenRefresh.
  @override
  Stream<String> get onTokenRefresh {
    log.add('listen-token-refresh');
    return tokenRefresh.stream;
  }

  // Function Name: onMessage
  // Description: Logs access to the foreground-message stream without contacting Firebase.
  // Parameters: None.
  // Returns: Stream<RemoteMessage>; events injected through messages.
  @override
  Stream<RemoteMessage> get onMessage {
    log.add('listen-foreground');
    return messages.stream;
  }

  // Function Name: onMessageOpenedApp
  // Description: Logs access to the notification-open stream without platform callbacks.
  // Parameters: None.
  // Returns: Stream<RemoteMessage>; events injected through opened.
  @override
  Stream<RemoteMessage> get onMessageOpenedApp {
    log.add('listen-opened');
    return opened.stream;
  }

  // Function Name: getInitialMessage
  // Description: Counts and logs launch-message reads without consuming the configured message.
  // Parameters: None.
  // Returns: Future<RemoteMessage?>; initialMessage, or null when none is configured.
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
  // Description: Counts occurrences of a platform-call label, including stream getter access, to detect duplicated startup work.
  // Parameters: name (String) - exact label to count in log.
  // Returns: int; number of matching log entries, not the stream's current listener count.
  int subscriptions(String name) => log.where((entry) => entry == name).length;
}

// 함수이름: main
// 함수역할: 푸시 등록·재시도·해제와 알림 문구·개인정보 표시·플랫폼 기능 전달의 회귀 테스트를 등록한다.
// 매개변수: 없음.
// 반환값: void; 등록한 콜백은 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: 필요시 복용 알림 문구 테스트
  // 함수역할: 한국어와 영어 필요시 복용 푸시가 전체 복용 완료가 아닌 새 복용 기록을 안내하는지 검증한다.
  // 매개변수: 없음.
  // 반환값: void; 문구 기대값이 다르면 테스트가 실패한다.
  test('필요시 복용 푸시는 전체 완료가 아닌 새 기록으로 안내한다', () {
    for (final language in ['ko', 'en']) {
      final text = PushNotificationService.caregiverNotificationTextForTesting(
        type: 'caregiver_dose_completed',
        slotKey: 'as_needed',
        language: language,
      );
      expect(
        text.body,
        contains(
          language == 'ko' ? '필요시 약 복용을 기록' : 'recorded taking an as-needed',
        ),
      );
      expect(text.body, isNot(contains(language == 'ko' ? '모두' : 'all')));
    }
  });
  // Group: startup and registration retry
  // Description:
  // - A failed token registration must not leave push dead for the whole process: the subscriptions
  //   stay attached and registration is retried, without subscribing, prompting or registering twice.
  // 함수이름: start 테스트 그룹
  // 함수역할: 가짜 플랫폼과 HTTP 응답으로 시작 시 구독 유지, 토큰 등록 재시도·중복 방지 및 종료 동작을 검증할 사례를 등록한다.
  // 매개변수: 없음.
  // 반환값: void; 그룹의 준비·정리 콜백과 테스트를 등록한다.
  group('start', () {
    late _FakePushPlatform platform;
    late List<http.Request> requests;
    late int failingPosts;
    late bool failingDeletes;
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
    // Description: Filters the recorded HTTP requests to token-registration POST attempts.
    // Parameters: None.
    // Returns: List<http.Request>; POST requests in their original order.
    List<http.Request> posts() => [
      for (final request in requests)
        if (request.method == 'POST') request,
    ];

    // Function Name: setUp callback
    // Description: Resets preferences and the fake platform; records HTTP requests with configurable POST failures and DELETE rejection.
    // Parameters: None.
    // Returns: void; installs isolated client and failure counters for each startup test.
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      platform = _FakePushPlatform();
      requests = [];
      failingPosts = 0;
      failingDeletes = false;
      client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST' && failingPosts > 0) {
          failingPosts--;
          return http.Response('unavailable', 503);
        }
        if (request.method == 'DELETE' && failingDeletes) {
          return http.Response('unauthorized', 401);
        }
        return http.Response('{}', 200);
      });
    });

    // Function Name: tearDown callback
    // Description: Clears the notification handler, closes the client, and checks that all requests used the push-token endpoint.
    // Parameters: None.
    // Returns: void; an unexpected request URL fails the test.
    tearDown(() {
      NotificationService.setNotificationSelectionHandler(null);
      client.close();
      // Checked here because expect may not run inside a request made while the test clock is pumped.
      for (final request in requests) {
        expect(request.url.toString(), ApiConfig.pushTokenUrl);
      }
    });

    // 함수이름: 첫 등록 실패 후 재시도 테스트
    // 함수역할: 첫 POST 실패에도 구독과 시작 메시지 처리가 유지되고 5초 뒤 한 번 재시도하며, 성공 뒤 중복 등록 없이 종료 시 토큰을 해제하는지 검증한다.
    // 매개변수: tester (WidgetTester) - 재시도 타이머와 비동기 시작·종료를 진행하는 테스트 실행기.
    // 반환값: Future<void>; 구독 횟수·요청 순서·메시지 전달 기대값이 다르면 실패한다.
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
      expect(
        jsonDecode(posts().last.body),
        containsPair('token', 'device-token'),
      );

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
      expect(
        jsonDecode(requests.last.body),
        containsPair('token', 'device-token'),
      );
      expect(platform.listening, isFalse);
    });

    // 함수이름: 등록 재시도 간격 상한 테스트
    // 함수역할: 연속 실패 시 간격이 5·10·20초에서 설정된 30초 상한까지 증가하고, 구독·권한 요청은 반복하지 않으며 종료 후 재시도를 멈추는지 검증한다.
    // 매개변수: tester (WidgetTester) - 재시도 간격을 가상 시간으로 진행하는 실행기.
    // 반환값: Future<void>; 각 시점의 요청 횟수나 종료 후 동작이 다르면 실패한다.
    testWidgets(
      'retries back off up to the cap while registration keeps failing',
      (tester) async {
        failingPosts = 1000;
        final service = build(retryMaxDelay: const Duration(seconds: 30));

        unawaited(service.start());
        await tester.pump();
        expect(posts(), hasLength(1));

        for (final (delay, expected) in [
          (5, 2),
          (10, 3),
          (20, 4),
          (30, 5),
          (30, 6),
        ]) {
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
      },
    );

    // 함수이름: 즉시 재시도 중복 방지 테스트
    // 함수역할: 시작 전 재시도는 무시하고, 시작 후 겹친 즉시 재시도는 한 요청을 공유하며 성공하면 예약된 재시도가 취소되는지 검증한다.
    // 매개변수: tester (WidgetTester) - 겹친 요청과 재시도 타이머를 진행하는 실행기.
    // 반환값: Future<void>; 등록·권한 요청 횟수가 기대와 다르면 실패한다.
    testWidgets(
      'retryRegistration retries immediately without duplicating the attempt',
      (tester) async {
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
      },
    );

    // 함수이름: 서버 해제 실패 토큰 폐기 테스트
    // 함수역할: 일반 종료는 기기 토큰을 보존하지만 해제 실패 후 명시적으로 폐기를 요청하면 한 번만 삭제하고 후속 종료에서는 재처리하지 않는지 검증한다.
    // 매개변수: tester (WidgetTester) - 비동기 등록과 종료를 진행하는 실행기.
    // 반환값: Future<void>; DELETE 또는 기기 토큰 삭제 횟수가 다르면 실패한다.
    testWidgets(
      'a token the server could not unregister is discarded on request',
      (tester) async {
        final service = build();
        unawaited(service.start());
        await tester.pump();
        expect(posts(), hasLength(1));

        failingDeletes = true;
        unawaited(service.stop());
        await tester.pump();
        expect(platform.log, isNot(contains('delete-token')));

        unawaited(service.stop(discardUnregisteredToken: true));
        await tester.pump();
        expect(requests.last.method, 'DELETE');
        expect(platform.subscriptions('delete-token'), 1);

        // The token is gone; a further stop has nothing left to unregister or discard.
        final deletes = requests
            .where((request) => request.method == 'DELETE')
            .length;
        unawaited(service.stop(discardUnregisteredToken: true));
        await tester.pump();
        expect(
          requests.where((request) => request.method == 'DELETE'),
          hasLength(deletes),
        );
        expect(platform.subscriptions('delete-token'), 1);
      },
    );

    // 함수이름: 이전 실행에서 등록됐을 수 있는 토큰 해제 테스트
    // 함수역할: 현재 실행의 등록이 계속 실패해도 이전 실행의 서버 등록을 정리하도록 종료 시 기기 토큰의 DELETE를 보내는지 검증한다.
    // 매개변수: tester (WidgetTester) - 실패한 등록과 종료를 진행하는 실행기.
    // 반환값: Future<void>; 해제 요청의 토큰이나 메서드가 다르면 실패한다.
    testWidgets(
      'a token registered by an earlier run is unregistered on stop',
      (tester) async {
        failingPosts = 100;
        final service = build();
        unawaited(service.start());
        await tester.pump();
        expect(posts(), hasLength(1));

        unawaited(service.stop());
        await tester.pump();

        expect(requests.last.method, 'DELETE');
        expect(requests.last.body, contains('"token"'));
      },
    );

    // 함수이름: 서버 해제 성공 시 기기 토큰 보존 테스트
    // 함수역할: 서버 해제가 성공하면 실패 토큰 폐기 옵션을 켜도 기기 토큰은 삭제하지 않는지 검증한다.
    // 매개변수: tester (WidgetTester) - 등록과 종료 요청을 진행하는 실행기.
    // 반환값: Future<void>; 기기 토큰 삭제가 발생하면 실패한다.
    testWidgets('a token the server unregistered is kept on the device', (
      tester,
    ) async {
      final service = build();
      unawaited(service.start());
      await tester.pump();

      unawaited(service.stop(discardUnregisteredToken: true));
      await tester.pump();
      expect(requests.last.method, 'DELETE');
      expect(platform.log, isNot(contains('delete-token')));
    });

    // Function Name: token read failure test
    // Description: Verifies that an initial token-read exception leaves subscriptions attached and retries the read after five seconds before registering.
    // Parameters: tester (WidgetTester) - advances startup and the retry timer.
    // Returns: Future<void>; fails if token reads, subscriptions, or POST counts differ.
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

    for (final unavailableToken in <String?>[null, '   ']) {
      // 함수이름: 토큰 미발급 상태의 자동 재시도 테스트
      // 함수역할: null 또는 공백 토큰은 등록하지 않고 재조회하며, 유효한 토큰을 얻으면 권한 요청·시작 메시지 처리를 반복하지 않고 등록 후 재시도를 멈추는지 검증한다.
      // 매개변수: tester (WidgetTester) - 5초·10초 재시도와 성공 후 대기 시간을 진행하는 실행기.
      // 반환값: Future<void>; 토큰 조회·등록·권한 요청 횟수가 다르면 실패한다.
      testWidgets(
        'an unavailable token is retried without another prompt: $unavailableToken',
        (tester) async {
          platform.token = unavailableToken;
          final service = build();
          unawaited(service.start());
          await tester.pump();
          expect(posts(), isEmpty);
          expect(platform.listening, isTrue);

          await tester.pump(const Duration(seconds: 5));
          expect(platform.tokenReads, 2);
          expect(posts(), isEmpty);
          platform.token = 'ready-token';
          await tester.pump(const Duration(seconds: 10));
          expect(posts(), hasLength(1));
          expect(
            jsonDecode(posts().single.body),
            containsPair('token', 'ready-token'),
          );
          expect(platform.permissionRequests, 1);
          expect(platform.initialMessageReads, 1);
          expect(platform.subscriptions('listen-foreground'), 1);
          await tester.pump(const Duration(minutes: 10));
          expect(platform.tokenReads, 3);
          unawaited(service.stop());
          await tester.pump();
        },
      );
    }

    // 함수이름: 토큰 미발급 후 즉시 재시도 테스트
    // 함수역할: 처음 없던 토큰이 준비되면 전경 복귀용 재시도가 즉시 등록하고 기존 재시도 타이머는 더 조회하지 않는지 검증한다.
    // 매개변수: tester (WidgetTester) - 시작·즉시 재시도와 후속 대기 시간을 진행하는 실행기.
    // 반환값: Future<void>; 토큰 조회나 등록 횟수가 다르면 실패한다.
    testWidgets('foreground retry recovers a token that was initially absent', (
      tester,
    ) async {
      platform.token = null;
      final service = build();
      unawaited(service.start());
      await tester.pump();
      platform.token = 'ready-token';
      unawaited(service.retryRegistration());
      await tester.pump();
      expect(posts(), hasLength(1));
      await tester.pump(const Duration(minutes: 10));
      expect(platform.tokenReads, 2);
      unawaited(service.stop());
      await tester.pump();
    });

    // 함수이름: 등록 중 동일 토큰 갱신 중복 방지 테스트
    // 함수역할: 등록 진행 중 같은 토큰의 갱신 이벤트는 중복 POST를 만들지 않고, 이후 바뀐 토큰은 새로 등록해 종료 시 그 토큰을 해제하는지 검증한다.
    // 매개변수: 없음.
    // 반환값: Future<void>; 등록 횟수나 등록·해제 토큰이 다르면 실패한다.
    test(
      'a refresh of the token being registered does not register it twice',
      () async {
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
        expect(
          jsonDecode(posts().last.body),
          containsPair('token', 'rotated-token'),
        );
        await service.stop();
        expect(
          jsonDecode(requests.last.body),
          containsPair('token', 'rotated-token'),
        );
      },
    );

    // 함수이름: 갱신 토큰 등록 실패 후 재시도 테스트
    // 함수역할: 갱신된 토큰의 등록이 실패하면 5초 뒤 해당 토큰을 재등록하고 성공 뒤에는 추가 요청을 보내지 않는지 검증한다.
    // 매개변수: tester (WidgetTester) - 갱신 이벤트와 재시도 타이머를 진행하는 실행기.
    // 반환값: Future<void>; POST 횟수나 재시도 토큰이 다르면 실패한다.
    testWidgets('a failed refreshed-token registration is retried', (
      tester,
    ) async {
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
      expect(
        jsonDecode(posts().last.body),
        containsPair('token', 'rotated-token'),
      );
      await tester.pump(const Duration(hours: 1));
      expect(posts(), hasLength(3));
      unawaited(service.stop());
      await tester.pump();
    });

    // 함수이름: 저장된 알림 내용 숨김 설정 적용 테스트
    // 함수역할: 시작 시 저장된 type_only 설정을 적용하여 바로 수신한 보호자 알림에도 환자·복약 상세 대신 일반 안내 문구를 표시하는지 검증한다.
    // 매개변수: 없음.
    // 반환값: Future<void>; 표시된 알림 본문이 기대값과 다르면 실패한다.
    test(
      'start applies the stored type_only mode to foreground caregiver alerts',
      () async {
        SharedPreferences.setMockInitialValues({
          'user_setting_push-start-user_notification_detail_mode': 'type_only',
        });
        const channel = MethodChannel(
          'dexterous.com/flutter/local_notifications',
        );
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
      },
    );
  });

  // 함수이름: 미복용 푸시 현지화 문구 테스트
  // 함수역할: 서버의 미복용 알림에 한국어·영어 제목과 해당 저녁·아침 시간대 문구가 포함되는지 검증한다.
  // 매개변수: 없음.
  // 반환값: void; 제목이나 시간대 문구가 다르면 실패한다.
  test('missed-dose push uses the caregiver schedule copy', () {
    final korean = PushNotificationService.caregiverNotificationTextForTesting(
      type: 'caregiver_slot_missed',
      slotKey: 'evening',
      language: 'ko',
    );
    final english = PushNotificationService.caregiverNotificationTextForTesting(
      type: 'caregiver_slot_missed',
      slotKey: 'morning',
      language: 'en',
    );

    expect(korean.title, '미복용 일정 확인');
    expect(korean.body, contains('저녁'));
    expect(english.title, 'Medication not checked');
    expect(english.body, contains('morning'));
  });

  // 함수이름: 플랫폼별 보호자 알림 동작 지원 등록 테스트
  // 함수역할: 토큰 등록 본문의 플랫폼 값과 보호자·복용 확인 동작 지원 값이 Android에서만 활성화되고 iOS에서는 비활성화되는지 검증한다.
  // 매개변수: 없음.
  // 반환값: Future<void>; 전송한 플랫폼 또는 지원 값이 다르면 실패한다.
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
    expect(bodies[0]['supports_slot_check_actions'], isTrue);
    expect(bodies[1]['platform'], 'ios');
    expect(bodies[1]['supports_caregiver_actions'], isFalse);
    expect(bodies[1]['supports_slot_check_actions'], isFalse);
  });

  // Function Name: strict stop rejection retry test
  // Description: Verifies that strict shutdown throws StateError on a rejected DELETE, retries the retained token successfully, and sends no third request.
  // Parameters: None.
  // Returns: Future<void>; fails if rejection is swallowed or the unregister count is not two.
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

  // Function Name: strict stop in-flight registration test
  // Description: Verifies that strict shutdown stays pending until an in-flight POST finishes, then unregisters the token with DELETE.
  // Parameters: None.
  // Returns: Future<void>; fails if shutdown finishes early or request order differs from POST then DELETE.
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
