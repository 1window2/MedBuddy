// 파일명: chat_message_entity.dart
// 역할: 환자·보호자 채팅 메시지와 읽음 상태를 표현한다.

// 클래스명: ChatMessageKind
// 역할: 일반 대화와 복약·약국 맥락 메시지의 유형을 구분한다.
// 주요 책임:
// - 서버 전송 이름을 매핑하고 알 수 없는 새 유형은 일반 대화로 표시한다.
// 비고:
// - 파일명: chat_message_entity.dart
enum ChatMessageKind {
  text,
  slotCheckRequest,
  slotCompletion,
  medicationShortage,
  medicationDiscomfort,
  pharmacyShare,
  pharmacyPhoneVerified;

  // 함수이름: wireName
  // 함수역할: 현재 메시지 유형을 REST·WebSocket에서 공유하는 snake_case 전송값으로 변환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 현재 메시지 유형을 REST·WebSocket에서 공유하는 snake_case 전송값으로 변환한다.
  String get wireName => switch (this) {
    ChatMessageKind.text => 'text',
    ChatMessageKind.slotCheckRequest => 'slot_check_request',
    ChatMessageKind.slotCompletion => 'slot_completion',
    ChatMessageKind.medicationShortage => 'medication_shortage',
    ChatMessageKind.medicationDiscomfort => 'medication_discomfort',
    ChatMessageKind.pharmacyShare => 'pharmacy_share',
    ChatMessageKind.pharmacyPhoneVerified => 'pharmacy_phone_verified',
  };

  // 함수이름: fromWireName
  // 함수역할: 서버에 새 유형이 추가돼도 기존 앱이 일반 메시지로 안전하게 표시하게 한다.
  // 매개변수:
  // - value (dynamic): 채팅 메시지 종류로 해석할 서버 전송 값
  // 반환값:
  // - ChatMessageKind: 서버에 새 유형이 추가돼도 기존 앱이 일반 메시지로 안전하게 표시하게 한다.
  static ChatMessageKind fromWireName(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return ChatMessageKind.values.firstWhere(
      // 함수이름: firstWhere 콜백
      // 함수역할: 정규화된 전송 값과 일치하는 채팅 메시지 종류를 찾는다.
      // 매개변수:
      // - kind (ChatMessageKind): 해석 중인 채팅 메시지 종류
      // 반환값:
      // - 전송 이름이 일치하면 true.
      (kind) => kind.wireName == normalized,
      orElse: /* 함수이름: orElse 콜백
       * 함수역할: 알 수 없는 메시지 종류를 일반 텍스트로 해석한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 일반 텍스트 메시지 종류.
       */() => ChatMessageKind.text,
    );
  }
}

// 클래스명: ChatMedicationContext
// 역할: 채팅에 첨부할 활성 복약 항목의 식별·표시 정보를 보관한다.
// 주요 책임:
// - 약 ID·이름을 검증하고 이미지·용량·지원 시간대를 카드에 전달한다.
// 속성:
// - medicationId (int): 대상 저장 복약정보의 식별자
// - medicationName (String): 화면과 저장에 사용할 약 이름
// - imageUrl (String): 약 상세·후보에 포함된 원격 이미지 주소
// - dosagePerTime (String): 단위를 포함한 1회 복용량
// - scheduleSlotKeys (List<String>): 명시적으로 선택한 복약 시간대 키 목록
class ChatMedicationContext {
  final int medicationId;
  final String medicationName;
  final String imageUrl;
  final String dosagePerTime;
  final List<String> scheduleSlotKeys;

  // 함수이름: ChatMedicationContext
  // 함수역할: 채팅 카드의 약 ID·표시명·이미지·1회 용량과 연결 시간대를 함께 보존한다.
  // 매개변수:
  // - medicationId (int): 대상 저장 복약정보의 식별자
  // - medicationName (String): 화면과 저장에 사용할 약 이름
  // - imageUrl (String): 약 상세·후보에 포함된 원격 이미지 주소
  // - dosagePerTime (String): 단위를 포함한 1회 복용량
  // - scheduleSlotKeys (List<String>): 명시적으로 선택한 복약 시간대 키 목록
  // 반환값:
  // - ChatMedicationContext: 초기화된 인스턴스.
  const ChatMedicationContext({
    required this.medicationId,
    required this.medicationName,
    this.imageUrl = '',
    this.dosagePerTime = '',
    this.scheduleSlotKeys = const [],
  });

