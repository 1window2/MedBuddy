// 파일명: manage_linked_chat_control.dart
// 역할: 환자·보호자 채팅 REST API 호출과 응답 해석을 담당한다.

import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../entities/chat_message_entity.dart';
import '../entities/chat_notification_summary.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';
import '../services/auth_config.dart';
import '../services/authenticated_api_client.dart';

// 함수이름: ChatUrlBuilder
// 함수역할: 채팅 REST 하위 경로를 배포 환경의 전체 주소로 바꾸는 URL 구성 계약이다.
// 매개변수:
// - path (String): 설정된 API 리소스 뒤에 붙일 하위 경로
// 반환값:
// - String: 채팅 REST 하위 경로를 배포 환경의 전체 주소로 바꾸는 URL 구성 계약이다.
typedef ChatUrlBuilder = String Function(String path);

// 클래스명: ChatMedicationTakenResult
// 역할: 한 번의 복용 기록 요청으로 서버에 함께 저장된 대화와 일정을 전달한다.
// 주요 책임: 확정 메시지와 최신 복약 상태를 동일 응답으로 유지한다.
// 속성: message: 저장 메시지; schedules: 반환된 일정 목록.
class ChatMedicationTakenResult {
  final ChatMessage message;
  final List<MedicationSchedule> schedules;

  // 함수이름: ChatMedicationTakenResult
  // 함수역할: 확정된 복용 메시지와 일정 목록을 묶는다.
  // 매개변수: message: 저장된 ChatMessage; schedules: 최신 MedicationSchedule 목록.
  // 반환값: 결과 객체; 목록을 별도로 복사하거나 동결하지 않는다.
  const ChatMedicationTakenResult({
    required this.message,
    required this.schedules,
  });
}

// 클래스명: ChatUnreadSummary
// 역할: 읽음 처리 전에 조회한 미확인 메시지 수와 시작 위치를 보관한다.
// 주요 책임: 대화 진입 위치와 선택적 알림 미리보기 정보를 함께 전달한다.
// 속성: count: 미확인 수; firstMessageId: 첫 미확인 ID; notification: 선택적 알림 요약.
class ChatUnreadSummary {
  final int count;
  final int? firstMessageId;
  final ChatNotificationSummary? notification;

  // 함수이름: ChatUnreadSummary
  // 함수역할: 미확인 개수와 선택적 첫 메시지·알림 정보를 보관한다.
  // 매개변수: count: 미확인 개수; firstMessageId: 첫 ID; notification: 알림 요약.
  // 반환값: 요약 객체; 값 검증은 응답 조회 메서드가 수행한다.
  const ChatUnreadSummary({
    required this.count,
    this.firstMessageId,
    this.notification,
  });
}

// Class Name: ChatHistoryPage
// Role: Carries parsed chat messages alongside the server's original page length.
// Responsibilities: Keep skipped malformed rows from changing pagination decisions.
// Attributes: rowCount: Raw server row count; inherited read-only list: Successfully parsed messages in received order.
class ChatHistoryPage extends UnmodifiableListView<ChatMessage> {
  final int rowCount;

  // Function Name: ChatHistoryPage
  // Description: Wraps parsed messages and the original server row count.
  // Parameters: messages: Parsed message iterable; rowCount: Count including skipped rows.
  // Returns: An unmodifiable message view with pagination metadata.
  ChatHistoryPage(super.messages, {required this.rowCount});

  // Function Name: rowCountOf
  // Description: Reads raw page length when available, falling back to ordinary list length.
  // Parameters: page: A chat history result list.
  // Returns: The count used to decide whether earlier pages may exist.
  static int rowCountOf(List<ChatMessage> page) =>
      page is ChatHistoryPage ? page.rowCount : page.length;
}

// 클래스명: ManageLinkedChat
// 역할: 인증된 연동 참여자의 채팅 REST 요청을 조정한다.
// 주요 책임:
// - 기록·복약 맥락 조회, 중복 방지 전송, 선택 삭제와 읽음 갱신을 수행하고 성공 응답을 검증한다.
// 속성:
// - _requestTimeout (Duration): 식별·분석 요청의 최대 대기시간
// - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
// - _client (http.Client): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
// - _chatUrlBuilder (ChatUrlBuilder): 채팅 하위 경로의 전체 URL 구성 경계
class ManageLinkedChat {
  static const Duration _requestTimeout = Duration(seconds: 20);

  final String userHash;
  final http.Client _client;
  final bool _ownsClient;
  final ChatUrlBuilder _chatUrlBuilder;

