// 파일명: linked_chat_notification_monitor_factory.dart
// 역할: 가족 채팅의 연동 조회, 실시간 연결과 로컬 알림 의존성을 조립한다.

import '../controls/link_patient_caregiver_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../services/authenticated_api_client.dart';
import '../services/linked_chat_notification_monitor_service.dart';
import '../services/linked_chat_realtime_service.dart';
import '../services/notification_service.dart';

// 클래스명: LinkedChatNotificationMonitorFactory
// 역할: 채팅 감시 서비스와 구체적인 HTTP·WebSocket·알림 구현을 연결한다.
// 주요 책임:
// - 실험실 기능과 채팅 알림 설정을 확인하고 연동별 이벤트 소스 및 자원 정리 콜백을 제공한다.
class LinkedChatNotificationMonitorFactory {
  // 함수이름: LinkedChatNotificationMonitorFactory._
  // 함수역할: 가족 채팅 감시 조립을 정적 create 진입점으로만 제공하도록 외부 생성을 막는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - LinkedChatNotificationMonitorFactory: 초기화된 인스턴스.
  const LinkedChatNotificationMonitorFactory._();

  // 함수이름: create
  // 함수역할: 인증 클라이언트로 연동·설정 조회를 구성하고 채팅 알림 설정을 확인하는 전송 경계를 감시 서비스에 주입한다.
  // 매개변수:
  // - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // - client (AuthenticatedApiClient): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
  // - linkRefreshInterval (Duration): 활성 채팅 연동 목록 갱신 간격
  // - requestPermission (bool): 감시 중 운영체제 권한 요청을 수행할지 여부
  // 반환값:
  // - LinkedChatNotificationMonitorService: 인증 클라이언트로 연동·설정 조회를 구성하고 채팅 알림 설정을 확인하는 전송 경계를 감시 서비스에 주입한다.
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
      eventSourceFactory: /* 함수이름: eventSourceFactory 콜백
       * 함수역할: 연결 ID와 현재 사용자 인증 클라이언트로 가족 채팅 실시간 스트림을 구성한다.
       * 매개변수:
       * - linkId (int): 조회·전송·감시 대상 연동 ID
       * 반환값:
       * - 해당 연결의 실시간 이벤트 서비스.
       */(linkId) {
        return LinkedChatRealtimeService(
          linkId: linkId,
          userHash: userHash,
          authenticationClient: client,
        );
      },
      sendAlert:
          // 함수이름: sendAlert 콜백
          // 함수역할: 채팅 알림 설정을 확인하고 메시지와 연결 ID에서 계산한 알림 ID로 로컬 알림을 표시한다.
          // 매개변수:
          // - linkId (int): 조회·전송·감시 대상 연동 ID
          // - messageId (int): 서버가 부여한 채팅 메시지 ID
          // - messageBody (String): 전송하거나 표시할 메시지·알림 본문
          // - messageKind (ChatMessageKind): 일반·복약·약국 맥락 메시지 유형
          // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
          // 반환값:
          // - 알림 비활성화 확인 또는 표시가 완료되는 Future.
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
      featureEnabledLoader: /* 함수이름: featureEnabledLoader 콜백
       * 함수역할: 사용자 설정에서 가족 복약 채팅 실험 기능의 활성 여부를 읽는다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 실험 기능 활성 여부를 완료하는 Future.
       */() async {
        final setting = await settingControl.requestUserSetting();
        return setting.linkedMedicationChatLabEnabled;
      },
      linkRefreshInterval: linkRefreshInterval,
      requestPermission: requestPermission,
      onDispose: /* 함수이름: onDispose 콜백
       * 함수역할: 팩토리에서 생성한 환자 연결 제어기와 사용자 설정 제어기를 해제한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 없음.
       */() {
        linkControl.dispose();
        settingControl.dispose();
      },
    );
  }

  // 함수이름: _notificationId
  // 함수역할: 연동과 메시지 식별자로 Android 허용 범위 안의 안정적인 알림 ID를 만든다.
  // 매개변수:
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // - messageId (int): 서버가 부여한 채팅 메시지 ID
  // 반환값:
  // - int: 연동과 메시지 식별자로 Android 허용 범위 안의 안정적인 알림 ID를 만든다.
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
