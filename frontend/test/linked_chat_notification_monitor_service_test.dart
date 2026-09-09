// 파일명: linked_chat_notification_monitor_service_test.dart
// 역할: 연동 채팅의 읽지 않은 메시지 감시와 로컬 알림 조건을 검증한다.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/services/linked_chat_notification_monitor_service.dart';
import 'package:medbuddy_frontend/services/linked_chat_realtime_service.dart';

// 함수이름: main
// 함수역할:
// - 복약 대화 알림 중복 억제, 권한 재시도와 연결 생명주기 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 상대가 보낸 새 채팅을 한 번만 알림으로 전달한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('상대가 보낸 새 채팅을 한 번만 알림으로 전달한다', () async {
    final sources = <int, _FakeLinkedChatEventSource>{};
    final alerts = <String>[];
    var permissionRequestCount = 0;
    final monitor = LinkedChatNotificationMonitorService(
      currentUserHash: 'caregiver_test',
      // 함수이름: loadLinks 콜백
      // 함수역할:
      // - 활성 연결 목록을 제공해 추가·제거에 따른 채팅 구독 변화를 검사한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 지정한 활성 환자·보호자 연결 목록.
      loadLinks: () async => [_activeLink(7)],
      // 함수이름: eventSourceFactory 콜백
      // 함수역할:
      // - 연결별 가짜 이벤트 소스를 한 번 생성해 재사용한다.
      // 매개변수:
      // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자.
      // 반환값:
      // - 연결에 배정된 가짜 이벤트 소스.
      eventSourceFactory: (linkId) {
        return sources.putIfAbsent(linkId, _FakeLinkedChatEventSource.new);
      },
      sendAlert:
          // 함수이름: sendAlert 콜백
          // 함수역할:
          // - 연결·메시지 식별자와 본문을 기록해 새 메시지 알림의 중복 여부를 검사한다.
          // 매개변수:
          // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자.
          // - messageId (int): 채팅 메시지의 서버 식별자.
          // - messageBody (String): 알림 전송기로 전달한 수신 채팅 본문.
          // - messageKind (ChatMessageKind): 일반 텍스트 또는 복약 문맥 메시지 유형. 이 대역에서는 직접 사용하지 않는다.
          // - slotKey (String): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - Future<void>; 알림 기록 추가 완료.
          ({
            required linkId,
            required messageId,
            required messageBody,
            required messageKind,
            required slotKey,
          }) async {
            alerts.add('$linkId:$messageId:$messageBody');
          },
      // 함수이름: permissionRequester 콜백
      // 함수역할:
      // - 권한 조회 횟수를 기록하고 알림 권한 허용을 제공한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - true로 완료되는 Future<bool>.
      permissionRequester: () async {
        permissionRequestCount += 1;
        return true;
      },
      linkRefreshInterval: const Duration(hours: 1),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    expect(sources[7]?.started, isTrue);

    final event = _messageEvent(
      messageId: 31,
      linkId: 7,
      senderHash: 'patient_test',
    );
    sources[7]!.emit(event);
    sources[7]!.emit(event);
    await _flushEvents();

    expect(alerts, ['7:31:테스트 메시지']);
    expect(permissionRequestCount, 1);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 본인이 보낸 채팅과 형식이 잘못된 이벤트는 알리지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('본인이 보낸 채팅과 형식이 잘못된 이벤트는 알리지 않는다', () async {
    final source = _FakeLinkedChatEventSource();
    var alertCount = 0;
    final monitor = LinkedChatNotificationMonitorService(
      currentUserHash: 'patient_test',
      // 함수이름: loadLinks 콜백
      // 함수역할:
      // - 활성 연결 목록을 제공해 추가·제거에 따른 채팅 구독 변화를 검사한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 지정한 활성 환자·보호자 연결 목록.
      loadLinks: () async => [_activeLink(9)],
      // 함수이름: eventSourceFactory 콜백
      // 함수역할:
      // - 주입한 이벤트 소스를 재사용해 메시지 전달을 제어한다.
      // 매개변수:
      // - _ (int): 같은 이벤트 소스를 재사용하므로 무시하는 연결 식별자.
      // 반환값:
      // - 연결에 배정된 가짜 이벤트 소스.
      eventSourceFactory: (_) => source,
      sendAlert:
          // 함수이름: sendAlert 콜백
          // 함수역할:
          // - 실제 기기 알림 대신 전송 횟수를 기록해 이벤트 필터와 재시도 조건을 검사한다.
          // 매개변수:
          // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - messageId (int): 채팅 메시지의 서버 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - messageBody (String): 알림 전송기로 전달한 수신 채팅 본문. 이 대역에서는 직접 사용하지 않는다.
          // - messageKind (ChatMessageKind): 일반 텍스트 또는 복약 문맥 메시지 유형. 이 대역에서는 직접 사용하지 않는다.
          // - slotKey (String): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - Future<void>; 알림 횟수 증가 완료.
          ({
            required linkId,
            required messageId,
            required messageBody,
            required messageKind,
            required slotKey,
          }) async {
            alertCount += 1;
          },
      // 함수이름: permissionRequester 콜백
      // 함수역할:
      // - 기기 권한 창 없이 알림 권한 허용을 재현한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - true로 완료되는 Future<bool>.
      permissionRequester: () async => true,
      linkRefreshInterval: const Duration(hours: 1),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    source.emit(
      _messageEvent(messageId: 41, linkId: 9, senderHash: 'patient_test'),
    );
    source.emit({'type': 'chat_message', 'message': const <String, Object>{}});
    source.emit({'type': 'chat_read'});
    await _flushEvents();

    expect(alertCount, 0);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 연동 목록이 바뀌면 제거된 연결을 닫고 새 연결을 시작한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('연동 목록이 바뀌면 제거된 연결을 닫고 새 연결을 시작한다', () async {
    var links = <PatientCaregiverLink>[_activeLink(11)];
    final sources = <int, _FakeLinkedChatEventSource>{};
    final monitor = LinkedChatNotificationMonitorService(
      currentUserHash: 'caregiver_test',
      // 함수이름: loadLinks 콜백
      // 함수역할:
      // - 활성 연결 목록을 제공해 추가·제거에 따른 채팅 구독 변화를 검사한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 지정한 활성 환자·보호자 연결 목록.
      loadLinks: () async => links,
      // 함수이름: eventSourceFactory 콜백
      // 함수역할:
      // - 연결별 가짜 이벤트 소스를 한 번 생성해 재사용한다.
      // 매개변수:
      // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자.
      // 반환값:
      // - 연결에 배정된 가짜 이벤트 소스.
      eventSourceFactory: (linkId) {
        return sources.putIfAbsent(linkId, _FakeLinkedChatEventSource.new);
      },
      sendAlert:
          // 함수이름: sendAlert 콜백
          // 함수역할:
          // - 감시기의 조회·연결 상태를 검사하는 동안 실제 기기 알림은 표시하지 않는다.
          // 매개변수:
          // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - messageId (int): 채팅 메시지의 서버 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - messageBody (String): 알림 전송기로 전달한 수신 채팅 본문. 이 대역에서는 직접 사용하지 않는다.
          // - messageKind (ChatMessageKind): 일반 텍스트 또는 복약 문맥 메시지 유형. 이 대역에서는 직접 사용하지 않는다.
          // - slotKey (String): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - Future<void>; 알림 표시 없이 완료된다.
          ({
            required linkId,
            required messageId,
            required messageBody,
            required messageKind,
            required slotKey,
          }) async {},
      // 함수이름: permissionRequester 콜백
      // 함수역할:
      // - 기기 권한 창 없이 알림 권한 허용을 재현한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - true로 완료되는 Future<bool>.
      permissionRequester: () async => true,
      linkRefreshInterval: const Duration(hours: 1),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    links = [_activeLink(12)];
    expect(await monitor.refreshNow(), isTrue);

    expect(sources[11]?.disposed, isTrue);
    expect(sources[12]?.started, isTrue);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 알림 권한이 거부되면 같은 메시지를 이후 이벤트에서 다시 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('알림 권한이 거부되면 같은 메시지를 이후 이벤트에서 다시 확인한다', () async {
    final source = _FakeLinkedChatEventSource();
    var alertCount = 0;
    final monitor = LinkedChatNotificationMonitorService(
      currentUserHash: 'caregiver_test',
      // 함수이름: loadLinks 콜백
      // 함수역할:
      // - 활성 연결 목록을 제공해 추가·제거에 따른 채팅 구독 변화를 검사한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 지정한 활성 환자·보호자 연결 목록.
      loadLinks: () async => [_activeLink(13)],
      // 함수이름: eventSourceFactory 콜백
      // 함수역할:
      // - 주입한 이벤트 소스를 재사용해 메시지 전달을 제어한다.
      // 매개변수:
      // - _ (int): 같은 이벤트 소스를 재사용하므로 무시하는 연결 식별자.
      // 반환값:
      // - 연결에 배정된 가짜 이벤트 소스.
      eventSourceFactory: (_) => source,
      sendAlert:
          // 함수이름: sendAlert 콜백
          // 함수역할:
          // - 실제 기기 알림 대신 전송 횟수를 기록해 이벤트 필터와 재시도 조건을 검사한다.
          // 매개변수:
          // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - messageId (int): 채팅 메시지의 서버 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - messageBody (String): 알림 전송기로 전달한 수신 채팅 본문. 이 대역에서는 직접 사용하지 않는다.
          // - messageKind (ChatMessageKind): 일반 텍스트 또는 복약 문맥 메시지 유형. 이 대역에서는 직접 사용하지 않는다.
          // - slotKey (String): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - Future<void>; 알림 횟수 증가 완료.
          ({
            required linkId,
            required messageId,
            required messageBody,
            required messageKind,
            required slotKey,
          }) async {
            alertCount += 1;
          },
      // 함수이름: permissionRequester 콜백
      // 함수역할:
      // - 기기 권한 창 없이 알림 권한 거부을 재현한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - false로 완료되는 Future<bool>.
      permissionRequester: () async => false,
      linkRefreshInterval: const Duration(hours: 1),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    final event = _messageEvent(
      messageId: 51,
      linkId: 13,
      senderHash: 'patient_test',
    );
    source.emit(event);
    source.emit(event);
    await _flushEvents();

    expect(alertCount, 0);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 실험실 기능을 끄면 연결과 채팅 알림을 모두 중지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('실험실 기능을 끄면 연결과 채팅 알림을 모두 중지한다', () async {
    final source = _FakeLinkedChatEventSource();
    var featureEnabled = true;
    var alertCount = 0;
    final monitor = LinkedChatNotificationMonitorService(
      currentUserHash: 'caregiver_test',
      // 함수이름: loadLinks 콜백
      // 함수역할:
      // - 활성 연결 목록을 제공해 추가·제거에 따른 채팅 구독 변화를 검사한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 지정한 활성 환자·보호자 연결 목록.
      loadLinks: () async => [_activeLink(15)],
      // 함수이름: eventSourceFactory 콜백
      // 함수역할:
      // - 주입한 이벤트 소스를 재사용해 메시지 전달을 제어한다.
      // 매개변수:
      // - _ (int): 같은 이벤트 소스를 재사용하므로 무시하는 연결 식별자.
      // 반환값:
      // - 연결에 배정된 가짜 이벤트 소스.
      eventSourceFactory: (_) => source,
      sendAlert:
          // 함수이름: sendAlert 콜백
          // 함수역할:
          // - 실제 기기 알림 대신 전송 횟수를 기록해 이벤트 필터와 재시도 조건을 검사한다.
          // 매개변수:
          // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - messageId (int): 채팅 메시지의 서버 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - messageBody (String): 알림 전송기로 전달한 수신 채팅 본문. 이 대역에서는 직접 사용하지 않는다.
          // - messageKind (ChatMessageKind): 일반 텍스트 또는 복약 문맥 메시지 유형. 이 대역에서는 직접 사용하지 않는다.
          // - slotKey (String): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - Future<void>; 알림 횟수 증가 완료.
          ({
            required linkId,
            required messageId,
            required messageBody,
            required messageKind,
            required slotKey,
          }) async {
            alertCount += 1;
          },
      // 함수이름: permissionRequester 콜백
      // 함수역할:
      // - 기기 권한 창 없이 알림 권한 허용을 재현한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - true로 완료되는 Future<bool>.
      permissionRequester: () async => true,
      // 함수이름: featureEnabledLoader 콜백
      // 함수역할:
      // - 알림 스트림 연결 전에 변경 가능한 채팅 실험 기능 상태를 읽는다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 현재 실험 기능 활성 여부.
      featureEnabledLoader: () async => featureEnabled,
      linkRefreshInterval: const Duration(hours: 1),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    expect(source.started, isTrue);

    featureEnabled = false;
    source.emit(
      _messageEvent(messageId: 61, linkId: 15, senderHash: 'patient_test'),
    );
    await _flushEvents();
    expect(alertCount, 0);

    expect(await monitor.refreshNow(), isTrue);
    expect(source.disposed, isTrue);
  });
}

// 함수이름: _activeLink
// 함수역할:
// - 지정 연결 식별자로 고정 환자와 보호자의 활성 연결을 만든다.
// 매개변수:
// - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자.
// 반환값:
// - 알림 감시 대상인 활성 연결 한 건.
PatientCaregiverLink _activeLink(int linkId) {
  return PatientCaregiverLink(
    linkId: linkId,
    patientHash: 'patient_test',
    caregiverHash: 'caregiver_test',
    linkStatus: true,
  );
}

// 함수이름: _messageEvent
// 함수역할:
// - 지정 발신자와 메시지 식별자를 가진 미확인 채팅 이벤트를 만든다.
// 매개변수:
// - messageId (int): 채팅 메시지의 서버 식별자.
// - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자.
// - senderHash (String): 수신 메시지를 보낸 사용자 식별자.
// 반환값:
// - chat_message 유형과 메시지 데이터가 있는 맵.
Map<String, dynamic> _messageEvent({
  required int messageId,
  required int linkId,
  required String senderHash,
}) {
  return {
    'type': 'chat_message',
    'message': {
      'message_id': messageId,
      'link_id': linkId,
      'sender_hash': senderHash,
      'client_message_id': 'client-$messageId',
      'body': '테스트 메시지',
      'created_at': '2026-08-23T12:00:00+09:00',
      'read_at': null,
    },
  };
}

// 함수이름: _flushEvents
// 함수역할:
// - 연속 두 이벤트 루프를 양보해 채팅 이벤트와 후속 비동기 처리가 진행되게 한다.
// 매개변수:
// - 없음.
// 반환값:
// - 대기 중 이벤트 처리 기회 두 번이 지난 완료 상태.
Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

// 클래스명: _FakeLinkedChatEventSource
// 역할: 메시지 이벤트 주입과 시작·폐기 상태 확인을 지원하는 채팅 이벤트 소스 대역.
// 주요 책임:
// - 테스트가 주입한 채팅 이벤트를 감시기에 노출한다.
// - 실제 연결 없이 이벤트 소스가 시작되었음을 기록한다.
// - 지정 채팅 이벤트를 구독 중인 감시기로 전달한다.
// 속성:
// - started (bool): 이벤트 소스가 시작되었는지 여부.
// - disposed (bool): 이벤트 소스가 이미 닫혔는지 여부.
class _FakeLinkedChatEventSource implements LinkedChatEventSource {
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  bool started = false;
  bool disposed = false;

  // 함수이름: events
  // 함수역할:
  // - 테스트가 주입한 채팅 이벤트를 감시기에 노출한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 내부 브로드캐스트 이벤트 스트림.
  @override
  Stream<Map<String, dynamic>> get events => _controller.stream;

  // 함수이름: start
  // 함수역할:
  // - 실제 연결 없이 이벤트 소스가 시작되었음을 기록한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 시작 플래그 설정 완료.
  @override
  Future<void> start() async {
    started = true;
  }

  // 함수이름: emit
  // 함수역할:
  // - 지정 채팅 이벤트를 구독 중인 감시기로 전달한다.
  // 매개변수:
  // - event (Map<String, dynamic>): 스트림으로 보낼 가상 복약 대화 이벤트.
  // 반환값:
  // - 없음; 내부 스트림에 이벤트가 추가된다.
  void emit(Map<String, dynamic> event) {
    _controller.add(event);
  }

  // 함수이름: dispose
  // 함수역할:
  // - 중복 폐기를 무시하고 최초 폐기 시 이벤트 스트림을 닫는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 이벤트 스트림 종료 완료 또는 이미 폐기된 경우 즉시 완료.
  @override
  Future<void> dispose() async {
    if (disposed) {
      return;
    }
    disposed = true;
    await _controller.close();
  }
}
