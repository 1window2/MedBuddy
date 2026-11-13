// File Name: linked_chat_notification_monitor_factory_test.dart
// Role: Verifies the chat-notification gate the monitor factory wires in: the chat switch and
//   the notification-detail setting are read right before each alert.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/composition/linked_chat_notification_monitor_factory.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/services/slot_check_notification_context.dart';

import 'support/fake_notification_service.dart';

// 함수이름: _deliver
// 함수역할:
// - 고정된 연동 17·아침 시간대·현재 시각으로 채팅 알림 전달 경로를 실행하고, 날짜가 있으면 환자 확인 요청 문맥을 함께 만든다.
// 매개변수:
// - notifications (RecordingNotificationService): 실제 플랫폼 대신 알림 호출을 기록할 대역.
// - setting (UserSetting): 전달 직전에 읽을 언어·알림 허용·상세 표시 설정.
// - messageId (int): 기본 41인 메시지 번호와 이벤트 ID 구성 값.
// - userHash (String): 알림 수신 계정, 기본 caregiver-a.
// - scheduleDate (String?): null이면 확인 요청 문맥 없음; 날짜 문자열이면 patient-a의 해당 복용일 문맥을 만든다.
// - messageKind (ChatMessageKind): 기본 slotCheckRequest인 메시지 종류.
// - loadSummary (Future<ChatNotificationSummary?> Function()?): 선택적인 읽지 않은 메시지 요약 조회 함수.
// 반환값:
// - Future<void>; 설정과 수신 범위에 따른 알림 전달 또는 억제가 끝나면 완료한다.
Future<void> _deliver(
  RecordingNotificationService notifications,
  UserSetting setting, {
  int messageId = 41,
  String userHash = 'caregiver-a',
  String? scheduleDate,
  ChatMessageKind messageKind = ChatMessageKind.slotCheckRequest,
  Future<ChatNotificationSummary?> Function()? loadSummary,
}) {
  return deliverLinkedChatAlert(
    loadSetting: () async => setting,
    notifications: notifications,
    userHash: userHash,
    linkId: 17,
    messageId: messageId,
    messageBody: 'Did you take the morning dose?',
    messageKind: messageKind,
    slotKey: 'morning',
    clock: () => DateTime.utc(2026, 11, 7, 3),
    slotCheck: scheduleDate == null
        ? null
        : SlotCheckNotificationContext.fromData({
            'type': 'linked_chat_message',
            'message_kind': 'slot_check_request',
            'action_version': '1',
            'recipient_hash': 'patient-a',
            'patient_hash': 'patient-a',
            'link_id': 17,
            'message_id': messageId,
            'event_id': 'chat:17:$messageId',
            'schedule_date': scheduleDate,
            'slot_key': 'morning',
          }),
    loadSummary: loadSummary,
  );
}

