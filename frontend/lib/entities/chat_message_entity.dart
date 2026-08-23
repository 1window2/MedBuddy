// 파일명: chat_message_entity.dart
// 역할: 환자·보호자 채팅 메시지와 읽음 상태를 표현한다.

class ChatMedicationContext {
  final int medicationId;
  final String medicationName;
  final String imageUrl;
  final String dosagePerTime;
  final List<String> scheduleSlotKeys;

  const ChatMedicationContext({
    required this.medicationId,
    required this.medicationName,
    this.imageUrl = '',
    this.dosagePerTime = '',
    this.scheduleSlotKeys = const [],
  });

  // 함수명: fromJson
  // 역할:
  // - 서버가 검증한 활성 복약정보를 채팅에서 선택 가능한 약 정보로 변환한다.
  factory ChatMedicationContext.fromJson(Map<String, dynamic> json) {
    final medicationId = ChatMessage._readInt(json['medication_id']);
    final medicationName = ChatMessage._readString(json['medication_name']);
    if (medicationId == null || medicationName.isEmpty) {
      throw const FormatException('채팅 약 정보에 필수 값이 없습니다.');
    }
    return ChatMedicationContext(
      medicationId: medicationId,
      medicationName: medicationName,
      imageUrl: ChatMessage._readString(json['image_url']),
      dosagePerTime: ChatMessage._readString(json['dosage_per_time']),
      scheduleSlotKeys: _readScheduleSlotKeys(json['schedule_slot_keys']),
    );
  }

  static List<String> _readScheduleSlotKeys(dynamic value) {
    if (value is! List) {
      return const [];
    }
    const supportedKeys = {'morning', 'lunch', 'evening', 'bedtime'};
    return value
        .map((item) => item?.toString().trim().toLowerCase() ?? '')
        .where(supportedKeys.contains)
        .toSet()
        .toList(growable: false);
  }
}

class ChatMessage {
  final int messageId;
  final int linkId;
  final String senderHash;
  final String clientMessageId;
  final String body;
  final DateTime createdAt;
  final ChatMedicationContext? medicationContext;
  final DateTime? readAt;

  const ChatMessage({
    required this.messageId,
    required this.linkId,
    required this.senderHash,
    required this.clientMessageId,
    required this.body,
    required this.createdAt,
    this.medicationContext,
    this.readAt,
  });

  // 함수명: fromJson
  // 역할:
  // - 서버 응답을 필수 필드가 검증된 채팅 메시지로 변환한다.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final messageId = _readInt(json['message_id']);
    final linkId = _readInt(json['link_id']);
    final senderHash = _readString(json['sender_hash']);
    final clientMessageId = _readString(json['client_message_id']);
    final body = _readString(json['body']);
    final createdAt = DateTime.tryParse(_readString(json['created_at']));
    if (messageId == null ||
        linkId == null ||
        senderHash.isEmpty ||
        clientMessageId.isEmpty ||
        body.isEmpty ||
        createdAt == null) {
      throw const FormatException('채팅 메시지 응답에 필수 정보가 없습니다.');
    }
    final readAtText = _readString(json['read_at']);
    final rawMedicationContext = json['medication_context'];
    return ChatMessage(
      messageId: messageId,
      linkId: linkId,
      senderHash: senderHash,
      clientMessageId: clientMessageId,
      body: body,
      createdAt: createdAt,
      medicationContext: rawMedicationContext is Map
          ? ChatMedicationContext.fromJson(
              Map<String, dynamic>.from(rawMedicationContext),
            )
          : null,
      readAt: readAtText.isEmpty ? null : DateTime.tryParse(readAtText),
    );
  }

  ChatMessage copyWith({DateTime? readAt}) {
    return ChatMessage(
      messageId: messageId,
      linkId: linkId,
      senderHash: senderHash,
      clientMessageId: clientMessageId,
      body: body,
      createdAt: createdAt,
      medicationContext: medicationContext,
      readAt: readAt ?? this.readAt,
    );
  }

  static String _readString(dynamic value) => value?.toString().trim() ?? '';

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(_readString(value));
  }
}
