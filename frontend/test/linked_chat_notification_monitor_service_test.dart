// 파일명: linked_chat_notification_monitor_service_test.dart
// 역할: 연동 채팅의 읽지 않은 메시지 감시와 로컬 알림 조건을 검증한다.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/services/linked_chat_notification_monitor_service.dart';
import 'package:medbuddy_frontend/services/linked_chat_realtime_service.dart';

void main() {
  test('상대가 보낸 새 채팅을 한 번만 알림으로 전달한다', () async {
    final sources = <int, _FakeLinkedChatEventSource>{};
    final alerts = <String>[];
    var permissionRequestCount = 0;
    final monitor = LinkedChatNotificationMonitorService(
      currentUserHash: 'caregiver_test',
      loadLinks: () async => [_activeLink(7)],
      eventSourceFactory: (linkId) {
        return sources.putIfAbsent(linkId, _FakeLinkedChatEventSource.new);
      },
      sendAlert: ({required linkId, required messageId}) async {
        alerts.add('$linkId:$messageId');
      },
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

    expect(alerts, ['7:31']);
    expect(permissionRequestCount, 1);
  });

  test('본인이 보낸 채팅과 형식이 잘못된 이벤트는 알리지 않는다', () async {
    final source = _FakeLinkedChatEventSource();
    var alertCount = 0;
    final monitor = LinkedChatNotificationMonitorService(
      currentUserHash: 'patient_test',
      loadLinks: () async => [_activeLink(9)],
      eventSourceFactory: (_) => source,
      sendAlert: ({required linkId, required messageId}) async {
        alertCount += 1;
      },
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

  test('연동 목록이 바뀌면 제거된 연결을 닫고 새 연결을 시작한다', () async {
    var links = <PatientCaregiverLink>[_activeLink(11)];
    final sources = <int, _FakeLinkedChatEventSource>{};
    final monitor = LinkedChatNotificationMonitorService(
      currentUserHash: 'caregiver_test',
      loadLinks: () async => links,
      eventSourceFactory: (linkId) {
        return sources.putIfAbsent(linkId, _FakeLinkedChatEventSource.new);
      },
      sendAlert: ({required linkId, required messageId}) async {},
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

  test('알림 권한이 거부되면 같은 메시지를 이후 이벤트에서 다시 확인한다', () async {
    final source = _FakeLinkedChatEventSource();
    var alertCount = 0;
    final monitor = LinkedChatNotificationMonitorService(
      currentUserHash: 'caregiver_test',
      loadLinks: () async => [_activeLink(13)],
      eventSourceFactory: (_) => source,
      sendAlert: ({required linkId, required messageId}) async {
        alertCount += 1;
      },
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

  test('실험실 기능을 끄면 연결과 채팅 알림을 모두 중지한다', () async {
    final source = _FakeLinkedChatEventSource();
    var featureEnabled = true;
    var alertCount = 0;
    final monitor = LinkedChatNotificationMonitorService(
      currentUserHash: 'caregiver_test',
      loadLinks: () async => [_activeLink(15)],
      eventSourceFactory: (_) => source,
      sendAlert: ({required linkId, required messageId}) async {
        alertCount += 1;
      },
      permissionRequester: () async => true,
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

PatientCaregiverLink _activeLink(int linkId) {
  return PatientCaregiverLink(
    linkId: linkId,
    patientHash: 'patient_test',
    caregiverHash: 'caregiver_test',
    linkStatus: true,
  );
}

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

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeLinkedChatEventSource implements LinkedChatEventSource {
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  bool started = false;
  bool disposed = false;

  @override
  Stream<Map<String, dynamic>> get events => _controller.stream;

  @override
  Future<void> start() async {
    started = true;
  }

  void emit(Map<String, dynamic> event) {
    _controller.add(event);
  }

  @override
  Future<void> dispose() async {
    if (disposed) {
      return;
    }
    disposed = true;
    await _controller.close();
  }
}
