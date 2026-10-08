// 파일명: manage_linked_chat_control.dart
// 역할: 환자·보호자 채팅 REST API 호출과 응답 해석을 담당한다.

import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../entities/chat_message_entity.dart';
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

// 서버에서 함께 저장한 메시지와 현재 일정 상태를 전달한다.
class ChatMedicationTakenResult {
  final ChatMessage message;
  final List<MedicationSchedule> schedules;

  const ChatMedicationTakenResult({
    required this.message,
    required this.schedules,
  });
}

// 읽음 처리 전에 받은 개수와 첫 미확인 메시지 위치를 함께 보관한다.
class ChatUnreadSummary {
  final int count;
  final int? firstMessageId;

  const ChatUnreadSummary({required this.count, this.firstMessageId});
}

// 클래스명: ChatHistoryPage
// 역할: 해석할 수 있는 메시지만 담은 채팅 기록 한 페이지와 서버가 보낸 원래 행 수를 함께 전달한다.
// 주요 책임:
// - 해석하지 못해 건너뛴 행이 있어도 "50행이면 이전 페이지가 더 있다"는 판단이 달라지지 않게 한다.
// 속성:
// - rowCount (int): 건너뛴 행을 포함해 서버가 이 페이지에 보낸 행 수
class ChatHistoryPage extends UnmodifiableListView<ChatMessage> {
  final int rowCount;

  // 함수이름: ChatHistoryPage
  // 함수역할: 해석한 메시지 목록과 서버 응답의 원래 행 수를 묶는다.
  // 매개변수:
  // - messages (Iterable<ChatMessage>): 오래된 순서로 해석한 메시지
  // - rowCount (int): 서버가 보낸 행 수
  // 반환값:
  // - ChatHistoryPage: 초기화된 인스턴스.
  ChatHistoryPage(super.messages, {required this.rowCount});

  // 함수이름: rowCountOf
  // 함수역할: 기록 페이지의 서버 행 수를 읽고, 행 수를 따로 담지 않은 일반 목록은 목록 길이를 사용한다.
  // 매개변수:
  // - page (List<ChatMessage>): requestHistory가 반환한 페이지
  // 반환값:
  // - int: 이전 페이지 존재 여부를 판단할 행 수.
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

  // 함수이름: requestHistory
  // 함수역할: 현재 연동에서 최근 채팅 기록 한 페이지를 오래된 순서로 조회한다.
  //           해석할 수 없는 행은 실시간 수신과 같이 건너뛰어 한 행 때문에 대화 전체가 막히지 않게 한다.
  // 매개변수:
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // - beforeMessageId (int?): 이 메시지보다 이전 기록을 가져올 페이지 기준
  // - limit (int): 한 번에 선택하거나 조회할 최대 항목 수
  // 반환값:
  // - Future<List<ChatMessage>>: 해석한 메시지와 서버 행 수를 담은 ChatHistoryPage.
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
  // - messageKind (ChatMessageKind): 일반·복약·약국 맥락 메시지 유형
  // - slotKey (String?): morning·lunch·evening·bedtime 복약 시간대 키
  // - pharmacyId (String?): 공공데이터 또는 서버의 약국 식별자
  // 반환값:
  // - Future<ChatMessage>: 일반 또는 복약 맥락 메시지를 보내고 재시도 중복 저장을 방지한다.
  Future<ChatMessage> sendMessage({
    required int linkId,
    required String clientMessageId,
    required String body,
    int? medicationId,
    List<int> medicationIds = const [],
    ChatMessageKind messageKind = ChatMessageKind.text,
    String? slotKey,
    String? pharmacyId,
    String? hospitalId,
    String? hospitalScheduleDate,
    int? sourceAlertId,
  }) async {
    final normalizedMedicationIds = medicationIds
        .where(
          /* 함수이름: where 콜백
         * 함수역할: 채팅 약 참조에 사용할 수 있는 양의 약 ID만 남긴다.
         * 매개변수:
         * - id (int): 플랫폼 알림의 예약·교체·취소 식별자
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
            'slot_key': ?slotKey,
            'pharmacy_id': ?pharmacyId,
            'hospital_id': ?hospitalId,
            'hospital_schedule_date': ?hospitalScheduleDate,
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

  // 함수역할: 명시적으로 확인한 날짜·시간대·약만 기록하며 재시도 ID를 유지한다.
  // 반환값: 서버가 함께 저장한 메시지와 오늘 일정의 최신 상태.
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
  Future<ChatUnreadSummary> requestUnreadSummary({required int linkId}) async {
    final response = await _client
        .get(_buildUri('/links/$linkId/unread-count'))
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

  // 함수이름: _decodeSuccessfulResponse
  // 함수역할: 응답을 디코딩하고 2xx 이외 상태에는 호출 맥락과 서버 상세를 포함한 오류를 발생시킨다.
  // 매개변수:
  // - response (http.Response): 상태 코드와 본문을 해석할 HTTP 응답
  // - failureMessage (String): 실패 상태에 사용할 사용자 안내문
  // 반환값:
  // - Map<String, dynamic>: 응답을 디코딩하고 2xx 이외 상태에는 호출 맥락과 서버 상세를 포함한 오류를 발생시킨다.
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
