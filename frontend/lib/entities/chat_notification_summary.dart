// 파일명: chat_notification_summary.dart
// 역할: 서버의 미확인 채팅 요약과 계정별 알림 그룹 키를 표현한다.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

// 기기에 메시지를 누적하지 않고 서버의 현재 미확인 상태로 알림을 교체한다.
// 클래스명: ChatNotificationSummary
// 역할: 기기에 누적하지 않고 서버 기준 채팅 알림 내용을 전달한다.
// 주요 책임: 미확인 건수·최신 메시지·개인정보 표시 여부를 보존하고 알림 그룹을 식별한다.
// 속성: count/latestMessageId (int): 건수와 최신 ID; senderName (String), lines (List<String>): 표시 내용; showDetails (bool): 상세 표시 여부.
class ChatNotificationSummary {
  final int count;
  final int latestMessageId;
  final String senderName;
  final List<String> lines;
  final bool showDetails;

  // 함수이름: ChatNotificationSummary
  // 함수역할: 조회한 요약 상태를 보관한다. 직접 생성 시 값 검증이나 목록 복사는 하지 않는다.
  // 매개변수: count/latestMessageId (int): 건수·최신 ID; senderName (String): 발신자; lines (List<String>): 요약 행; showDetails (bool): 상세 허용 여부.
  // 반환값: 요약 인스턴스. 기본 표시 내용은 비어 있고 상세 표시는 허용한다.
  const ChatNotificationSummary({
    required this.count,
    required this.latestMessageId,
    this.senderName = '',
    this.lines = const [],
    this.showDetails = true,
  });

  // 함수이름: parse
  // 함수역할: JSON 문자열 또는 맵에서 음수가 아닌 건수·메시지 ID를 검증하고 문자열 요약을 최대 세 줄 추린다.
  // 매개변수: value (Object?): 서버 요약 JSON 또는 맵.
  // 반환값: 유효한 요약 또는 잘못된 JSON·필수 필드 형식이면 null. show_details는 명시적 true만 허용한다.
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
  // 함수이름: groupTag
  // 함수역할: 계정과 연동 ID를 SHA-256으로 묶어 FCM과 동일한 대화별 알림 태그를 만든다.
  // 매개변수: owner (String): 계정; linkId (int): 대화 연동 ID.
  // 반환값: 해시 앞 16바이트를 쓴 medbuddy-chat- 접두사 태그 Future.
  static Future<String> groupTag(String owner, int linkId) async {
    final digest = await Sha256().hash(utf8.encode('$owner|$linkId'));
    final hex = digest.bytes
        .take(16)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'medbuddy-chat-$hex';
  }
}
