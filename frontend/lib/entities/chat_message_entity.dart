// 파일명: chat_message_entity.dart
// 역할: 환자·보호자 채팅 메시지와 읽음 상태를 표현한다.

enum ChatMessageKind {
  text,
  slotCheckRequest,
  slotCompletion,
  medicationShortage,
  medicationDiscomfort,
  pharmacyShare,
  pharmacyPhoneVerified;

  String get wireName => switch (this) {
    ChatMessageKind.text => 'text',
    ChatMessageKind.slotCheckRequest => 'slot_check_request',
    ChatMessageKind.slotCompletion => 'slot_completion',
    ChatMessageKind.medicationShortage => 'medication_shortage',
    ChatMessageKind.medicationDiscomfort => 'medication_discomfort',
    ChatMessageKind.pharmacyShare => 'pharmacy_share',
    ChatMessageKind.pharmacyPhoneVerified => 'pharmacy_phone_verified',
  };

  // 함수명: fromWireName
  // 역할:
  // - 서버에 새 유형이 추가돼도 기존 앱이 일반 메시지로 안전하게 표시하게 한다.
  static ChatMessageKind fromWireName(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return ChatMessageKind.values.firstWhere(
      (kind) => kind.wireName == normalized,
      orElse: () => ChatMessageKind.text,
    );
  }
}

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

// 클래스명: ChatScheduleContext
// 역할: 채팅에 첨부된 한 복약 시간대의 진행률과 약 목록을 표현한다.
class ChatScheduleContext {
  final String slotKey;
  final String alarmTime;
  final bool alarmEnabled;
  final int completedCount;
  final int totalCount;
  final bool canRequestCheck;
  final List<ChatMedicationContext> medications;

  const ChatScheduleContext({
    required this.slotKey,
    required this.alarmTime,
    required this.alarmEnabled,
    required this.completedCount,
    required this.totalCount,
    this.canRequestCheck = false,
    required this.medications,
  });

