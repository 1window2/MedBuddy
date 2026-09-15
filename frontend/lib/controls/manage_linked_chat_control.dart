// 파일명: manage_linked_chat_control.dart
// 역할: 환자·보호자 채팅 REST API 호출과 응답 해석을 담당한다.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../entities/chat_message_entity.dart';
import '../entities/medication_detail_entity.dart';
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
  // 매개변수:
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // - beforeMessageId (int?): 이 메시지보다 이전 기록을 가져올 페이지 기준
  // - limit (int): 한 번에 선택하거나 조회할 최대 항목 수
  // 반환값:
  // - Future<List<ChatMessage>>: 현재 연동에서 최근 채팅 기록 한 페이지를 오래된 순서로 조회한다.
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
    return rawMessages
        .whereType<Map>()
        .map(/* 함수이름: map 콜백
         * 함수역할: 연결 채팅 응답 항목을 메시지 모델로 변환한다.
         * 매개변수:
         * - item (Map): 현재 변환·검사 중인 응답 또는 목록 항목
         * 반환값:
         * - 메시지 본문과 복약 문맥을 담은 채팅 메시지.
         */(item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
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
  }) async {
    final normalizedMedicationIds = medicationIds
        .where(/* 함수이름: where 콜백
         * 함수역할: 채팅 약 참조에 사용할 수 있는 양의 약 ID만 남긴다.
         * 매개변수:
         * - id (int): 플랫폼 알림의 예약·교체·취소 식별자
         * 반환값:
         * - ID가 양수이면 true.
         */(id) => id > 0)
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
          }),
        )
        .timeout(_requestTimeout);
    final decoded = _decodeSuccessfulResponse(response, '메시지를 보내지 못했습니다.');
    final rawMessage = decoded['data'];
    if (rawMessage is! Map) {
      throw StateError('메시지 전송 응답 형식이 올바르지 않습니다.');
    }
    return ChatMessage.fromJson(Map<String, dynamic>.from(rawMessage));
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
        messageIds.any(/* 함수이름: any 콜백
         * 함수역할: 요청의 참조 ID 중 서버 식별자로 사용할 수 없는 값이 있는지 확인한다.
         * 매개변수:
         * - id (int): 플랫폼 알림의 예약·교체·취소 식별자
         * 반환값:
         * - ID가 1보다 작으면 true.
         */(id) => id < 1)) {
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
      throw StateError(
        '$failureMessage (${response.statusCode}): '
        '${ApiResponseParser.extractErrorDetail(responseBody)}',
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
