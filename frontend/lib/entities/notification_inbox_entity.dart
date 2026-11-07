// 파일명: notification_inbox_entity.dart
// 역할: 알림함 항목과 분류, 읽음 상태를 표현한다.

// 클래스명: NotificationInboxCategory
// 역할: 알림함 항목을 복약 관련 알림과 가족 대화 알림으로 구분한다.
// 주요 책임: 목록 필터와 알림 목적지별 표시 처리를 위한 분류 값을 제공한다.
// 속성: medication: 복약 관련 알림; chat: 가족 대화 알림.
enum NotificationInboxCategory { medication, chat }

// 클래스명: NotificationInboxEntry
// 역할: 계정별 알림의 원문 표시 내용과 이동 payload를 보관한다.
// 주요 책임: 저장 원본과 별도로 전달받는 읽음 상태를 합쳐 알림함 항목을 표현한다.
// 속성: id/title/body/payload: 식별·내용·이동 정보; category: 분류; occurredAt: 발생 시각; isRead: 별도 관리되는 읽음 상태.
class NotificationInboxEntry {
  final String id;
  final String title;
  final String body;
  final String payload;
  final NotificationInboxCategory category;
  final DateTime occurredAt;
  final bool isRead;

  // 함수이름: NotificationInboxEntry
  // 함수역할: 알림 표시 내용과 이동 페이로드를 발생 시각·읽음 상태와 함께 보관한다.
  // 매개변수: id/title/body/payload (String): 중복 식별자·제목·본문·이동 정보; category (NotificationInboxCategory): 분류; occurredAt (DateTime): 발생·예약 시각; isRead (bool): 읽음 상태.
  // 반환값: NotificationInboxEntry: 제공된 알림 값.
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
  // 함수역할: 저장 필드를 엄격한 타입으로 읽고 별도 관리한 읽음 상태를 적용한다.
  // 매개변수: json (Map<String, dynamic>): 저장 알림; isRead (bool): 별도 읽음 표식.
  // 반환값: NotificationInboxEntry: 복원 결과; 잘못된 타입·분류·날짜는 오류를 던진다.
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
