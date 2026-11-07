// 역할: 보호자 확인 요청 알림의 계정·날짜·시간대와 중복 방지 식별자를 검증한다.
import 'dart:convert';

import '../entities/medication_schedule_entity.dart';

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

  String get eventId => 'chat:$linkId:$messageId';
  String get payload =>
      '$prefix${jsonEncode({'type': 'linked_chat_message', 'message_kind': 'slot_check_request', 'action_version': '1', 'recipient_hash': owner, 'patient_hash': owner, 'link_id': '$linkId', 'message_id': '$messageId', 'event_id': eventId, 'schedule_date': scheduleDate, 'slot_key': slotKey})}';

  static SlotCheckNotificationContext? fromPayload(String? payload) {
    if (payload == null || !payload.startsWith(prefix)) return null;
    try {
      final data = jsonDecode(payload.substring(prefix.length));
      return data is Map ? fromData(Map<String, dynamic>.from(data)) : null;
    } catch (_) {
      return null;
    }
  }

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