  // 함수이름: ManageLinkedChat
  // 함수역할: 현재 사용자와 채팅 URL 구성 경계를 연결하고 주입된 HTTP 클라이언트가 없으면 인증 클라이언트를 소유한다.
  // 매개변수:
  // - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // - client (http.Client?): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
  // - chatUrlBuilder (ChatUrlBuilder?): 채팅 하위 경로의 전체 URL 구성 경계
  // 반환값:
  // - ManageLinkedChat: 초기화된 인스턴스.
  ManageLinkedChat({
    required this.userHash,
    http.Client? client,
    ChatUrlBuilder? chatUrlBuilder,
  }) : _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null,
       _chatUrlBuilder = chatUrlBuilder ?? ApiConfig.chatUrl;

  // Function Name: requestHistory
  // Description: Loads a history page and skips rows rejected with FormatException while preserving server row count.
  // Parameters: linkId: Conversation relationship; beforeMessageId: Optional earlier-page boundary; limit: Requested page size.
  // Returns: A ChatHistoryPage in server-provided order; transport, unsuccessful status and invalid list envelopes propagate errors.
  Future<List<ChatMessage>> requestHistory({
    required int linkId,
    int? beforeMessageId,
    int limit = 50,
  }) async {
    final response = await _client
        .get(
          _buildUri(
            '/links/$linkId/messages',
            parameters: {
              if (beforeMessageId != null)
                'before_message_id': '$beforeMessageId',
              'limit': '$limit',
            },
          ),
        )
        .timeout(_requestTimeout);
    final decoded = _decodeSuccessfulResponse(response, '채팅 기록을 불러오지 못했습니다.');
    final rawMessages = decoded['data'];
    if (rawMessages is! List) {
      throw StateError('채팅 기록 응답 형식이 올바르지 않습니다.');
    }
    final messages = <ChatMessage>[];
    for (final item in rawMessages.whereType<Map>()) {
      try {
        messages.add(ChatMessage.fromJson(Map<String, dynamic>.from(item)));
      } on FormatException {
        // 필수 값이 없는 행은 표시하지 않고 나머지 기록을 유지한다.
        continue;
      }
    }
    return ChatHistoryPage(messages, rowCount: rawMessages.length);
  }

