// 파일명: linked_chat_notification_monitor_factory.dart
// 역할: 가족 채팅의 연동 조회, 실시간 연결과 로컬 알림 의존성을 조립한다.

import '../controls/link_patient_caregiver_control.dart';
import '../controls/manage_linked_chat_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../entities/chat_message_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/authenticated_api_client.dart';
import '../services/linked_chat_notification_monitor_service.dart';
import '../services/linked_chat_realtime_service.dart';
import '../services/notification_service.dart';
import '../services/dose_sync_service.dart';
import '../services/slot_check_notification_context.dart';

// 함수이름: deliverLinkedChatAlert
// 함수역할: 최신 사용자 설정을 읽어 채팅 알림이 꺼져 있으면 아무것도 표시하지 않고, 켜져 있으면 알림 상세 표시 설정을 적용한 뒤 연동·메시지에서 계산한 알림 ID로 로컬 알림을 표시한다.
// 매개변수:
// - loadSetting (Future<UserSetting> Function()): 알림 직전의 사용자 설정을 읽는 함수
// - notifications (NotificationService): 로컬 알림 표시 경계
// - userHash (String): 알림함에 기록할 수신 계정 해시
// - linkId (int): 조회·전송·감시 대상 연동 ID
// - messageId (int): 서버가 부여한 채팅 메시지 ID
// - messageBody (String): 전송하거나 표시할 메시지·알림 본문
// - messageKind (ChatMessageKind): 일반·복약·약국 맥락 메시지 유형
// - slotKey (String?): morning·lunch·evening·bedtime 복약 시간대 키
// - slotCheck (SlotCheckNotificationContext?): 보호자의 확인 요청이면 복용 완료 버튼에 쓸 검증한 요청
// - clock (DateTime Function()?): 요청이 오늘 것인지 판단할 시계. 없으면 현재 시각
// - loadSummary (Future<ChatNotificationSummary?> Function()?): 대화별 미확인 요약을 읽는 함수
// 반환값:
// - Future<void>: 알림 비활성화 확인 또는 표시가 완료되는 Future.
Future<void> deliverLinkedChatAlert({
  required Future<UserSetting> Function() loadSetting,
  required NotificationService notifications,
  required String userHash,
  required int linkId,
  required int messageId,
  required String messageBody,
  required ChatMessageKind messageKind,
  required String? slotKey,
  SlotCheckNotificationContext? slotCheck,
  DateTime Function()? clock,
  Future<ChatNotificationSummary?> Function()? loadSummary,
}) async {
  final setting = await loadSetting();
  if (!setting.chatNotificationsEnabled) {
    return;
  }
  notifications.setShowSensitiveDetails(setting.showNotificationDetails);
  // 요약 조회가 실패해도 이번 메시지 알림은 요약 없이 보여 준다.
  ChatNotificationSummary? summary;
  try {
    summary = await loadSummary?.call();
  } catch (_) {}
  if (summary?.count == 0) return;
  if (slotCheck != null &&
      slotCheck.owner == userHash &&
      slotCheck.linkId == linkId &&
      slotCheck.messageId == messageId &&
      messageKind == ChatMessageKind.slotCheckRequest &&
      slotCheck.scheduleDate == doseScheduleDay((clock ?? DateTime.now)())) {
    return notifications.showSlotCheckAlert(
      request: slotCheck,
      id: LinkedChatNotificationMonitorFactory._notificationId(
        linkId,
        messageId,
      ),
      language: setting.language,
      messagePreview:
          setting.showNotificationDetails && (summary?.showDetails ?? true)
          ? messageBody
          : null,
      recordHistory: true,
    );
  }
  return notifications.showLinkedChatAlert(
    historyUserHash: userHash,
    id: LinkedChatNotificationMonitorFactory._notificationId(linkId, messageId),
    linkId: linkId,
    language: setting.language,
    messagePreview: messageBody,
    messageKind: messageKind.wireName,
    slotKey: slotKey,
    summary: summary,
  );
}

// 클래스명: LinkedChatNotificationMonitorFactory
// 역할: 채팅 감시 서비스에 HTTP·WebSocket·알림 구현을 연결한다.
// 주요 책임: 알림 설정을 확인하고 연동별 이벤트 소스 및 생성한 제어기의 정리를 제공한다.
// 속성: 인스턴스 상태 없음; create가 주입받은 인증 클라이언트를 빌려 사용한다.
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
    final chatControl = ManageLinkedChat(userHash: userHash, client: client);
    return LinkedChatNotificationMonitorService(
      currentUserHash: userHash,
      loadLinks: linkControl.requestLinkScreen,
      eventSourceFactory: /* 함수이름: eventSourceFactory 콜백
       * 함수역할: 연결 ID와 현재 사용자 인증 클라이언트로 가족 채팅 실시간 스트림을 구성한다.
       * 매개변수:
       * - linkId (int): 조회·전송·감시 대상 연동 ID
       * 반환값:
       * - 해당 연결의 실시간 이벤트 서비스.
       */ (linkId) {
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
            slotCheck,
          }) => deliverLinkedChatAlert(
            loadSetting: settingControl.requestUserSetting,
            notifications: NotificationService.instance,
            userHash: userHash,
            linkId: linkId,
            messageId: messageId,
            messageBody: messageBody,
            messageKind: messageKind,
            slotKey: slotKey,
            slotCheck: slotCheck,
            loadSummary: () =>
                chatControl.requestNotificationSummary(linkId: linkId),
          ),
      permissionRequester: NotificationService.instance.requestPermission,
      linkRefreshInterval: linkRefreshInterval,
      requestPermission: requestPermission,
      onDispose: /* 함수이름: onDispose 콜백
       * 함수역할: 팩토리에서 생성한 환자 연결 제어기와 사용자 설정 제어기를 해제한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 없음.
       */ () {
        linkControl.dispose();
        settingControl.dispose();
        chatControl.dispose();
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
