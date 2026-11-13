// 파일명: regular_caregiver_completion_push_test.dart
// 역할: 보호자 복약 완료 푸시의 동시 수신·재시작 중복 방지와 구형 메시지 호환을 검증한다.

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/services/caregiver_alert_delivery_service.dart';
import 'package:medbuddy_frontend/services/notification_inbox_store.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/services/push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: _Messaging
// 역할: 테스트가 주입한 전경 메시지만 전달하는 푸시 플랫폼.
// 주요 책임: 권한과 토큰 준비를 성공 처리하고 외부 Firebase 의존성을 차단한다.
// 속성: messages는 전경 메시지용 브로드캐스트 스트림 컨트롤러.
class _Messaging extends PushMessagingPlatform {
  final messages = StreamController<RemoteMessage>.broadcast();

  // 함수이름: enabled
  // 함수역할:
  // - 푸시 서비스를 사용할 수 있는 플랫폼 상태를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 항상 true.
  @override
  bool get enabled => true;
  // 함수이름: registerBackgroundHandler
  // 함수역할:
  // - 실제 백그라운드 엔트리 등록 없이 초기화를 통과시킨다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  @override
  void registerBackgroundHandler() {}
  // 함수이름: requestPermission
  // 함수역할:
  // - 권한 요청을 사용자 창 없이 성공 처리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 즉시 완료.
  @override
  Future<void> requestPermission() async {}
  // 함수이름: getToken
  // 함수역할:
  // - 서버 등록 경로를 실행할 수 있는 고정 테스트 토큰을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<String?>: synthetic-token.
  @override
  Future<String?> getToken() async => 'synthetic-token';
  // 함수이름: deleteToken
  // 함수역할:
  // - 가짜 토큰 정리를 성공 처리하며 외부 상태는 변경하지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 즉시 완료.
  @override
  Future<void> deleteToken() async {}
  // 함수이름: onTokenRefresh
  // 함수역할:
  // - 시나리오에 없는 토큰 갱신 이벤트를 발생시키지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Stream<String>: 빈 스트림.
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  // 함수이름: onMessage
  // 함수역할:
  // - 테스트가 추가한 전경 메시지를 서비스에 전달한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Stream<RemoteMessage>: messages의 브로드캐스트 스트림.
  @override
  Stream<RemoteMessage> get onMessage => messages.stream;
  // 함수이름: onMessageOpenedApp
  // 함수역할:
  // - 알림을 눌러 앱을 여는 이벤트를 자동으로 발생시키지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Stream<RemoteMessage>: 빈 스트림.
  @override
  Stream<RemoteMessage> get onMessageOpenedApp => const Stream.empty();
  // 함수이름: getInitialMessage
  // 함수역할:
  // - 알림으로 시작하지 않은 초기 실행 상태를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<RemoteMessage?>: null.
  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
}

// 함수이름: _message
// 함수역할:
// - 완료 이벤트 키와 알림 본문 유무를 바꿀 수 있는 보호자 FCM 메시지를 만든다.
// 매개변수:
// - id(String): FCM 메시지 식별자.
// - eventKey(String?): 중복 방지 키; null이면 필드를 생략한다.
// - recipient(String): 수신 계정; 기본 caregiver-a.
// - slot(String): 시간대; 기본 morning.
// - kind(String): 이벤트 유형; 기본 정기 시간대 완료.
// - notification(bool): OS 표시용 제목/본문 포함 여부.
// 반환값:
// - RemoteMessage: 고정 환자와 한국어를 포함한 입력 메시지.
RemoteMessage _message(
  String id, {
  String? eventKey,
  String recipient = 'caregiver-a',
  String slot = 'morning',
  String kind = 'caregiver_slot_completed',
  bool notification = true,
}) => RemoteMessage(
  messageId: id,
  data: {
    'type': kind,
    'slot_key': slot,
    'patient_hash': 'patient-a',
    'recipient_hash': recipient,
    'event_key': ?eventKey,
    'language': 'ko',
  },
  notification: notification
      ? const RemoteNotification(title: '복약 상태 알림', body: '복약 상태가 변경되었습니다.')
      : null,
);

