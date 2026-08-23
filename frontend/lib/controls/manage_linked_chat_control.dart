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

typedef ChatUrlBuilder = String Function(String path);

class ManageLinkedChat {
  static const Duration _requestTimeout = Duration(seconds: 20);

  final String userHash;
  final http.Client _client;
  final bool _ownsClient;
  final ChatUrlBuilder _chatUrlBuilder;

  ManageLinkedChat({
    required this.userHash,
    http.Client? client,
    ChatUrlBuilder? chatUrlBuilder,
  }) : _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null,
       _chatUrlBuilder = chatUrlBuilder ?? ApiConfig.chatUrl;

  // 함수명: requestHistory
  // 역할:
  // - 현재 연동에서 최근 채팅 기록 한 페이지를 오래된 순서로 조회한다.
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
        .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  // 함수명: requestMedicationContexts
  // 역할:
  // - 현재 연동 환자가 오늘 복용 중인 약을 서버 권한 검증 후 불러온다.
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
          (item) =>
              ChatMedicationContext.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  // 함수명: requestMedicationDetail
  // 역할:
  // - 채팅에 연결된 약의 상세정보를 연동 참여자 권한 범위에서 조회한다.
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

  // 함수명: sendMessage
  // 역할:
  // - 클라이언트 요청 식별자와 함께 메시지를 보내 재시도 중복 저장을 방지한다.
  Future<ChatMessage> sendMessage({
    required int linkId,
    required String clientMessageId,
    required String body,
    required int medicationId,
  }) async {
    final response = await _client
        .post(
          _buildUri('/links/$linkId/messages'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'client_message_id': clientMessageId,
            'body': body,
            'medication_id': medicationId,
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

  // 함수명: markRead
  // 역할:
  // - 화면에서 확인한 마지막 상대 메시지까지 읽음 상태로 갱신한다.
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

  Uri _buildUri(String path, {Map<String, String> parameters = const {}}) {
    final queryParameters = <String, String>{
      if (AuthConfig.mode == AuthenticationMode.disabled) 'user_hash': userHash,
      ...parameters,
    };
    return Uri.parse(
      _chatUrlBuilder(path),
    ).replace(queryParameters: queryParameters);
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