  factory ChatScheduleContext.fromJson(Map<String, dynamic> json) {
    final slotKey = ChatMessage._readString(json['slot_key']).toLowerCase();
    const supportedKeys = {'morning', 'lunch', 'evening', 'bedtime'};
    if (!supportedKeys.contains(slotKey)) {
      throw const FormatException('채팅 복약 시간대 정보가 올바르지 않습니다.');
    }
    final rawMedications = json['medications'];
    return ChatScheduleContext(
      slotKey: slotKey,
      alarmTime: ChatMessage._readString(json['alarm_time']),
      alarmEnabled: json['alarm_enabled'] == true,
      completedCount: ChatMessage._readInt(json['completed_count']) ?? 0,
      totalCount: ChatMessage._readInt(json['total_count']) ?? 0,
      canRequestCheck: json['can_request_check'] == true,
      medications: rawMedications is List
          ? rawMedications
                .whereType<Map>()
                .map(
                  (item) => ChatMedicationContext.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

// 클래스명: ChatPharmacyContext
// 역할: 채팅으로 공유한 약국의 연락처와 길찾기 좌표를 보존한다.
class ChatPharmacyContext {
  final String pharmacyId;
  final String name;
  final String address;
  final String telephone;
  final String todayHours;
  final double latitude;
  final double longitude;
  final DateTime? sourceUpdatedAt;

  const ChatPharmacyContext({
    required this.pharmacyId,
    required this.name,
    required this.address,
    required this.telephone,
    this.todayHours = '',
    required this.latitude,
    required this.longitude,
    this.sourceUpdatedAt,
  });

  factory ChatPharmacyContext.fromJson(Map<String, dynamic> json) {
    final pharmacyId = ChatMessage._readString(json['pharmacy_id']);
    final name = ChatMessage._readString(json['name']);
    if (pharmacyId.isEmpty || name.isEmpty) {
      throw const FormatException('채팅 약국 정보에 필수 값이 없습니다.');
    }
    return ChatPharmacyContext(
      pharmacyId: pharmacyId,
      name: name,
      address: ChatMessage._readString(json['address']),
      telephone: ChatMessage._readString(json['telephone']),
      todayHours: ChatMessage._readString(json['today_hours']),
      latitude: ChatMessage._readDouble(json['latitude']),
      longitude: ChatMessage._readDouble(json['longitude']),
      sourceUpdatedAt: DateTime.tryParse(
        ChatMessage._readString(json['source_updated_at']),
      ),
    );
  }
}

class ChatMessage {
  final int messageId;
  final int linkId;
  final String senderHash;
  final String clientMessageId;
  final String body;
  final DateTime createdAt;
  final ChatMessageKind messageKind;
  final ChatMedicationContext? medicationContext;
  final List<ChatMedicationContext> medicationContexts;
  final ChatScheduleContext? scheduleContext;
  final ChatPharmacyContext? pharmacyContext;
  final int? remainingDays;
  final DateTime? courseEndDate;
  final bool showSafetyGuidance;
  final DateTime? readAt;

  const ChatMessage({
    required this.messageId,
    required this.linkId,
    required this.senderHash,
    required this.clientMessageId,
    required this.body,
    required this.createdAt,
    this.messageKind = ChatMessageKind.text,
    this.medicationContext,
    this.medicationContexts = const [],
    this.scheduleContext,
    this.pharmacyContext,
    this.remainingDays,
    this.courseEndDate,
    this.showSafetyGuidance = false,
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
    final rawMedicationContexts = json['medication_contexts'];
    final rawContext = json['context'];
    final context = rawContext is Map
        ? Map<String, dynamic>.from(rawContext)
        : const <String, dynamic>{};
    final rawScheduleContext = context['schedule_context'];
    final rawPharmacyContext = context['pharmacy_context'];
    final singleMedicationContext = rawMedicationContext is Map
        ? ChatMedicationContext.fromJson(
            Map<String, dynamic>.from(rawMedicationContext),
          )
        : null;
    final parsedMedicationContexts = _readMedicationContexts(
      rawMedicationContexts ?? context['medication_contexts'],
    );
    final medicationContexts = parsedMedicationContexts.isNotEmpty
        ? parsedMedicationContexts
        : singleMedicationContext == null
        ? const <ChatMedicationContext>[]
        : <ChatMedicationContext>[singleMedicationContext];
    return ChatMessage(
      messageId: messageId,
      linkId: linkId,
      senderHash: senderHash,
      clientMessageId: clientMessageId,
      body: body,
      createdAt: createdAt,
      messageKind: ChatMessageKind.fromWireName(json['message_kind']),
      medicationContext: medicationContexts.isEmpty
          ? null
          : medicationContexts.first,
      medicationContexts: medicationContexts,
      scheduleContext: rawScheduleContext is Map
          ? ChatScheduleContext.fromJson(
              Map<String, dynamic>.from(rawScheduleContext),
            )
          : null,
      pharmacyContext: rawPharmacyContext is Map
          ? ChatPharmacyContext.fromJson(
              Map<String, dynamic>.from(rawPharmacyContext),
            )
          : null,
      remainingDays: _readInt(context['remaining_days']),
      courseEndDate: DateTime.tryParse(_readString(context['course_end_date'])),
      showSafetyGuidance: context['show_safety_guidance'] == true,
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
      messageKind: messageKind,
      medicationContext: medicationContext,
      medicationContexts: medicationContexts,
      scheduleContext: scheduleContext,
      pharmacyContext: pharmacyContext,
      remainingDays: remainingDays,
      courseEndDate: courseEndDate,
      showSafetyGuidance: showSafetyGuidance,
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

  static double _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(_readString(value)) ?? 0;
  }

  // 함수명: attachedMedicationContexts
  // 역할: 새 다중 약 응답과 이전 단일 약 응답을 같은 목록 형태로 제공한다.
  List<ChatMedicationContext> get attachedMedicationContexts {
    if (medicationContexts.isNotEmpty) {
      return medicationContexts;
    }
    final singleContext = medicationContext;
    return singleContext == null ? const [] : [singleContext];
  }

  static List<ChatMedicationContext> _readMedicationContexts(dynamic value) {
    if (value is! List) {
      return const [];
    }
    final contextsById = <int, ChatMedicationContext>{};
    for (final item in value.whereType<Map>()) {
      final context = ChatMedicationContext.fromJson(
        Map<String, dynamic>.from(item),
      );
      contextsById.putIfAbsent(context.medicationId, () => context);
    }
    return contextsById.values.toList(growable: false);
  }
}