  // 함수이름: ChatMedicationContext.fromJson
  // 함수역할: 서버가 검증한 활성 복약정보를 채팅에서 선택 가능한 약 정보로 변환한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 해당 모델의 서버 응답 또는 저장 JSON 객체
  // 반환값:
  // - ChatMedicationContext: 필드 검증과 기본값 처리를 거쳐 복원한 레코드.
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

  // 함수이름: _readScheduleSlotKeys
  // 함수역할: 시간대 배열을 정규화하고 아침·점심·저녁·취침 전 키만 중복 없이 남긴다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - List<String>: 시간대 배열을 정규화하고 아침·점심·저녁·취침 전 키만 중복 없이 남긴다.
  static List<String> _readScheduleSlotKeys(dynamic value) {
    if (value is! List) {
      return const [];
    }
    const supportedKeys = {'morning', 'lunch', 'evening', 'bedtime'};
    return value
        .map(/* 함수이름: map 콜백
         * 함수역할: 시간대 항목을 공백 없는 소문자 문자열로 정규화한다.
         * 매개변수:
         * - item (dynamic): 현재 변환·검사 중인 응답 또는 목록 항목
         * 반환값:
         * - 정규화된 시간대 키 또는 빈 문자열.
         */(item) => item?.toString().trim().toLowerCase() ?? '')
        .where(supportedKeys.contains)
        .toSet()
        .toList(growable: false);
  }
}

// 클래스명: ChatScheduleContext
// 역할: 채팅에 첨부된 한 복약 시간대의 진행률과 약 목록을 표현한다.
// 주요 책임:
// - 지원 시간대를 검증하고 알림 시각·완료 개수·확인 요청 가능 여부를 보존한다.
// 속성:
// - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
// - alarmTime (String): 시간대 알림의 표시용 시각
// - alarmEnabled (bool): 해당 시간대 알림 활성 여부
// - completedCount (int): 공유 시간대에서 완료된 약 항목 수
// - totalCount (int): 진행률 또는 집계의 전체 대상 수
// - canRequestCheck (bool): 해당 시간대의 복약 확인 요청 가능 여부
// - medications (List<ChatMedicationContext>): 공유 복약 시간대에 포함된 약 문맥 목록
class ChatScheduleContext {
  final String slotKey;
  final String alarmTime;
  final bool alarmEnabled;
  final int completedCount;
  final int totalCount;
  final bool canRequestCheck;
  final List<ChatMedicationContext> medications;

  // 함수이름: ChatScheduleContext
  // 함수역할: 한 시간대의 알림 시각, 복약 진행률, 확인 요청 가능 여부와 관련 약 목록을 묶는다.
  // 매개변수:
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // - alarmTime (String): 시간대 알림의 표시용 시각
  // - alarmEnabled (bool): 해당 시간대 알림 활성 여부
  // - completedCount (int): 공유 시간대에서 완료된 약 항목 수
  // - totalCount (int): 진행률 또는 집계의 전체 대상 수
  // - canRequestCheck (bool): 해당 시간대의 복약 확인 요청 가능 여부
  // - medications (List<ChatMedicationContext>): 공유 복약 시간대에 포함된 약 문맥 목록
  // 반환값:
  // - ChatScheduleContext: 초기화된 인스턴스.
  const ChatScheduleContext({
    required this.slotKey,
    required this.alarmTime,
    required this.alarmEnabled,
    required this.completedCount,
    required this.totalCount,
    this.canRequestCheck = false,
    required this.medications,
  });

