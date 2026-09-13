// 파일명: notification_inbox_entity.dart
// 역할: 알림함 항목과 분류, 읽음 상태를 표현한다.

// 열거형: NotificationInboxCategory
// 역할: 복약 관련 알림과 가족 채팅 알림을 구분한다.
enum NotificationInboxCategory { medication, chat }

// 클래스명: NotificationInboxEntry
// 역할: 계정별 알림 내역의 표시 내용과 기존 알림 이동 payload를 보관한다.
class NotificationInboxEntry {
  final String id;
  final String title;
  final String body;
  final String payload;
  final NotificationInboxCategory category;
  final DateTime occurredAt;
  final bool isRead;

  // 함수이름: NotificationInboxEntry
  // 함수역할: 알림 하나를 생성한다. 매개변수: 식별자·표시 내용·분류·시각·읽음 상태. 반환값: 항목.
  const NotificationInboxEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    required this.category,
    required this.occurredAt,
    this.isRead = false,
  });

  // 함수이름: fromJson
  // 함수역할: 저장된 알림을 복원한다. 매개변수: json, 별도 보관한 읽음 상태. 반환값: 항목 또는 형식 오류.
  factory NotificationInboxEntry.fromJson(
    Map<String, dynamic> json, {
    bool isRead = false,
  }) {
    return NotificationInboxEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      payload: json['payload'] as String,
      category: NotificationInboxCategory.values.byName(
        json['category'] as String,
      ),
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      isRead: isRead,
    );
  }

  // 함수이름: toJson
  // 함수역할: 읽음 상태와 별도로 알림 원본을 직렬화한다. 매개변수: 없음. 반환값: 저장용 맵.
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'payload': payload,
    'category': category.name,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
  };
}