// 함수이름: main
// 함수역할:
// - 전경·백그라운드 표시 이력, 실행 알림과 완료 이벤트 키별 표시 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<Map<dynamic, dynamic>> shown;
  late _Messaging platform;
  late PushNotificationService service;
  late MockClient client;
  final eventKey = 'a' * 64;

  // 함수이름: build
  // 함수역할:
  // - 현재 가짜 플랫폼과 클라이언트를 사용하는 보호자 푸시 서비스를 새로 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - PushNotificationService: 아직 시작하지 않은 caregiver-a 서비스.
  PushNotificationService build() => PushNotificationService(
    userHash: 'caregiver-a',
    platform: platform,
    client: client,
  );

  // 함수이름: setUp
  // 함수역할:
  // - 계정 저장값과 Android 표시 채널을 초기화하고 기록용 푸시 서비스를 시작한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 테스트별 서비스와 알림 수집 준비 완료.
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      NotificationInboxStore.activeUserKey: 'caregiver-a',
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    NotificationService.instance.setShowSensitiveDetails(true);
    shown = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'show') {
            shown.add(Map<dynamic, dynamic>.from(call.arguments as Map));
          }
          return call.method == 'initialize' ? true : null;
        });
    platform = _Messaging();
    client = MockClient((_) async => http.Response('{}', 200));
    service = build();
    await service.start();
  });

  // 함수이름: tearDown
  // 함수역할:
  // - 서비스·메시지 스트림·HTTP 클라이언트를 닫고 알림 설정·시계·모의 채널을 되돌린다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 전역 상태 정리 완료.
  tearDown(() async {
    await service.stop();
    await platform.messages.close();
    client.close();
    debugDefaultTargetPlatformOverride = null;
    NotificationService.instance.setShowSensitiveDetails(true);
    NotificationService.setNotificationSelectionHandler(null);
    CaregiverAlertDeliveryService.clock = DateTime.now;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // 함수이름: 동일 완료 이벤트의 중복 방지
  // 함수역할:
  // - 동시 수신·서비스 재시작·읽음·삭제 후 재전송은 한 번만 표시하고, 같은 시간대라도 새 이벤트 키에는 새 ID를 부여하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('동일 완료 이벤트는 동시 수신과 서비스 재시작에도 한 번만 표시한다', () async {
    platform.messages.add(_message('first', eventKey: eventKey));
    platform.messages.add(_message('concurrent-retry', eventKey: eventKey));
    await pumpEventQueue();
    expect(shown, hasLength(1));
    expect((shown.single['platformSpecifics'] as Map)['onlyAlertOnce'], isTrue);
    final firstId = shown.single['id'];
    final store = NotificationInboxStore(userHash: 'caregiver-a');
    final entry = (await store.load()).single;
    await store.markRead([entry.id]);

    await service.stop();
    service = build();
    await service.start();
    platform.messages.add(_message('after-restart', eventKey: eventKey));
    await pumpEventQueue();
    expect(shown, hasLength(1));
    expect((await store.load()).single.isRead, isTrue);
    await store.remove([entry.id]);
    platform.messages.add(_message('after-dismissal', eventKey: eventKey));
    await pumpEventQueue();
    expect(shown, hasLength(1));
    expect(await store.load(), isEmpty);

    platform.messages.add(_message('new-event-same-slot', eventKey: 'b' * 64));
    await pumpEventQueue();
    expect(shown, hasLength(2));
    expect(shown.last['id'], isNot(firstId));
    expect(await store.load(), hasLength(1));
  });

  // 함수이름: 백그라운드 표시 후 전경 재수신
  // 함수역할:
  // - OS 알림이 포함된 백그라운드 수신을 받은함에 한 번 저장하고 같은 이벤트의 전경 재표시를 억제하되 새 이벤트는 표시하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('백그라운드에서 표시된 완료 이벤트의 전경 재수신은 다시 표시하지 않는다', () async {
    await medBuddyPushBackgroundHandler(
      _message('background', eventKey: eventKey),
    );
    await medBuddyPushBackgroundHandler(
      _message('background-retry', eventKey: eventKey),
    );
    platform.messages.add(_message('foreground-retry', eventKey: eventKey));
    await pumpEventQueue();
    expect(shown, isEmpty);
    expect(
      await NotificationInboxStore(userHash: 'caregiver-a').load(),
      hasLength(1),
    );
    platform.messages.add(_message('new-event', eventKey: 'b' * 64));
    await pumpEventQueue();
    expect(shown, hasLength(1));
  });

  // 함수이름: 데이터 전용 수신 후 표시
  // 함수역할:
  // - 알림 본문 없는 백그라운드 수신이 표시 마커를 소비하지 않아 같은 키의 후속 전경 알림을 표시하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('OS 알림이 없는 데이터 수신은 완료 알림 표시를 미리 소비하지 않는다', () async {
    await medBuddyPushBackgroundHandler(
      _message('data-only', eventKey: eventKey, notification: false),
    );
    platform.messages.add(_message('visible', eventKey: eventKey));
    await pumpEventQueue();
    expect(shown, hasLength(1));
  });

  // 함수이름: 선택한 완료 알림의 재수신
  // 함수역할:
  // - 알림 선택 처리로 전달 이력을 남긴 이벤트는 전경에 다시 도착해도 표시하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('기존 알림 선택으로 시작해도 해당 완료 이벤트의 재수신을 억제한다', () async {
    service.handleOpenedMessageForTesting(
      _message('opened', eventKey: eventKey),
    );
    await pumpEventQueue();
    platform.messages.add(_message('retry', eventKey: eventKey));
    await pumpEventQueue();
    expect(shown, isEmpty);
  });

  for (final key in [null, 'invalid', '${'a' * 64}\n']) {
    // 함수이름: 구형 이벤트 키 호환
    // 함수역할:
    // - 누락·잘못된 길이·개행을 가진 키에서는 FCM 식별자별 두 알림을 다른 ID로 표시하고 onlyAlertOnce를 끄는지 확인한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    test('고정 키가 없거나 잘못된 구형 메시지는 기존 FCM 식별자로 표시한다: $key', () async {
      platform.messages.add(_message('legacy-first', eventKey: key));
      await pumpEventQueue();
      platform.messages.add(_message('legacy-second', eventKey: key));
      await pumpEventQueue();
      expect(shown, hasLength(2));
      expect(shown.first['id'], isNot(shown.last['id']));
      expect(
        (shown.first['platformSpecifics'] as Map)['onlyAlertOnce'],
        isFalse,
      );
    });
  }

  // 함수이름: 다른 수신 계정 격리
  // 함수역할:
  // - 백그라운드와 전경 모두 다른 계정 대상 메시지를 표시하거나 완료 전달 마커로 저장하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('다른 계정의 완료 이벤트는 표시하거나 전달 마커를 저장하지 않는다', () async {
    final other = _message(
      'wrong-recipient',
      eventKey: eventKey,
      recipient: 'other',
    );
    await medBuddyPushBackgroundHandler(other);
    platform.messages.add(other);
    await pumpEventQueue();
    expect(shown, isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getKeys().where(
        CaregiverAlertDeliveryService.markerKeyPattern.hasMatch,
      ),
      isEmpty,
    );
  });

  // 함수이름: 비정기완료 이벤트의 마커 분리
  // 함수역할:
  // - 필요시 복용과 미복용 알림은 각각 표시하되 정기 완료용 전달 마커를 생성하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('필요시 복용 및 미복용 알림은 정기 완료 전달 마커를 사용하지 않는다', () async {
    for (final (kind, slot) in [
      ('caregiver_dose_completed', 'as_needed'),
      ('caregiver_slot_missed', 'morning'),
    ]) {
      platform.messages.add(
        _message(kind, eventKey: eventKey, kind: kind, slot: slot),
      );
      await pumpEventQueue();
    }
    expect(shown, hasLength(2));
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getKeys().where(
        CaregiverAlertDeliveryService.markerKeyPattern.hasMatch,
      ),
      isEmpty,
    );
  });

  // 함수이름: 표시 실패 후 재시도
  // 함수역할:
  // - 표시 콜백 오류가 호출자에게 전달되고 동일 키의 후속 성공 콜백을 한 번 실행할 수 있는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('표시 실패 후 같은 완료 이벤트는 재시도할 수 있다', () async {
    await expectLater(
      CaregiverAlertDeliveryService.presentCompletionOnce(
        recipientHash: 'caregiver-a',
        eventKey: eventKey,
        present: () async => throw StateError('synthetic display failure'),
      ),
      throwsStateError,
    );
    var count = 0;
    expect(
      await CaregiverAlertDeliveryService.presentCompletionOnce(
        recipientHash: 'caregiver-a',
        eventKey: eventKey,
        present: () async {
          count++;
        },
      ),
      isTrue,
    );
    expect(count, 1);
  });

  // 함수이름: 전달 시각 보관과 만료 정리
  // 함수역할:
  // - 새 알림 표시 시 8일 된 마커를 제거하고 새 마커 값에는 현재 밀리초 시각만 저장하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('전달 마커는 시각만 보존하고 오래된 마커를 정리한다', () async {
    final now = DateTime.utc(2026, 10, 22);
    CaregiverAlertDeliveryService.clock = () => now;
    final preferences = await SharedPreferences.getInstance();
    final oldKey = CaregiverAlertDeliveryService.markerKeyFor(
      'caregiver-a',
      'b' * 64,
    );
    await preferences.setInt(
      oldKey,
      now.subtract(const Duration(days: 8)).millisecondsSinceEpoch,
    );
    await CaregiverAlertDeliveryService.presentCompletionOnce(
      recipientHash: 'caregiver-a',
      eventKey: eventKey,
      present: () async {},
    );
    await preferences.reload();
    expect(preferences.containsKey(oldKey), isFalse);
    expect(
      preferences.get(
        CaregiverAlertDeliveryService.markerKeyFor('caregiver-a', eventKey),
      ),
      now.millisecondsSinceEpoch,
    );
  });
}