  // 함수이름: ChatScheduleContext.fromJson
  // 함수역할: 지원되는 시간대 키를 요구하고 완료 수·알림 설정과 첨부 약 목록을 채팅 카드 정보로 변환한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 해당 모델의 서버 응답 또는 저장 JSON 객체
  // 반환값:
  // - ChatScheduleContext: 필드 검증과 기본값 처리를 거쳐 복원한 레코드.
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
                  // 함수이름: map 콜백
                  // 함수역할: 공유된 약 응답을 채팅 약 문맥 모델로 복원한다.
                  // 매개변수:
                  // - item (Map): 현재 변환·검사 중인 응답 또는 목록 항목
                  // 반환값:
                  // - 공유 약의 채팅 문맥.
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
// 주요 책임:
// - 필수 약국 ID·이름을 검증하고 영업시간과 출처 갱신 시각을 함께 전달한다.
// 속성:
// - pharmacyId (String): 공공데이터 또는 서버의 약국 식별자
// - name (String): 표시하거나 길찾기에 사용할 약국 이름
// - address (String): 복사하거나 표시할 약국 주소
// - telephone (String): 약국 전화번호 원문
// - todayHours (String): 공유 시점의 약국 영업시간 표시문
// - latitude (double): WGS84 위도(도 단위)
// - longitude (double): WGS84 경도(도 단위)
// - sourceUpdatedAt (DateTime?): 원본 약국 자료의 갱신 시각
class ChatPharmacyContext {
  final String pharmacyId;
  final String name;
  final String address;
  final String telephone;
  final String todayHours;
  final double latitude;
  final double longitude;
  final DateTime? sourceUpdatedAt;

  // 함수이름: ChatPharmacyContext
  // 함수역할: 공유 약국의 주소·전화·좌표·영업시간과 원본 갱신 시각을 메시지 맥락으로 보존한다.
  // 매개변수:
  // - pharmacyId (String): 공공데이터 또는 서버의 약국 식별자
  // - name (String): 표시하거나 길찾기에 사용할 약국 이름
  // - address (String): 복사하거나 표시할 약국 주소
  // - telephone (String): 약국 전화번호 원문
  // - todayHours (String): 공유 시점의 약국 영업시간 표시문
  // - latitude (double): WGS84 위도(도 단위)
  // - longitude (double): WGS84 경도(도 단위)
  // - sourceUpdatedAt (DateTime?): 원본 약국 자료의 갱신 시각
  // 반환값:
  // - ChatPharmacyContext: 초기화된 인스턴스.
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

  // 함수이름: ChatPharmacyContext.fromJson
  // 함수역할: 약국 ID와 이름을 필수로 검증하고 연락처·좌표·갱신 시각을 공유 카드 정보로 변환한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 해당 모델의 서버 응답 또는 저장 JSON 객체
  // 반환값:
  // - ChatPharmacyContext: 필드 검증과 기본값 처리를 거쳐 복원한 레코드.
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

// 클래스명: ChatDeletionScope
// 역할: 메시지를 본인에게만 숨길지 모든 참여자에게 삭제할지 구분한다.
// 주요 책임:
// - 삭제 요청에 서버가 검증할 개인·공유 범위를 명시한다.
enum ChatDeletionScope { me, everyone }

// 클래스명: ChatMessage
// 역할: 가족 채팅의 본문, 작성자, 읽음·삭제 상태와 복약·약국 맥락을 보존한다.
// 주요 책임:
// - 응답 필수값을 검증하고 구형 단일 약 첨부를 지원하며 숨김·공유 삭제 시 민감한 본문과 맥락을 비운다.
// 속성:
// - messageId (int): 서버가 부여한 채팅 메시지 ID
// - linkId (int): 조회·전송·감시 대상 연동 ID
// - senderHash (String): 메시지를 작성한 참여자 해시
// - clientMessageId (String): 전송 재시도 중복 방지용 클라이언트 메시지 ID
// - body (String): 전송하거나 표시할 메시지·알림 본문
// - createdAt (DateTime): 메시지 작성 시각
// - messageKind (ChatMessageKind): 일반·복약·약국 맥락 메시지 유형
// - medicationContext (ChatMedicationContext?): 구형 단일 약 첨부 맥락
// - medicationContexts (List<ChatMedicationContext>): 메시지에 첨부한 여러 약의 맥락
// - scheduleContext (ChatScheduleContext?): 메시지에 첨부한 시간대별 복약 진행 정보
// - pharmacyContext (ChatPharmacyContext?): 메시지에 첨부한 약국 연락처·위치 정보
// - remainingDays (int?): 복약 맥락의 남은 복용 일수
// - courseEndDate (DateTime?): 복약 맥락에서 계산된 복용 종료일
// - showSafetyGuidance (bool): 채팅 카드에 안전 안내를 표시할지 여부
// - readAt (DateTime?): 상대가 메시지를 읽은 시각
// - hiddenForMe (bool): 현재 사용자에게만 숨겨진 메시지 상태
// - deletedForEveryone (bool): 모든 참여자에게 삭제된 메시지 상태
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
  final bool hiddenForMe;
  final bool deletedForEveryone;

