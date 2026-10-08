// File Name: linked_chat_notification_monitor_factory_test.dart
// Role: Verifies the chat-notification gate the monitor factory wires in: the chat switch and
//   the notification-detail setting are read right before each alert.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/composition/linked_chat_notification_monitor_factory.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

import 'support/fake_notification_service.dart';

// Function Name: _deliver
// Description: Sends one synthetic chat alert through the gate with the given setting.
// Parameters: notifications - recording fake; setting - setting the gate will read;
//   messageId - message the alert is for.
// Returns: Completion of the gate.
Future<void> _deliver(
  RecordingNotificationService notifications,
  UserSetting setting, {
  int messageId = 41,
}) {
  return deliverLinkedChatAlert(
    loadSetting: () async => setting,
    notifications: notifications,
    userHash: 'caregiver-a',
    linkId: 17,
    messageId: messageId,
    messageBody: 'Did you take the morning dose?',
    messageKind: ChatMessageKind.slotCheckRequest,
    slotKey: 'morning',
  );
}

// Function Name: main
// Description: Registers the gate tests; no platform notification plugin is used.
// Parameters: None. Returns: None.
void main() {
  for (final detailMode in ['full', 'type_only']) {
    // Enabled: the alert is shown and the detail setting is applied first.
    test('enabled chat alerts are shown with detail mode $detailMode', () async {
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
    });

    // Disabled: nothing is shown and the privacy flag of other alerts is left alone.
    test('disabled chat alerts show nothing with detail mode $detailMode', () async {
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
    });
  }

  // One message keeps one notification ID (a repeated event replaces, not stacks); another
  // message of the same link gets another ID.
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
}
