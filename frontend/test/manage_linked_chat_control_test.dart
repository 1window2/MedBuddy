// 파일명: manage_linked_chat_control_test.dart
// 역할: 연동 채팅 REST 요청과 응답 변환을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';

// 함수이름: _jsonResponse
// 함수역할:
// - 응답 데이터를 UTF-8 JSON으로 직렬화하고 지정 HTTP 상태를 붙인다.
// 매개변수:
// - body (Object): JSON으로 직렬화할 응답 본문.
// - statusCode (int): 모의 JSON 응답에 지정할 HTTP 상태 코드.
// 반환값:
// - UTF-8 JSON 본문과 지정 상태 코드의 HTTP 응답.
http.Response _jsonResponse(Object body, int statusCode) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

// 함수이름: main
// 함수역할:
// - 복약 대화 요청 계약, 내용 삭제, 복약 문맥과 읽음 처리 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  const baseUrl = 'https://api.example.test/api/v1/chat';

  // 함수이름: test 콜백
  // 함수역할:
  // - 채팅 삭제 요청이 명시적인 메시지 식별자와 삭제 범위를 전달하고 서버 거절을 오류로 보고하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'deletion sends explicit IDs and scope and surfaces server refusal',
    () async {
      var refuse = false;
      final control = ManageLinkedChat(
        userHash: 'patient-a',
        // 함수이름: chatUrlBuilder 콜백
        // 함수역할:
        // - 채팅 경로를 로컬 모의 서버 기준 주소에 연결한다.
        // 매개변수:
        // - path (String): 모의 서버 기준 주소 뒤에 붙일 채팅 API 상대 경로.
        // 반환값:
        // - 기준 주소 뒤에 요청 경로를 붙인 문자열.
        chatUrlBuilder: (path) => '$baseUrl$path',
        // 함수이름: MockClient 콜백
        // 함수역할:
        // - 메시지 식별자와 모두에게서 삭제 범위를 검사하고 만료 거절 또는 삭제 성공을 선택한다.
        // 매개변수:
        // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
        // 반환값:
        // - 만료 시 HTTP 409, 성공 시 HTTP 200 응답.
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/chat/links/17/messages/delete');
          expect(jsonDecode(request.body), {
            'message_ids': [1, 2],
            'scope': 'everyone',
          });
          return _jsonResponse(
            refuse ? {'detail': 'expired'} : {'success': true},
            refuse ? 409 : 200,
          );
        }),
      );
      await control.deleteMessages(
        linkId: 17,
        messageIds: [1, 2],
        scope: ChatDeletionScope.everyone,
      );
      refuse = true;
      await expectLater(
        control.deleteMessages(
          linkId: 17,
          messageIds: [1, 2],
          scope: ChatDeletionScope.everyone,
        ),
        throwsStateError,
      );
      control.dispose();
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 삭제 표시 메시지는 빈 본문을 허용하되 복약 문맥은 제거하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('redacted messages allow empty text and discard medication context', () {
    final message = ChatMessage.fromJson({
      'message_id': 1,
      'link_id': 17,
      'sender_hash': 'patient-a',
      'client_message_id': 'deleted_001',
      'body': '',
      'created_at': '2026-09-09T00:00:00Z',
      'deleted_for_everyone': true,
    });
    expect(message.deletedForEveryone, isTrue);
    expect(
      message.canDeleteForEveryone('patient-a', DateTime.utc(2026, 9, 9, 1)),
      isFalse,
    );
    final original = ChatMessage(
      messageId: 1,
      linkId: 17,
      senderHash: 'patient-a',
      clientMessageId: 'test_001',
      body: 'secret',
      createdAt: DateTime.utc(2026, 9, 9),
      medicationContext: const ChatMedicationContext(
        medicationId: 1,
        medicationName: 'secret pill',
        dosagePerTime: '1',
      ),
    );
    expect(
      original.canDeleteForEveryone('patient-a', DateTime.utc(2026, 9, 10)),
      isFalse,
    );
    expect(
      original.copyWith(deletedForEveryone: true).attachedMedicationContexts,
      isEmpty,
    );
    expect(original.copyWith(deletedForEveryone: true).body, isEmpty);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 최근 채팅 기록을 사용자와 연동 범위로 조회한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('최근 채팅 기록을 사용자와 연동 범위로 조회한다', () async {
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 사용자·이전 메시지·조회 개수 범위를 검사하고 상대의 미확인 메시지를 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 채팅 기록 한 건의 HTTP 200 응답.
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/chat/links/17/messages');
      expect(request.url.queryParameters['user_hash'], 'patient-a');
      expect(request.url.queryParameters['before_message_id'], '42');
      expect(request.url.queryParameters['limit'], '25');
      return _jsonResponse({
        'success': true,
        'data': [
          {
            'message_id': 41,
            'link_id': 17,
            'sender_hash': 'caregiver-a',
            'client_message_id': 'message_request_001',
            'body': '아침 약은 드셨나요?',
            'created_at': '2026-08-23T01:00:00+00:00',
            'read_at': null,
          },
        ],
      }, 200);
    });
    final control = ManageLinkedChat(
      userHash: 'patient-a',
      client: client,
      // 함수이름: chatUrlBuilder 콜백
      // 함수역할:
      // - 채팅 경로를 로컬 모의 서버 기준 주소에 연결한다.
      // 매개변수:
      // - path (String): 모의 서버 기준 주소 뒤에 붙일 채팅 API 상대 경로.
      // 반환값:
      // - 기준 주소 뒤에 요청 경로를 붙인 문자열.
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    final messages = await control.requestHistory(
      linkId: 17,
      beforeMessageId: 42,
      limit: 25,
    );

    expect(messages, hasLength(1));
    expect(messages.single.messageId, 41);
    expect(messages.single.body, '아침 약은 드셨나요?');
    expect(messages.single.readAt, isNull);
    control.dispose();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 클라이언트 요청 식별자와 여러 약 식별자를 함께 전송한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('클라이언트 요청 식별자와 여러 약 식별자를 함께 전송한다', () async {
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 재전송 식별자와 복수 약 선택 필드를 검사하고 두 약 문맥이 포함된 메시지를 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 복수 약 문맥과 새 메시지 식별자가 있는 HTTP 200 응답.
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/chat/links/17/messages');
      expect(request.url.queryParameters['user_hash'], 'patient-a');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['client_message_id'], 'message_request_002');
      expect(body['body'], '점심 약을 복용했어요.');
      expect(body['medication_id'], 91);
      expect(body['medication_ids'], [91, 92]);
      return _jsonResponse({
        'success': true,
        'created': true,
        'data': {
          'message_id': 52,
          'link_id': 17,
          'sender_hash': 'patient-a',
          'client_message_id': 'message_request_002',
          'body': '점심 약을 복용했어요.',
          'created_at': '2026-08-23T03:00:00+00:00',
          'medication_context': {
            'medication_id': 91,
            'medication_name': '테스트정',
            'image_url': 'https://example.com/pill.png',
            'dosage_per_time': '1정',
          },
          'medication_contexts': [
            {
              'medication_id': 91,
              'medication_name': '테스트정',
              'image_url': 'https://example.com/pill.png',
              'dosage_per_time': '1정',
            },
            {
              'medication_id': 92,
              'medication_name': '저녁정',
              'image_url': null,
              'dosage_per_time': '0.5정',
            },
          ],
          'read_at': null,
        },
      }, 200);
    });
    final control = ManageLinkedChat(
      userHash: 'patient-a',
      client: client,
      // 함수이름: chatUrlBuilder 콜백
      // 함수역할:
      // - 채팅 경로를 로컬 모의 서버 기준 주소에 연결한다.
      // 매개변수:
      // - path (String): 모의 서버 기준 주소 뒤에 붙일 채팅 API 상대 경로.
      // 반환값:
      // - 기준 주소 뒤에 요청 경로를 붙인 문자열.
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    final message = await control.sendMessage(
      linkId: 17,
      clientMessageId: 'message_request_002',
      body: '점심 약을 복용했어요.',
      medicationId: 91,
      medicationIds: const [91, 92],
    );

    expect(message.messageId, 52);
    expect(message.senderHash, 'patient-a');
    expect(message.medicationContext?.medicationName, '테스트정');
    expect(message.attachedMedicationContexts, hasLength(2));
    expect(
      // 함수이름: map 콜백
      // 함수역할:
      // - 목록 검증에 사용할 복약 문맥의 약 식별자를 추출한다.
      // 매개변수:
      // - item (ChatMedicationContext): 약 관련 필드를 추출할 목록 요소.
      // 반환값:
      // - 요소의 medicationId 값.
      message.attachedMedicationContexts.map((item) => item.medicationId),
      [91, 92],
    );
    control.dispose();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 약을 선택하지 않은 일반 메시지는 복약 식별자 없이 전송한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('약을 선택하지 않은 일반 메시지는 복약 식별자 없이 전송한다', () async {
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 일반 메시지 요청에 약 식별자 필드가 없는지 검사하고 복약 문맥 없는 메시지를 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 일반 텍스트 메시지의 HTTP 200 응답.
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['client_message_id'], 'message_request_003');
      expect(body['body'], '오늘은 몸 상태가 괜찮아요.');
      expect(body.containsKey('medication_id'), isFalse);
      expect(body.containsKey('medication_ids'), isFalse);
      return _jsonResponse({
        'success': true,
        'created': true,
        'data': {
          'message_id': 53,
          'link_id': 17,
          'sender_hash': 'patient-a',
          'client_message_id': 'message_request_003',
          'body': '오늘은 몸 상태가 괜찮아요.',
          'created_at': '2026-08-23T03:01:00+00:00',
          'medication_context': null,
          'read_at': null,
        },
      }, 200);
    });
    final control = ManageLinkedChat(
      userHash: 'patient-a',
      client: client,
      // 함수이름: chatUrlBuilder 콜백
      // 함수역할:
      // - 채팅 경로를 로컬 모의 서버 기준 주소에 연결한다.
      // 매개변수:
      // - path (String): 모의 서버 기준 주소 뒤에 붙일 채팅 API 상대 경로.
      // 반환값:
      // - 기준 주소 뒤에 요청 경로를 붙인 문자열.
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    final message = await control.sendMessage(
      linkId: 17,
      clientMessageId: 'message_request_003',
      body: '오늘은 몸 상태가 괜찮아요.',
    );

    expect(message.medicationContext, isNull);
    control.dispose();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 연동 환자의 활성 복약 목록을 채팅 선택 정보로 변환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('연동 환자의 활성 복약 목록을 채팅 선택 정보로 변환한다', () async {
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 연결별 활성 약 조회 경로를 검사하고 채팅에서 선택할 약을 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 약 식별자·이미지·복용량을 담은 HTTP 200 응답.
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/chat/links/17/medications');
      return _jsonResponse({
        'success': true,
        'data': [
          {
            'medication_id': 91,
            'medication_name': '테스트정',
            'image_url': 'https://example.com/pill.png',
            'dosage_per_time': '1정',
          },
        ],
      }, 200);
    });
    final control = ManageLinkedChat(
      userHash: 'caregiver-a',
      client: client,
      // 함수이름: chatUrlBuilder 콜백
      // 함수역할:
      // - 채팅 경로를 로컬 모의 서버 기준 주소에 연결한다.
      // 매개변수:
      // - path (String): 모의 서버 기준 주소 뒤에 붙일 채팅 API 상대 경로.
      // 반환값:
      // - 기준 주소 뒤에 요청 경로를 붙인 문자열.
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    final medications = await control.requestMedicationContexts(linkId: 17);

    expect(medications, hasLength(1));
    expect(medications.single.medicationId, 91);
    expect(medications.single.medicationName, '테스트정');
    expect(medications.single.dosagePerTime, '1정');
    control.dispose();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 오늘 복약 상태를 시간대별 진행 카드로 변환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('오늘 복약 상태를 시간대별 진행 카드로 변환한다', () async {
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 보호자 범위의 시간대 문맥 조회를 검사하고 두 약 중 하나 완료한 아침 카드를 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 알림 시각·진행률·약 목록의 HTTP 200 응답.
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/chat/links/17/schedule-contexts');
      expect(request.url.queryParameters['user_hash'], 'caregiver-a');
      return _jsonResponse({
        'success': true,
        'data': [
          {
            'slot_key': 'morning',
            'alarm_time': '08:00',
            'alarm_enabled': true,
            'completed_count': 1,
            'total_count': 2,
            'can_request_check': true,
            'medications': [
              {
                'medication_id': 91,
                'medication_name': '테스트정',
                'dosage_per_time': '1정',
              },
            ],
          },
        ],
      }, 200);
    });
    final control = ManageLinkedChat(
      userHash: 'caregiver-a',
      client: client,
      // 함수이름: chatUrlBuilder 콜백
      // 함수역할:
      // - 채팅 경로를 로컬 모의 서버 기준 주소에 연결한다.
      // 매개변수:
      // - path (String): 모의 서버 기준 주소 뒤에 붙일 채팅 API 상대 경로.
      // 반환값:
      // - 기준 주소 뒤에 요청 경로를 붙인 문자열.
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    final contexts = await control.requestScheduleContexts(linkId: 17);

    expect(contexts, hasLength(1));
    expect(contexts.single.slotKey, 'morning');
    expect(contexts.single.completedCount, 1);
    expect(contexts.single.totalCount, 2);
    expect(contexts.single.canRequestCheck, isTrue);
    expect(contexts.single.medications.single.medicationName, '테스트정');
    control.dispose();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 복약 확인 요청은 시간대와 서버가 만든 일정 스냅샷을 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('복약 확인 요청은 시간대와 서버가 만든 일정 스냅샷을 유지한다', () async {
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 복약 확인 요청의 메시지 유형과 시간대를 검사하고 서버 생성 일정 스냅샷을 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 시간대 확인 요청 메시지와 일정 문맥의 HTTP 200 응답.
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['message_kind'], 'slot_check_request');
      expect(body['slot_key'], 'morning');
      expect(body.containsKey('pharmacy_id'), isFalse);
      return _jsonResponse({
        'success': true,
        'created': true,
        'data': {
          'message_id': 54,
          'link_id': 17,
          'sender_hash': 'caregiver-a',
          'client_message_id': 'slot_request_001',
          'body': '아침 복약을 확인해주세요.',
          'message_kind': 'slot_check_request',
          'context': {
            'schedule_context': {
              'slot_key': 'morning',
              'alarm_time': '08:00',
              'alarm_enabled': true,
              'completed_count': 0,
              'total_count': 1,
              'medications': [
                {
                  'medication_id': 91,
                  'medication_name': '테스트정',
                  'dosage_per_time': '1정',
                },
              ],
            },
          },
          'created_at': '2026-08-23T03:02:00+00:00',
          'medication_context': null,
          'read_at': null,
        },
      }, 200);
    });
    final control = ManageLinkedChat(
      userHash: 'caregiver-a',
      client: client,
      // 함수이름: chatUrlBuilder 콜백
      // 함수역할:
      // - 채팅 경로를 로컬 모의 서버 기준 주소에 연결한다.
      // 매개변수:
      // - path (String): 모의 서버 기준 주소 뒤에 붙일 채팅 API 상대 경로.
      // 반환값:
      // - 기준 주소 뒤에 요청 경로를 붙인 문자열.
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    final message = await control.sendMessage(
      linkId: 17,
      clientMessageId: 'slot_request_001',
      body: '아침 복약을 확인해주세요.',
      messageKind: ChatMessageKind.slotCheckRequest,
      slotKey: 'morning',
    );

    expect(message.messageKind, ChatMessageKind.slotCheckRequest);
    expect(message.scheduleContext?.slotKey, 'morning');
    expect(message.scheduleContext?.medications.single.medicationId, 91);
    control.dispose();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 마지막으로 확인한 상대 메시지까지 읽음 처리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('마지막으로 확인한 상대 메시지까지 읽음 처리한다', () async {
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 연결별 읽음 요청의 마지막 메시지 식별자를 검사하고 읽음 갱신 결과를 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 갱신 건수와 읽음 시각의 HTTP 200 응답.
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/chat/links/17/read');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['through_message_id'], 52);
      return _jsonResponse({
        'success': true,
        'data': {
          'updated_count': 1,
          'through_message_id': 52,
          'read_at': '2026-08-23T03:01:00+00:00',
        },
      }, 200);
    });
    final control = ManageLinkedChat(
      userHash: 'caregiver-a',
      client: client,
      // 함수이름: chatUrlBuilder 콜백
      // 함수역할:
      // - 채팅 경로를 로컬 모의 서버 기준 주소에 연결한다.
      // 매개변수:
      // - path (String): 모의 서버 기준 주소 뒤에 붙일 채팅 API 상대 경로.
      // 반환값:
      // - 기준 주소 뒤에 요청 경로를 붙인 문자열.
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    await control.markRead(linkId: 17, throughMessageId: 52);

    control.dispose();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 서버 오류를 사용자 동작에 맞는 예외로 변환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('서버 오류를 사용자 동작에 맞는 예외로 변환한다', () async {
    final control = ManageLinkedChat(
      userHash: 'patient-a',
      client: MockClient(
        // 함수이름: MockClient 콜백
        // 함수역할:
        // - 활성 대화가 없는 서버 응답으로 채팅 동작 실패를 재현한다.
        // 매개변수:
        // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청. 이 대역에서는 직접 사용하지 않는다.
        // 반환값:
        // - 오류 상세가 있는 HTTP 404 응답.
        (request) async =>
            _jsonResponse({'detail': 'Active chat was not found.'}, 404),
      ),
      // 함수이름: chatUrlBuilder 콜백
      // 함수역할:
      // - 채팅 경로를 로컬 모의 서버 기준 주소에 연결한다.
      // 매개변수:
      // - path (String): 모의 서버 기준 주소 뒤에 붙일 채팅 API 상대 경로.
      // 반환값:
      // - 기준 주소 뒤에 요청 경로를 붙인 문자열.
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    await expectLater(
      control.requestHistory(linkId: 17),
      throwsA(
        isA<StateError>().having(
          // 함수이름: having 콜백
          // 함수역할:
          // - 오류의 사용자에게 안내할 오류 메시지를 추출해 해당 필드를 검증한다.
          // 매개변수:
          // - error (Object): 매처가 검사할 유형화된 예외.
          // 반환값:
          // - 예외의 message 값.
          (error) => error.message,
          'message',
          contains('404'),
        ),
      ),
    );
    control.dispose();
  });
}