  // 함수이름: ChatMessage
  // 함수역할: 메시지 식별자·발신자·본문·작성 시각과 선택적 복약·약국 맥락 및 읽음·삭제 상태를 한 기록으로 묶는다.
  // 매개변수:
  // - messageId (int): 서버가 부여한 채팅 메시지 ID
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // - senderHash (String): 메시지를 작성한 참여자 해시
  // - clientMessageId (String): 전송 재시도 중복 방지용 클라이언트 메시지 ID
  // - body (String): 전송하거나 표시할 메시지·알림 본문
  // - createdAt (DateTime): 메시지 작성 시각
  // - messageKind (ChatMessageKind): 일반·복약·약국 맥락 메시지 유형
  // - medicationContext (ChatMedicationContext?): 구형 단일 약 첨부 맥락
  // - medicationContexts (List<ChatMedicationContext>): 메시지에 첨부한 여러 약의 맥락
  // - scheduleContext (ChatScheduleContext?): 메시지에 첨부한 시간대별 복약 진행 정보
  // - pharmacyContext (ChatPharmacyContext?): 메시지에 첨부한 약국 연락처·위치 정보
  // - remainingDays (int?): 복약 맥락의 남은 복용 일수
  // - courseEndDate (DateTime?): 복약 맥락에서 계산된 복용 종료일
  // - showSafetyGuidance (bool): 채팅 카드에 안전 안내를 표시할지 여부
  // - readAt (DateTime?): 상대가 메시지를 읽은 시각
  // - hiddenForMe (bool): 현재 사용자에게만 숨겨진 메시지 상태
  // - deletedForEveryone (bool): 모든 참여자에게 삭제된 메시지 상태
  // 반환값:
  // - ChatMessage: 초기화된 인스턴스.
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
    this.hiddenForMe = false,
    this.deletedForEveryone = false,
  });

  // 함수이름: ChatMessage.fromJson
  // 함수역할: 서버 응답을 필수 필드가 검증된 채팅 메시지로 변환한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 해당 모델의 서버 응답 또는 저장 JSON 객체
  // 반환값:
  // - ChatMessage: 필드 검증과 기본값 처리를 거쳐 복원한 레코드.
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
        (body.isEmpty &&
            json['hidden_for_me'] != true &&
            json['deleted_for_everyone'] != true) ||
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
      hiddenForMe: json['hidden_for_me'] == true,
      deletedForEveryone: json['deleted_for_everyone'] == true,
    );
  }

  // 함수이름: canDeleteForEveryone
  // 함수역할: 본인이 작성한 미삭제·미숨김 메시지 중 작성 후 24시간 미만인 항목에만 공유 삭제 선택지를 제공하며 최종 기한 검증은 서버에 맡긴다.
  // 매개변수:
  // - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // - now (DateTime): 비교와 날짜 계산의 기준 시각
  // 반환값:
  // - bool: 본인이 작성한 미삭제·미숨김 메시지 중 작성 후 24시간 미만인 항목에만 공유 삭제 선택지를 제공하며 최종 기한 검증은 서버에 맡긴다.
  bool canDeleteForEveryone(String userHash, DateTime now) {
    final age = now.toUtc().difference(createdAt.toUtc());
    return senderHash == userHash &&
        !deletedForEveryone &&
        !hiddenForMe &&
        !age.isNegative &&
        age < const Duration(hours: 24);
  }

  // 함수이름: copyWith
  // 함수역할: 읽음·숨김·공유 삭제 상태를 갱신하고 숨김 또는 삭제가 적용되면 본문·약·일정·약국·안전 안내 맥락을 제거한다.
  // 매개변수:
  // - readAt (DateTime?): 상대가 메시지를 읽은 시각
  // - hiddenForMe (bool?): 현재 사용자에게만 숨겨진 메시지 상태
  // - deletedForEveryone (bool?): 모든 참여자에게 삭제된 메시지 상태
  // 반환값:
  // - ChatMessage: 지정한 상태를 반영한 사본. 적용된 hiddenForMe 또는 deletedForEveryone이 true이면 본문·첨부 문맥·복용 기간 정보를 비우고 안전 안내를 끄며 messageKind를 text로 설정한다.
  ChatMessage copyWith({
    DateTime? readAt,
    bool? hiddenForMe,
    bool? deletedForEveryone,
  }) {
    final hidden = hiddenForMe ?? this.hiddenForMe;
    final deleted = deletedForEveryone ?? this.deletedForEveryone;
    final redact = hidden || deleted;
    return ChatMessage(
      messageId: messageId,
      linkId: linkId,
      senderHash: senderHash,
      clientMessageId: clientMessageId,
      body: redact ? '' : body,
      createdAt: createdAt,
      messageKind: redact ? ChatMessageKind.text : messageKind,
      medicationContext: redact ? null : medicationContext,
      medicationContexts: redact ? const [] : medicationContexts,
      scheduleContext: redact ? null : scheduleContext,
      pharmacyContext: redact ? null : pharmacyContext,
      remainingDays: redact ? null : remainingDays,
      courseEndDate: redact ? null : courseEndDate,
      showSafetyGuidance: !redact && showSafetyGuidance,
      readAt: readAt ?? this.readAt,
      hiddenForMe: hidden,
      deletedForEveryone: deleted,
    );
  }

  // 함수이름: _readString
  // 함수역할: 선택적 필드를 공백 정리한 문자열로 바꾸고 없는 값은 빈 문자열로 처리한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - String: 공백 정리한 필드 문자열; null이면 빈 문자열.
  static String _readString(dynamic value) => value?.toString().trim() ?? '';

  // 함수이름: _readInt
  // 함수역할: 정수 또는 숫자 문자열을 읽고 변환할 수 없으면 null을 사용한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - int?: 정수 또는 숫자 문자열을 읽고 변환할 수 없으면 null을 사용한다.
  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(_readString(value));
  }

  // 함수이름: _readDouble
  // 함수역할: 숫자 또는 숫자 문자열을 실수로 변환하고 실패하면 0을 사용한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - double: 숫자 또는 숫자 문자열을 실수로 변환하고 실패하면 0을 사용한다.
  static double _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(_readString(value)) ?? 0;
  }

  // 함수이름: attachedMedicationContexts
  // 함수역할: 새 다중 약 응답과 이전 단일 약 응답을 같은 목록 형태로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - List<ChatMedicationContext>: 새 다중 약 응답과 이전 단일 약 응답을 같은 목록 형태로 제공한다.
  List<ChatMedicationContext> get attachedMedicationContexts {
    if (medicationContexts.isNotEmpty) {
      return medicationContexts;
    }
    final singleContext = medicationContext;
    return singleContext == null ? const [] : [singleContext];
  }

  // 함수이름: _readMedicationContexts
  // 함수역할: 약 첨부 배열을 변환하고 같은 약 ID의 첫 맥락만 남겨 중복 카드 표시를 방지한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - List<ChatMedicationContext>: 약 첨부 배열을 변환하고 같은 약 ID의 첫 맥락만 남겨 중복 카드 표시를 방지한다.
  static List<ChatMedicationContext> _readMedicationContexts(dynamic value) {
    if (value is! List) {
      return const [];
    }
    final contextsById = <int, ChatMedicationContext>{};
    for (final item in value.whereType<Map>()) {
      final context = ChatMedicationContext.fromJson(
        Map<String, dynamic>.from(item),
      );
      contextsById.putIfAbsent(context.medicationId, /* 함수이름: putIfAbsent 콜백
       * 함수역할: 같은 약 키가 아직 없을 때 최초 채팅 약 문맥을 보존한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 중복 제거 목록에 사용할 약 문맥.
       */() => context);
    }
    return contextsById.values.toList(growable: false);
  }
}