  // 함수이름: requestMedicationContexts
  // 함수역할: 현재 연동 환자가 오늘 복용 중인 약을 서버 권한 검증 후 불러온다.
  // 매개변수:
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // 반환값:
  // - Future<List<ChatMedicationContext>>: 현재 연동 환자가 오늘 복용 중인 약을 서버 권한 검증 후 불러온다.
  Future<List<ChatMedicationContext>> requestMedicationContexts({
    required int linkId,
  }) async {
    final response = await _client
        .get(_buildUri('/links/$linkId/medications'))
        .timeout(_requestTimeout);
    final decoded = _decodeSuccessfulResponse(
      response,
      '복약 대화에 사용할 약 정보를 불러오지 못했습니다.',
    );
    final rawMedications = decoded['data'];
    if (rawMedications is! List) {
      throw StateError('복약 대화 약 목록 응답 형식이 올바르지 않습니다.');
    }
    return rawMedications
        .whereType<Map>()
        .map(
          // 함수이름: map 콜백
          // 함수역할: 채팅에서 공유 가능한 약 응답을 약 문맥 모델로 변환한다.
          // 매개변수:
          // - item (Map): 현재 변환·검사 중인 응답 또는 목록 항목
          // 반환값:
          // - 공유할 약의 식별·표시 정보.
          (item) =>
              ChatMedicationContext.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  // 함수이름: requestScheduleContexts
  // 함수역할: 현재 연동 환자의 오늘 복약 상태를 시간대별 카드 정보로 불러온다.
  // 매개변수:
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // 반환값:
  // - Future<List<ChatScheduleContext>>: 현재 연동 환자의 오늘 복약 상태를 시간대별 카드 정보로 불러온다.
  Future<List<ChatScheduleContext>> requestScheduleContexts({
    required int linkId,
  }) async {
    final response = await _client
        .get(_buildUri('/links/$linkId/schedule-contexts'))
        .timeout(_requestTimeout);
    final decoded = _decodeSuccessfulResponse(
      response,
      '시간대별 복약 상태를 불러오지 못했습니다.',
    );
    final rawContexts = decoded['data'];
    if (rawContexts is! List) {
      throw StateError('시간대별 복약 상태 응답 형식이 올바르지 않습니다.');
    }
    return rawContexts
        .whereType<Map>()
        .map(
          // 함수이름: map 콜백
          // 함수역할: 공유 가능한 복약 일정 응답을 시간대 문맥 모델로 변환한다.
          // 매개변수:
          // - item (Map): 현재 변환·검사 중인 응답 또는 목록 항목
          // 반환값:
          // - 공유할 일정의 날짜와 시간대 정보.
          (item) =>
              ChatScheduleContext.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  // 함수이름: requestMedicationDetail
  // 함수역할: 채팅에 연결된 약의 상세정보를 연동 참여자 권한 범위에서 조회한다.
  // 매개변수:
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // - medicationId (int): 대상 저장 복약정보의 식별자
  // 반환값:
  // - Future<MedicationDetail>: 채팅에 연결된 약의 상세정보를 연동 참여자 권한 범위에서 조회한다.
  Future<MedicationDetail> requestMedicationDetail({
    required int linkId,
    required int medicationId,
  }) async {
    final response = await _client
        .get(_buildUri('/links/$linkId/medications/$medicationId'))
        .timeout(_requestTimeout);
    final decoded = _decodeSuccessfulResponse(response, '약 상세정보를 불러오지 못했습니다.');
    final rawMedication = decoded['data'];
    if (rawMedication is! Map) {
      throw StateError('약 상세정보 응답 형식이 올바르지 않습니다.');
    }
    return MedicationDetail.fromJson(Map<String, dynamic>.from(rawMedication));
  }

  // 함수이름: sendMessage
  // 함수역할: 일반 또는 복약 맥락 메시지를 보내고 재시도 중복 저장을 방지한다.
  // 매개변수:
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // - clientMessageId (String): 전송 재시도 중복 방지용 클라이언트 메시지 ID
  // - body (String): 전송하거나 표시할 메시지·알림 본문
  // - medicationId (int?): 대상 저장 복약정보의 식별자
  // - medicationIds (List<int>): 처리할 저장 복약정보 식별자 목록
  // - medicationReferences (List<ChatMedicationReference>): 일반 메시지에 붙일 저장하지 않은 검색약
  // - messageKind (ChatMessageKind): 일반·복약·약국 맥락 메시지 유형
  // - slotKey (String?): morning·lunch·evening·bedtime 복약 시간대 키
  // - pharmacyId (String?): 공공데이터 또는 서버의 약국 식별자
  // - hospitalId (String?): 공유 병원 식별자; hospitalScheduleDate (String?): 공유 진료일(날짜 문자열).
  // - historyStartDate/historyEndDate (String?): 공유 복약 기록의 시작·종료일; sourceAlertId (int?): 확인 요청의 원본 보호자 알림 ID.
  // 반환값:
  // - Future<ChatMessage>: 일반 또는 복약 맥락 메시지를 보내고 재시도 중복 저장을 방지한다.
  Future<ChatMessage> sendMessage({
    required int linkId,
    required String clientMessageId,
    required String body,
    int? medicationId,
    List<int> medicationIds = const [],
    List<ChatMedicationReference> medicationReferences = const [],
    ChatMessageKind messageKind = ChatMessageKind.text,
    String? slotKey,
    String? pharmacyId,
    String? hospitalId,
    String? hospitalScheduleDate,
    String? historyStartDate,
    String? historyEndDate,
    int? sourceAlertId,
  }) async {
    final normalizedMedicationIds = medicationIds
        .where(
          /* 함수이름: where 콜백
         * 함수역할: 채팅 약 참조에 사용할 수 있는 양의 약 ID만 남긴다.
         * 매개변수:
         * - id (int): 메시지에 첨부할 저장 약 식별자
         * 반환값:
         * - ID가 양수이면 true.
         */
          (id) => id > 0,
        )
        .toSet()
        .toList(growable: false);
    final primaryMedicationId =
        medicationId ??
        (normalizedMedicationIds.isEmpty
            ? null
            : normalizedMedicationIds.first);
    final response = await _client
        .post(
          _buildUri('/links/$linkId/messages'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'client_message_id': clientMessageId,
            'body': body,
            'message_kind': messageKind.wireName,
            'medication_id': ?primaryMedicationId,
            if (normalizedMedicationIds.isNotEmpty)
              'medication_ids': normalizedMedicationIds,
            if (medicationReferences.isNotEmpty)
              'medication_references': medicationReferences
                  .map((item) => item.toJson())
                  .toList(),
            'slot_key': ?slotKey,
            'pharmacy_id': ?pharmacyId,
            'hospital_id': ?hospitalId,
            'hospital_schedule_date': ?hospitalScheduleDate,
            'history_start_date': ?historyStartDate,
            'history_end_date': ?historyEndDate,
            'source_alert_id': ?sourceAlertId,
          }),
        )
        // 병원 정보 확인의 서버 제한(22초)보다 응답 대기를 조금 길게 둔다.
        .timeout(
          messageKind == ChatMessageKind.hospitalShare
              ? const Duration(seconds: 25)
              : _requestTimeout,
        );
    final decoded = _decodeSuccessfulResponse(response, '메시지를 보내지 못했습니다.');
    final rawMessage = decoded['data'];
    if (rawMessage is! Map) {
      throw StateError('메시지 전송 응답 형식이 올바르지 않습니다.');
    }
    return ChatMessage.fromJson(Map<String, dynamic>.from(rawMessage));
  }

  // 함수이름: recordMedicationTaken
  // 함수역할: 사용자가 확인한 날짜·시간대·약의 복용 기록과 대화 메시지를 함께 저장하도록 요청한다.
  // 매개변수: linkId: 연동 ID; clientMessageId: 재시도에도 유지할 요청 ID; scheduleDate/slotKey: 확정 날짜와 구간; medicationIds: 확정 약 ID 목록.
  // 반환값: 서버가 저장한 메시지와 최신 일정; 통신 실패나 응답 구조 오류는 전파한다.
  Future<ChatMedicationTakenResult> recordMedicationTaken({
    required int linkId,
    required String clientMessageId,
    required String scheduleDate,
    required String slotKey,
    required List<int> medicationIds,
  }) async {
    final response = await _client
        .post(
          _buildUri('/links/$linkId/medication-taken'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'client_message_id': clientMessageId,
            'schedule_date': scheduleDate,
            'slot_key': slotKey,
            'medication_ids': medicationIds,
          }),
        )
        .timeout(_requestTimeout);
    final decoded = _decodeSuccessfulResponse(response, '복용 기록을 저장하지 못했습니다.');
    final message = decoded['data'];
    final schedules = decoded['schedules'];
    if (message is! Map || schedules is! List) {
      throw StateError('복용 기록 응답 형식이 올바르지 않습니다.');
    }
    return ChatMedicationTakenResult(
      message: ChatMessage.fromJson(Map<String, dynamic>.from(message)),
      schedules: schedules
          .map(
            (item) => MedicationSchedule.fromScheduleJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  // 함수이름: deleteMessages
  // 함수역할: 1~50개의 양수 메시지 ID를 검증하고 개인·공유 삭제 범위로 요청한 뒤 서버의 전체 삭제 확인을 요구한다.
  // 매개변수:
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // - messageIds (List<int>): 선택 삭제할 메시지 ID 목록
  // - scope (ChatDeletionScope): 본인 또는 모든 참여자를 대상으로 하는 메시지 삭제 범위
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> deleteMessages({
    required int linkId,
    required List<int> messageIds,
    required ChatDeletionScope scope,
  }) async {
    if (messageIds.isEmpty ||
        messageIds.length > 50 ||
        messageIds.any(
          /* 함수이름: any 콜백
         * 함수역할: 요청의 참조 ID 중 서버 식별자로 사용할 수 없는 값이 있는지 확인한다.
         * 매개변수:
         * - id (int): 플랫폼 알림의 예약·교체·취소 식별자
         * 반환값:
         * - ID가 1보다 작으면 true.
         */
          (id) => id < 1,
        )) {
      throw ArgumentError('Select between 1 and 50 messages.');
    }
    final response = await _client
        .post(
          _buildUri('/links/$linkId/messages/delete'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message_ids': messageIds.toSet().toList(),
            'scope': scope.name,
          }),
        )
        .timeout(_requestTimeout);
    final decoded = _decodeSuccessfulResponse(response, '메시지를 삭제하지 못했습니다.');
    if (decoded['success'] != true) {
      throw StateError('Message deletion was not confirmed.');
    }
  }

  // 함수이름: requestUnreadSummary
  // 함수역할: 읽음 상태를 바꾸지 않고 미확인 개수와 구분선 기준을 조회한다.
  // 매개변수: linkId: 활성 연동 ID. 반환값: 서버의 미확인 상태.
  Future<ChatUnreadSummary> requestUnreadSummary({required int linkId}) =>
      _requestUnreadSummary(linkId: linkId);

  // 함수이름: requestNotificationSummary
  // 함수역할: 읽음 상태를 바꾸지 않고 알림 미리보기를 포함한 미확인 요약을 요청한다.
  // 매개변수: linkId: 대화 연동 ID.
  // 반환값: 알림 요약 Future; 제공된 요약이 없으면 null, 요청 실패는 전파한다.
  Future<ChatNotificationSummary?> requestNotificationSummary({
    required int linkId,
  }) async => (await _requestUnreadSummary(
    linkId: linkId,
    includeNotificationPreview: true,
  )).notification;

  // 함수이름: _requestUnreadSummary
  // 함수역할: 미확인 개수와 첫 메시지 ID를 조회하고 값의 타입·범위를 검증한다.
  // 매개변수: linkId: 연동 ID; includeNotificationPreview: 알림 미리보기 포함 요청 여부.
  // 반환값: 검증된 요약; 음수 개수나 비양수 ID 등 잘못된 응답은 StateError.
  Future<ChatUnreadSummary> _requestUnreadSummary({
    required int linkId,
    bool includeNotificationPreview = false,
  }) async {
    final uri = _buildUri('/links/$linkId/unread-count');
    final response = await _client
        .get(
          includeNotificationPreview
              ? uri.replace(
                  queryParameters: {
                    ...uri.queryParameters,
                    'include_notification_preview': 'true',
                  },
                )
              : uri,
        )
        .timeout(_requestTimeout);
    final decoded = _decodeSuccessfulResponse(
      response,
      '안 읽은 메시지를 확인하지 못했습니다.',
    );
    final data = decoded['data'];
    if (data is! Map ||
        data['unread_count'] is! int ||
        data['unread_count'] < 0) {
      throw StateError('Invalid unread message count.');
    }
    final firstId = data['first_unread_message_id'];
    if (firstId != null && (firstId is! int || firstId <= 0)) {
      throw StateError('Invalid unread message boundary.');
    }
    return ChatUnreadSummary(
      count: data['unread_count'] as int,
      firstMessageId: firstId as int?,
      notification: ChatNotificationSummary.parse(data['notification']),
    );
  }

  // 함수이름: markRead
  // 함수역할: 화면에서 확인한 마지막 상대 메시지까지 읽음 상태로 갱신한다.
  // 매개변수:
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // - throughMessageId (int): 읽음 처리할 마지막 상대 메시지 ID
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> markRead({
    required int linkId,
    required int throughMessageId,
  }) async {
    final response = await _client
        .post(
          _buildUri('/links/$linkId/read'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'through_message_id': throughMessageId}),
        )
        .timeout(_requestTimeout);
    _decodeSuccessfulResponse(response, '읽음 상태를 갱신하지 못했습니다.');
  }

  // Function Name: _decodeSuccessfulResponse
  // Description: Decodes successful responses and retains HTTP status in failures for caller-specific handling.
  // Parameters: response: HTTP response; failureMessage: Operation-specific user guidance.
  // Returns: The decoded map for 2xx responses; other statuses throw a structured HTTP failure.
  Map<String, dynamic> _decodeSuccessfulResponse(
    http.Response response,
    String failureMessage,
  ) {
    final responseBody = ApiResponseParser.decodeBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // 문구는 그대로 두고 상태 코드를 함께 전달해 호출자가 403·404를 구분할 수 있게 한다.
      throw ApiResponseParser.httpFailure(
        failureMessage,
        response,
        responseBody,
      );
    }
    return ApiResponseParser.decodeMap(responseBody);
  }

  // 함수이름: _buildUri
  // 함수역할: 채팅 URL에 페이지 조건을 붙이고 인증 비활성 로컬 실행에서만 user_hash 조회 인자를 추가한다.
  // 매개변수:
  // - path (String): 설정된 API 리소스 뒤에 붙일 하위 경로
  // - parameters (Map<String, String>): 기본 범위에 추가할 HTTP 조회 조건
  // 반환값:
  // - Uri: 채팅 URL에 페이지 조건을 붙이고 인증 비활성 로컬 실행에서만 user_hash 조회 인자를 추가한다.
  Uri _buildUri(String path, {Map<String, String> parameters = const {}}) {
    final queryParameters = <String, String>{
      if (AuthConfig.mode == AuthenticationMode.disabled) 'user_hash': userHash,
      ...parameters,
    };
    return Uri.parse(
      _chatUrlBuilder(path),
    ).replace(queryParameters: queryParameters);
  }

  // 함수이름: dispose
  // 함수역할: 직접 생성한 HTTP 클라이언트만 닫고 외부에서 주입한 클라이언트의 수명은 호출자에게 맡긴다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
