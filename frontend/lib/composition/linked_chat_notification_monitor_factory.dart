// 파일명: linked_chat_notification_monitor_factory.dart
// 역할: 로컬 가족 채팅 알림 감시에 필요한 Control과 플랫폼 서비스를 조립한다.

import '../controls/link_patient_caregiver_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../services/authenticated_api_client.dart';
import '../services/linked_chat_notification_monitor_service.dart';
import '../services/linked_chat_realtime_service.dart';
import '../services/notification_service.dart';

// 클래스명: LinkedChatNotificationMonitorFactory
// 역할:
// - 채팅 알림 감시 서비스가 HTTP, WebSocket, 알림 플러그인 구현을 직접 생성하지 않게 한다.
class LinkedChatNotificationMonitorFactory {
  const LinkedChatNotificationMonitorFactory._();

  static LinkedChatNotificationMonitorService create({
    required String userHash,
    required AuthenticatedApiClient client,
    Duration linkRefreshInterval =
        LinkedChatNotificationMonitorService.defaultLinkRefreshInterval,
    bool requestPermission = true,
  }) {
    final linkControl = LinkPatientCaregiver(
      userHash: userHash,
      client: client,
    );
    final settingControl = ManageUserSetting(
      userHash: userHash,
      client: client,
      useRemotePersistence: false,
    );
    return LinkedChatNotificationMonitorService(
      currentUserHash: userHash,
      loadLinks: linkControl.requestLinkScreen,
      eventSourceFactory: (linkId) {
        return LinkedChatRealtimeService(
          linkId: linkId,
          userHash: userHash,
          authenticationClient: client,
        );
      },
      sendAlert:
          ({
            required linkId,
            required messageId,
            required messageBody,
            required messageKind,
            required slotKey,
          }) async {
            final setting = await settingControl.requestUserSetting();
            if (!setting.chatNotificationsEnabled) {
              return;
            }
            NotificationService.instance.setShowSensitiveDetails(
              setting.showNotificationDetails,
            );
            return NotificationService.instance.showLinkedChatAlert(
              id: _notificationId(linkId, messageId),
              linkId: linkId,
              language: setting.language,
              messagePreview: messageBody,
              messageKind: messageKind.wireName,
              slotKey: slotKey,
            );
          },
      permissionRequester: NotificationService.instance.requestPermission,
      featureEnabledLoader: () async {
        final setting = await settingControl.requestUserSetting();
        return setting.linkedMedicationChatLabEnabled;
      },
      linkRefreshInterval: linkRefreshInterval,
      requestPermission: requestPermission,
      onDispose: () {
        linkControl.dispose();
        settingControl.dispose();
      },
    );
  }

  // 함수명: _notificationId
  // 역할:
  // - 연동과 메시지 식별자로 Android 허용 범위 안의 안정적인 알림 ID를 만든다.
  static int _notificationId(int linkId, int messageId) {
    final source = '$linkId|$messageId';
    var hash = 0x811C9DC5;
    for (final codeUnit in source.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }
}
