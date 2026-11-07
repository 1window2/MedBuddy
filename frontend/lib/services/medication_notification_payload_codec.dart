// File Name: medication_notification_payload_codec.dart
// Role: Validates notification wire payloads without initializing a platform plugin.

import '../entities/caregiver_alert_context_entity.dart';
import '../entities/caregiver_notification_entity.dart';
import '../entities/medication_notification_selection_entity.dart';
import 'slot_check_notification_context.dart';

// 클래스명: MedicationNotificationPayloadCodec
// 역할: 플랫폼 알림 페이로드를 화면 이동·동작 선택 값으로 변환한다.
// 주요 책임: 일정·보호자·채팅 문맥의 형식을 검사하고 세션 관련 접두사를 식별한다.
// 속성: 동작 ID 및 caregiverPayloadPrefix (String): 플랫폼과 공유하는 문자열 상수; 인스턴스 상태 없음.
class MedicationNotificationPayloadCodec {
  // Function Name: MedicationNotificationPayloadCodec._
  // Description: Prevents instances of the stateless notification protocol utility.
  // Parameters: None.
  // Returns: A private codec instance, not exposed to callers.
  const MedicationNotificationPayloadCodec._();

  static const String markSlotTakenActionId = 'medbuddy_mark_slot_taken';
  static const String snoozeTenMinutesActionId = 'medbuddy_snooze_10_minutes';
  static const String caregiverSnoozeActionId = 'medbuddy_caregiver_snooze';
  static const String caregiverChatActionId = 'medbuddy_caregiver_chat';
  static const String caregiverPayloadPrefix = 'caregiver:';

  // Function Name: caregiverPayload
  // Description: Builds the legacy caregiver route that opens a linked patient's schedule; the caller trims the hash first where it needs to.
  // Parameters: patientHash (String): Patient hash, URI-encoded into the payload as given.
  // Returns: The payload "caregiver:<encoded patientHash>".
  static String caregiverPayload(String patientHash) =>
      '$caregiverPayloadPrefix${Uri.encodeComponent(patientHash)}';

  // Function Name: chatPayload
  // Description: Builds the route that opens one linked chat conversation.
  // Parameters: linkId (int): Patient-caregiver link ID of the conversation.
  // Returns: The payload "chat:<linkId>".
  static String chatPayload(int linkId) => 'chat:$linkId';

  // 함수이름: decode
  // 함수역할: 지원하는 알림 문맥을 해석하고 ID·날짜·태그 형식을 검사한다. 필요 시 복용은 열기만 허용하며 서명 검증 자체는 수행하지 않는다.
  // 매개변수: payload (String?): 저장된 페이로드; actionId (String?): 누른 동작; notificationId (int?): 일정 페이로드 ID를 대체할 플랫폼 ID.
  // 반환값: MedicationNotificationSelection?: 해석된 선택; 미지원·잘못된 형식이면 null.
  static MedicationNotificationSelection? decode(
    String? payload, {
    String? actionId,
    int? notificationId,
  }) {
    if (payload?.startsWith(SlotCheckNotificationContext.prefix) ?? false) {
      final request = SlotCheckNotificationContext.fromPayload(payload);
      if (request == null) return null;
      // 본문 선택은 채팅만 열고, 완료 버튼은 별도 백그라운드 처리기만 실행한다.
      return MedicationNotificationSelection(
        destination: MedicationNotificationDestination.linkedChat,
        linkId: request.linkId,
      );
    }
    if (payload?.startsWith('caregiver-v1:') ?? false) {
      final alert = CaregiverAlertContext.fromPayload(payload!);
      if (alert == null) return null;
      return MedicationNotificationSelection(
        destination: MedicationNotificationDestination.caregiverSchedule,
        patientHash: alert.patientHash,
        slotKey: alert.slotKey,
        linkId: alert.linkId,
        scheduleDate: DateTime.parse(alert.scheduleDate),
        caregiverAlert: alert,
        action: switch (actionId) {
          caregiverSnoozeActionId =>
            MedicationNotificationAction.caregiverSnooze,
          caregiverChatActionId =>
            MedicationNotificationAction.caregiverRequestCheck,
          _ => MedicationNotificationAction.open,
        },
      );
    }
    final segments = payload?.split(':') ?? const <String>[];
    if (segments.length >= 3 &&
        segments.length <= 5 &&
        segments[0] == 'schedule' &&
        caregiverNotificationSlotKeys.contains(
          segments[1].trim().toLowerCase(),
        )) {
      // The fifth segment is the app's own signature tag (see MedicationReminderActionTag).
      if (segments.length == 5 &&
          !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(segments[4])) {
        return null;
      }
      final encodedNotificationId = int.tryParse(segments[2]);
      if (encodedNotificationId == null || encodedNotificationId < 0) {
        return null;
      }
      DateTime? scheduleDate;
      if (segments.length >= 4) {
        final rawDate = segments[3];
        scheduleDate = DateTime.tryParse(rawDate);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate) ||
            scheduleDate == null ||
            scheduleDate.toIso8601String().split('T').first != rawDate) {
          return null;
        }
      }
      return MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
        slotKey: segments[1].trim().toLowerCase(),
        notificationId: notificationId ?? encodedNotificationId,
        scheduleDate: scheduleDate,
        signedPayload: segments.take(4).join(':'),
        actionTag: segments.length == 5 ? segments[4] : null,
        // 필요시 확인 알림은 복용 처리와 다시 알림을 자동 실행하지 않는다.
        action: segments[1].trim().toLowerCase() == 'as_needed'
            ? MedicationNotificationAction.open
            : switch (actionId) {
                markSlotTakenActionId =>
                  MedicationNotificationAction.markSlotTaken,
                snoozeTenMinutesActionId =>
                  MedicationNotificationAction.snoozeTenMinutes,
                _ => MedicationNotificationAction.open,
              },
      );
    }
    if (segments.length == 2 &&
        segments[0] == 'caregiver' &&
        segments[1].trim().isNotEmpty) {
      try {
        final patientHash = Uri.decodeComponent(segments[1]).trim();
        if (patientHash.isEmpty) return null;
        return MedicationNotificationSelection(
          destination: MedicationNotificationDestination.caregiverSchedule,
          patientHash: patientHash,
        );
      } on FormatException {
        return null;
      } on ArgumentError {
        return null;
      }
    }
    if (segments.length == 2 && segments[0] == 'chat') {
      final linkId = int.tryParse(segments[1]);
      if (linkId == null || linkId < 1) return null;
      return MedicationNotificationSelection(
        destination: MedicationNotificationDestination.linkedChat,
        linkId: linkId,
      );
    }
    return null;
  }

  // 함수이름: isSessionPayload
  // 함수역할: 페이로드가 현재 사용자 세션에 속하는 지원 접두사인지 검사한다. 내용 유효성까지 검증하지는 않는다.
  // 매개변수: payload (String?): 알림 페이로드.
  // 반환값: bool: 일정·보호자·채팅·복약 확인 접두사이면 true.
  static bool isSessionPayload(String? payload) =>
      payload?.startsWith(SlotCheckNotificationContext.prefix) == true ||
      payload?.startsWith('schedule:') == true ||
      payload?.startsWith('caregiver-v1:') == true ||
      payload?.startsWith(caregiverPayloadPrefix) == true ||
      payload?.startsWith('chat:') == true;
}
