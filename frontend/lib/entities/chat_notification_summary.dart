import 'dart:convert';

import 'package:cryptography/cryptography.dart';

// 기기에 메시지를 누적하지 않고 서버의 현재 미확인 상태로 알림을 교체한다.
class ChatNotificationSummary {
  final int count;
  final int latestMessageId;
  final String senderName;
  final List<String> lines;
  final bool showDetails;

  const ChatNotificationSummary({
    required this.count,
    required this.latestMessageId,
    this.senderName = '',
    this.lines = const [],
    this.showDetails = true,
  });

  static ChatNotificationSummary? parse(Object? value) {
    try {
      final data = value is String ? jsonDecode(value) : value;
      if (data is! Map ||
          data['count'] is! int ||
          data['count'] < 0 ||
          data['latest_message_id'] is! int ||
          data['latest_message_id'] < 0) {
        return null;
      }
      final lines = data['lines'];
      return ChatNotificationSummary(
        count: data['count'] as int,
        latestMessageId: data['latest_message_id'] as int,
        senderName: data['sender_name'] is String
            ? data['sender_name'] as String
            : '',
        lines: lines is List
            ? lines.whereType<String>().take(3).toList()
            : const [],
        showDetails: data['show_details'] == true,
      );
    } on FormatException {
      return null;
    }
  }

  // FCM의 tag와 동일하게 생성해 전경/백그라운드 전환에도 하나의 알림만 유지한다.
  static Future<String> groupTag(String owner, int linkId) async {
    final digest = await Sha256().hash(utf8.encode('$owner|$linkId'));
    final hex = digest.bytes
        .take(16)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'medbuddy-chat-$hex';
  }
}