// 함수이름: main
// 함수역할:
// - 실제 알림 플러그인 없이 채팅 설정, 환자·복용일 범위, 상세 표시, 알림 ID와 요약 조회 실패를 검증하는 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - void; 반환값 없음.
void main() {
  for (final mode in ['full', 'type_only']) {
    // 함수이름: 오늘의 환자 확인 요청에 복용 버튼과 알림함 기록을 연결한다: $mode
    // 함수역할:
    // - 오늘 날짜의 동일 환자 확인 요청은 일반 채팅 대신 복용 버튼 알림과 알림함 기록을 만들며, full에서만 미리보기를 전달하는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    test('오늘의 환자 확인 요청에 복용 버튼과 알림함 기록을 연결한다: $mode', () async {
      final notifications = RecordingNotificationService();
      await _deliver(
        notifications,
        UserSetting(language: 'en', notificationDetailMode: mode),
        userHash: 'patient-a',
        scheduleDate: '2026-11-07',
      );
      expect(notifications.linkedChatAlerts, isEmpty);
      final alert = notifications.slotCheckAlerts.single;
      expect(alert.request.slotKey, 'morning');
      expect(alert.language, 'en');
      expect(alert.recordHistory, isTrue);
      expect(
        alert.messagePreview,
        mode == 'full' ? 'Did you take the morning dose?' : null,
      );
    });
  }
  // 함수이름: 다른 환자·지난 날짜·일반 채팅에는 복용 버튼을 붙이지 않는다
  // 함수역할:
  // - 다른 수신 계정·어제·내일·일반 텍스트 메시지는 복용 버튼 없이 네 건 모두 일반 채팅 알림으로 전달하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  test('다른 환자·지난 날짜·일반 채팅에는 복용 버튼을 붙이지 않는다', () async {
    final notifications = RecordingNotificationService();
    await _deliver(
      notifications,
      const UserSetting(),
      scheduleDate: '2026-11-07',
    );
    await _deliver(
      notifications,
      const UserSetting(),
      userHash: 'patient-a',
      scheduleDate: '2026-11-06',
    );
    await _deliver(
      notifications,
      const UserSetting(),
      userHash: 'patient-a',
      scheduleDate: '2026-11-08',
    );
    await _deliver(
      notifications,
      const UserSetting(),
      userHash: 'patient-a',
      scheduleDate: '2026-11-07',
      messageKind: ChatMessageKind.text,
    );
    expect(notifications.slotCheckAlerts, isEmpty);
    expect(notifications.linkedChatAlerts, hasLength(4));
  });
  // 함수이름: 채팅 알림을 끄면 복용 버튼 알림도 표시하지 않는다
  // 함수역할:
  // - 채팅 알림을 끄면 오늘의 환자 확인 요청도 복용 버튼 알림이나 일반 채팅 알림을 만들지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  test('채팅 알림을 끄면 복용 버튼 알림도 표시하지 않는다', () async {
    final notifications = RecordingNotificationService();
    await _deliver(
      notifications,
      const UserSetting(chatNotificationsEnabled: false),
      userHash: 'patient-a',
      scheduleDate: '2026-11-07',
    );
    expect(notifications.slotCheckAlerts, isEmpty);
    expect(notifications.linkedChatAlerts, isEmpty);
  });
  for (final detailMode in ['full', 'type_only']) {
    // 함수이름: enabled chat alerts are shown with detail mode $detailMode
    // 함수역할:
    // - 허용된 채팅 알림은 상세 표시 설정을 먼저 적용하고 연동·언어·메시지 종류·시간대·기록 소유자를 전달하며 0 이상 0x7FFFFFFF 이하 ID를 쓰는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    test(
      'enabled chat alerts are shown with detail mode $detailMode',
      () async {
        final notifications = RecordingNotificationService();
        await _deliver(
          notifications,
          UserSetting(language: 'en', notificationDetailMode: detailMode),
        );

        expect(notifications.showSensitiveDetails, detailMode == 'full');
        final alert = notifications.linkedChatAlerts.single;
        expect(alert.linkId, 17);
        expect(alert.language, 'en');
        expect(alert.messagePreview, 'Did you take the morning dose?');
        expect(alert.messageKind, ChatMessageKind.slotCheckRequest.wireName);
        expect(alert.slotKey, 'morning');
        expect(alert.historyUserHash, 'caregiver-a');
        expect(alert.id, inInclusiveRange(0, 0x7FFFFFFF));
      },
    );

    // 함수이름: disabled chat alerts show nothing with detail mode $detailMode
    // 함수역할:
    // - 채팅 알림이 꺼져 있으면 상세 모드와 무관하게 아무 알림도 만들지 않고 다른 알림의 민감정보 표시 설정도 건드리지 않는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    test(
      'disabled chat alerts show nothing with detail mode $detailMode',
      () async {
        final notifications = RecordingNotificationService();
        await _deliver(
          notifications,
          UserSetting(
            chatNotificationsEnabled: false,
            notificationDetailMode: detailMode,
          ),
        );

        expect(notifications.linkedChatAlerts, isEmpty);
        expect(notifications.showSensitiveDetails, isNull);
      },
    );
  }

  // Function Name: the notification ID is stable per link and message
  // Description:
  // - Repeated delivery of one link/message pair reuses its notification ID, while a different message in that link receives a different ID.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('the notification ID is stable per link and message', () async {
    final notifications = RecordingNotificationService();
    const setting = UserSetting();
    await _deliver(notifications, setting);
    await _deliver(notifications, setting);
    await _deliver(notifications, setting, messageId: 42);

    final ids = [for (final alert in notifications.linkedChatAlerts) alert.id];
    expect(ids[0], ids[1]);
    expect(ids[2], isNot(ids[0]));
  });

  // Function Name: a failed summary lookup still shows the message alert
  // Description:
  // - A failed unread-summary lookup still delivers the incoming message alert instead of silently dropping it.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('a failed summary lookup still shows the message alert', () async {
    final notifications = RecordingNotificationService();
    await _deliver(
      notifications,
      const UserSetting(),
      loadSummary: () async => throw StateError('offline'),
    );

    expect(notifications.linkedChatAlerts, hasLength(1));
  });
}
