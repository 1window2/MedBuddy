// 파일명: slot_check_notification_context.dart
// 역할: 보호자 확인 요청 알림의 계정·날짜·시간대와 중복 방지 식별자를 검증한다.
import 'dart:convert';

import '../entities/medication_schedule_entity.dart';

// 클래스명: SlotCheckNotificationContext
// 역할: 확인 요청 한 건의 환자·연동·메시지·날짜·시간대를 담고 FCM 데이터와 알림 payload를 오간다.
// 속성:
// - owner (String): 요청을 받은 환자 계정.
// - linkId (int): 연동 ID.
// - messageId (int): 확인 요청 메시지 ID.
// - scheduleDate (String): 요청한 복약 날짜(yyyy-MM-dd).
// - slotKey (String): 요청한 정기 복약 시간대.
class SlotCheckNotificationContext {
  static const prefix = 'slot-check-v1:';
  static const actionId = 'medbuddy_complete_slot_check';
  final String owner;
  final int linkId;
  final int messageId;
  final String scheduleDate;
  final String slotKey;

  const SlotCheckNotificationContext._(
    this.owner,
    this.linkId,
    this.messageId,
    this.scheduleDate,
    this.slotKey,
  );

  // 함수이름: eventId
  // 함수역할: 알림 태그와 중복 방지에 쓰는 메시지 식별자를 만든다. 반환값: chat:<연동>:<메시지>.
  String get eventId => 'chat:$linkId:$messageId';

  // 함수이름: payload
  // 함수역할: 알림 버튼 처리와 본문 탭이 다시 읽을 접두어 붙은 JSON을 만든다. 반환값: 알림 payload.
  String get payload =>
      '$prefix${jsonEncode({'type': 'linked_chat_message', 'message_kind': 'slot_check_request', 'action_version': '1', 'recipient_hash': owner, 'patient_hash': owner, 'link_id': '$linkId', 'message_id': '$messageId', 'event_id': eventId, 'schedule_date': scheduleDate, 'slot_key': slotKey})}';

  // 함수이름: fromPayload
  // 함수역할: 알림 payload를 fromData와 같은 규칙으로 검증해 읽는다.
  // 매개변수: payload 알림 payload. 반환값: 요청 또는 형식이 맞지 않으면 null.
  static SlotCheckNotificationContext? fromPayload(String? payload) {
    if (payload == null || !payload.startsWith(prefix)) return null;
    try {
      final data = jsonDecode(payload.substring(prefix.length));
      return data is Map ? fromData(Map<String, dynamic>.from(data)) : null;
    } catch (_) {
      return null;
    }
  }

  // 함수이름: fromData
  // 함수역할: FCM 데이터에서 유형·버전·수신 환자·식별자·실제 날짜·정기 시간대를 모두 검증한다.
  // 매개변수: data FCM 데이터나 payload JSON. 반환값: 요청 또는 하나라도 맞지 않으면 null.
  static SlotCheckNotificationContext? fromData(Map<String, dynamic> data) {
    final owner = data['recipient_hash'];
    final day = data['schedule_date'];
    final slot = data['slot_key'];
    final link = int.tryParse('${data['link_id']}');
    final message = int.tryParse('${data['message_id']}');
    if (data['type'] != 'linked_chat_message' ||
        data['message_kind'] != 'slot_check_request' ||
        data['action_version'] != '1' ||
        owner is! String ||
        owner.isEmpty ||
        owner.trim() != owner ||
        data['patient_hash'] != owner ||
        link == null ||
        link <= 0 ||
        message == null ||
        message <= 0 ||
        data['event_id'] != 'chat:$link:$message' ||
        day is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) ||
        DateTime.tryParse(day)?.toIso8601String().substring(0, 10) != day ||
        slot is! String ||
        !medicationScheduleSlotKeys.contains(slot)) {
      return null;
    }
    return SlotCheckNotificationContext._(owner, link, message, day, slot);
  }
}
