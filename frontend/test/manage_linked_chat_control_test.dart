// 파일명: manage_linked_chat_control_test.dart
// 역할: 연동 채팅 REST 요청과 응답 변환을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/services/api_response_parser.dart';

// 함수이름: _jsonResponse
// 함수역할:
// - 응답 데이터를 UTF-8 JSON으로 인코딩하고 지정한 HTTP 상태와 콘텐츠 유형을 붙인다.
// 매개변수:
// - body (Object): JSON으로 인코딩 가능한 응답 본문.
// - statusCode (int): 모의 응답 HTTP 상태 코드.
// 반환값:
// - http.Response; UTF-8 JSON 응답. 인코딩할 수 없는 body는 오류를 발생시킨다.
http.Response _jsonResponse(Object body, int statusCode) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

// 함수이름: main
// 함수역할:
// - 채팅 기록·읽음·삭제·약 문맥·복용 확인·병원 및 이력 공유의 요청 계약과 잘못된 서버 응답 처리를 검사하는 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - void; 반환값 없음.
void main() {
  const baseUrl = 'https://api.example.test/api/v1/chat';

  // 함수이름: history share sends range only and restores server snapshot
  // 함수역할:
  // - 공유 요청은 날짜 범위와 메시지 메타데이터만 보내고, 실제 건수·날짜 스냅샷은 서버 응답에서 복원하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  test('history share sends range only and restores server snapshot', () async {
    final control = ManageLinkedChat(
      userHash: 'patient-a',
      chatUrlBuilder: (path) => '$baseUrl$path',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/chat/links/17/messages');
        expect(jsonDecode(request.body), {
          'client_message_id': 'history_001',
          'body': '복약 기록 공유',
          'message_kind': 'medication_history_share',
          'history_start_date': '2026-10-01',
          'history_end_date': '2026-10-07',
        });
        return _jsonResponse({
          'data': {
            'message_id': 5,
            'link_id': 17,
            'sender_hash': 'patient-a',
            'client_message_id': 'history_001',
            'body': '복약 기록 공유',
            'message_kind': 'medication_history_share',
            'created_at': '2026-10-07T01:00:00Z',
            'context': {
              'history_context': {
                'start_date': '2026-10-01',
                'end_date': '2026-10-07',
                'taken_count': 12,
                'skipped_count': 1,
                'unrecorded_count': 3,
              },
            },
          },
        }, 200);
      }),
    );
    addTearDown(control.dispose);
    final message = await control.sendMessage(
      linkId: 17,
      clientMessageId: 'history_001',
      body: '복약 기록 공유',
      messageKind: ChatMessageKind.medicationHistoryShare,
      historyStartDate: '2026-10-01',
      historyEndDate: '2026-10-07',
    );
    expect(message.messageKind, ChatMessageKind.medicationHistoryShare);
    expect(message.historyContext!.takenCount, 12);
    expect(message.historyContext!.endDate, DateTime.utc(2026, 10, 7));
  });

  // 함수이름: malformed history attachment preserves the entire history page
  // 함수역할:
  // - 이력 첨부의 건수 한 개가 잘못되어도 세 메시지와 페이지 행 수를 보존하고 해당 첨부만 버리며 본문을 유지하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  test(
    'malformed history attachment preserves the entire history page',
    () async {
      final control = ManageLinkedChat(
        userHash: 'patient-a',
        client: MockClient(
          (request) async => _jsonResponse({
            'data': [
              for (var id = 1; id <= 3; id++)
                {
                  'message_id': id,
                  'link_id': 17,
                  'sender_hash': 'patient-a',
                  'client_message_id': 'history_$id',
                  'body': 'Shared records $id',
                  'message_kind': 'medication_history_share',
                  'created_at': '2026-10-07T01:00:00Z',
                  'context': {
                    'history_context': {
                      'start_date': '2026-10-01',
                      'end_date': '2026-10-07',
                      'taken_count': id == 2 ? 'invalid' : 0,
                      'skipped_count': 0,
                      'unrecorded_count': 0,
                    },
                  },
                },
            ],
          }, 200),
        ),
      );
      addTearDown(control.dispose);
      final page = await control.requestHistory(linkId: 17);
      expect(page, hasLength(3));
      expect(ChatHistoryPage.rowCountOf(page), 3);
      expect(page[0].historyContext, isNotNull);
      expect(page[1].historyContext, isNull);
      expect(page[1].body, 'Shared records 2');
      expect(page[2].historyContext, isNotNull);
    },
  );

  // 함수이름: unread summary uses read-only endpoint and preserves exact count
  // 함수역할:
  // - 읽지 않은 메시지 요약은 GET 전용 경로를 사용하고 120건과 첫 메시지 ID 41을 축소하거나 읽음 처리하지 않고 보존하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  test(
    'unread summary uses read-only endpoint and preserves exact count',
    () async {
      final control = ManageLinkedChat(
        userHash: 'patient-a',
        chatUrlBuilder: (path) => '$baseUrl$path',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/chat/links/17/unread-count');
          return _jsonResponse({
            'success': true,
            'data': {'unread_count': 120, 'first_unread_message_id': 41},
          }, 200);
        }),
      );
      final unread = await control.requestUnreadSummary(linkId: 17);
      expect(unread.count, 120);
      expect(unread.firstMessageId, 41);
      control.dispose();
    },
  );
  for (final invalid in [-1, '2', null]) {
    // 함수이름: invalid unread count does not become zero: $invalid
    // 함수역할:
    // - 잘못된 unread_count 값은 읽지 않은 메시지 0건으로 숨기지 않고 StateError로 거절하는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    test('invalid unread count does not become zero: $invalid', () async {
      final control = ManageLinkedChat(
        userHash: 'patient-a',
        client: MockClient(
          (_) async => _jsonResponse({
            'data': {'unread_count': invalid},
          }, 200),
        ),
      );
      await expectLater(
        control.requestUnreadSummary(linkId: 17),
        throwsStateError,
      );
      control.dispose();
    });
  }

  // 함수이름: hospital share sends IDs and parses dated server context
  // 함수역할:
  // - 병원 공유는 ID·조회일만 전송하고 서버의 이름·진료과·날짜를 복원하며, 메시지 숨김·삭제 시 병원 문맥을 제거하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  test('hospital share sends IDs and parses dated server context', () async {
    final control = ManageLinkedChat(
      userHash: 'patient-a',
      chatUrlBuilder: (path) => '$baseUrl$path',
      client: MockClient((request) async {
        expect(jsonDecode(request.body), {
          'client_message_id': 'hospital_001',
          'body': '병원 공유',
          'message_kind': 'hospital_share',
          'hospital_id': 'A123',
          'hospital_schedule_date': '2026-10-05',
        });
        return _jsonResponse({
          'success': true,
          'data': {
            'message_id': 1,
            'link_id': 17,
            'sender_hash': 'patient-a',
            'client_message_id': 'hospital_001',
            'body': '병원 공유',
            'message_kind': 'hospital_share',
            'created_at': '2026-09-28T01:00:00Z',
            'context': {
              'hospital_context': {
                'hospital_id': 'A123',
                'name': '확인된 병원',
                'address': '서울',
                'telephone': '02-000-0000',
                'latitude': 37.55,
                'longitude': 126.92,
                'schedule_date': '2026-10-05',
                'today_hours': '10:00 - 13:00',
                'departments': ['내과'],
                'source_updated_at': '2026-09-28T01:00:00Z',
              },
            },
          },
        }, 200);
      }),
    );
    final message = await control.sendMessage(
      linkId: 17,
      clientMessageId: 'hospital_001',
      body: '병원 공유',
      messageKind: ChatMessageKind.hospitalShare,
      hospitalId: 'A123',
      hospitalScheduleDate: '2026-10-05',
    );
    expect(message.messageKind, ChatMessageKind.hospitalShare);
    expect(message.pharmacyContext, isNull);
    expect(message.hospitalContext!.name, '확인된 병원');
    expect(message.hospitalContext!.departments, ['내과']);
    expect(message.hospitalContext!.scheduleDate, DateTime(2026, 10, 5));
    expect(message.copyWith(deletedForEveryone: true).hospitalContext, isNull);
    expect(message.copyWith(hiddenForMe: true).hospitalContext, isNull);
    control.dispose();
  });

  // 함수이름: dose confirmation uses a dedicated endpoint with original date and selected IDs
  // 함수역할:
  // - 일반 메시지와 구분된 복용 확인 POST에 원래 날짜·시간대·선택 약·요청 ID를 보내고 서버의 확인 메시지를 복원하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  test(
    'dose confirmation uses a dedicated endpoint with original date and selected IDs',
    () async {
      final control = ManageLinkedChat(
        userHash: 'patient-a',
        chatUrlBuilder: (path) => '$baseUrl$path',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/chat/links/17/medication-taken');
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {
            'client_message_id': 'taken-request-01',
            'schedule_date': '2026-09-21',
            'slot_key': 'morning',
            'medication_ids': [91],
          });
          return _jsonResponse({
            'success': true,
            'data': {
              'message_id': 1,
              'link_id': 17,
              'sender_hash': 'patient-a',
              'client_message_id': 'taken-request-01',
              'body': '복용을 기록했습니다.',
              'created_at': '2026-09-21T00:00:00Z',
            },
            'schedules': [],
          }, 200);
        }),
      );
      final result = await control.recordMedicationTaken(
        linkId: 17,
        clientMessageId: 'taken-request-01',
        scheduleDate: '2026-09-21',
        slotKey: 'morning',
        medicationIds: [91],
      );
      expect(result.message.body, '복용을 기록했습니다.');
      control.dispose();
    },
  );

  // 함수이름: deletion sends explicit IDs and scope and surfaces server refusal
  // 함수역할:
  // - 삭제 POST가 명시적인 메시지 ID 목록과 everyone 범위를 전달하며, 동일 요청이 HTTP 409로 거절되면 StateError로 알리는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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

  // 함수이름: redacted messages allow empty text and discard medication context
  // 함수역할:
  // - 삭제 메시지의 빈 본문을 허용하되 재삭제를 막고, 오래된 메시지의 전체 삭제 권한을 거절하며 삭제 복사본의 본문·약 문맥을 제거하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 기대 결과와 다르면 테스트가 실패한다.
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

  // 함수이름: 최근 채팅 기록을 사용자와 연동 범위로 조회한다
  // 함수역할:
  // - 현재 사용자와 연동 17, 이전 ID 42, 제한 25를 기록 GET에 전달하고 상대의 읽지 않은 메시지 본문·ID·읽음 상태를 복원하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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

  // 함수이름: 클라이언트 요청 식별자와 여러 약 식별자를 함께 전송한다
  // 함수역할:
  // - 메시지 재전송 ID와 단일·복수 약 식별자를 함께 전송하고 응답의 두 약 문맥을 모두 보존하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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

  // 함수이름: 약을 선택하지 않은 일반 메시지는 복약 식별자 없이 전송한다
  // 함수역할:
  // - 약을 선택하지 않은 일반 메시지 본문에는 medication_id와 medication_ids를 넣지 않고 반환 문맥도 null로 유지하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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

  // 함수이름: 연동 환자의 활성 복약 목록을 채팅 선택 정보로 변환한다
  // 함수역할:
  // - 연동별 활성 약 GET을 사용하여 서버의 약 ID·이름·복용량을 채팅에서 선택 가능한 문맥으로 복원하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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

  // 함수이름: 오늘 복약 상태를 시간대별 진행 카드로 변환한다
  // 함수역할:
  // - 보호자 범위의 일정 문맥 GET 응답에서 시간대·완료 건수·전체 건수·확인 요청 가능 여부와 약 목록을 복원하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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

  // 함수이름: 복약 확인 요청은 시간대와 서버가 만든 일정 스냅샷을 유지한다
  // 함수역할:
  // - 확인 요청 메시지의 종류와 아침 시간대는 전송하되 약국 ID는 보내지 않고, 응답의 서버 일정 스냅샷을 유지하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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

  // 함수이름: 마지막으로 확인한 상대 메시지까지 읽음 처리한다
  // 함수역할:
  // - 연동별 읽음 POST에 마지막 확인 메시지 ID 52를 전달하여 명시한 경계까지만 읽음 처리하도록 요청하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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

  // 함수이름: 서버 오류를 사용자 동작에 맞는 예외로 변환한다
  // 함수역할:
  // - 활성 대화가 없다는 HTTP 404 응답은 정상 빈 기록 대신 상태 코드를 포함한 StateError로 드러내는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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
          // - error (StateError): 매처가 검사할 사용자 동작 오류.
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

  // Function Name: 거부된 응답은 문구를 유지하고 상태 코드를 함께 전달한다
  // Description:
  // - Preserve the localized operation message, HTTP 403 status, and server detail in ApiRequestException when history access is denied.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('거부된 응답은 문구를 유지하고 상태 코드를 함께 전달한다', () async {
    final control = ManageLinkedChat(
      userHash: 'patient-a',
      client: MockClient(
        (request) async => _jsonResponse({
          'detail': 'An active patient-caregiver link is required.',
        }, 403),
      ),
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    await expectLater(
      control.requestHistory(linkId: 17),
      throwsA(
        isA<ApiRequestException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having(
              (error) => error.message,
              'message',
              '채팅 기록을 불러오지 못했습니다. (403): '
                  'An active patient-caregiver link is required.',
            ),
      ),
    );
    control.dispose();
  });

  // Function Name: 해석할 수 없는 행 하나가 기록 페이지 전체를 실패시키지 않는다
  // Description:
  // - Skip a row missing sender/time while returning the other 49 messages in order; preserve the original 50-row page count, with ordinary lists falling back to their length.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('해석할 수 없는 행 하나가 기록 페이지 전체를 실패시키지 않는다', () async {
    // Function Name: row
    // Description:
    // - Build a valid history row so one malformed sibling can be isolated in a full server page.
    // Parameters:
    // - id (int): message ID and suffix for client ID and body.
    // Returns:
    // - Map<String, Object?>; complete link-17 message payload with a fixed timestamp.
    Map<String, Object?> row(int id) => {
      'message_id': id,
      'link_id': 17,
      'sender_hash': 'caregiver-a',
      'client_message_id': 'message_$id',
      'body': '메시지 $id',
      'created_at': '2026-08-23T01:00:00+00:00',
    };
    final control = ManageLinkedChat(
      userHash: 'patient-a',
      client: MockClient(
        (request) async => _jsonResponse({
          'success': true,
          'data': [
            for (var id = 1; id <= 50; id++)
      // Row 25 omits the required sender and creation timestamp.
              if (id == 25)
                {'message_id': id, 'link_id': 17, 'body': '깨진 행'}
              else
                row(id),
          ],
        }, 200),
      ),
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    final page = await control.requestHistory(linkId: 17);

    expect(page, hasLength(49));
    expect(page.map((message) => message.messageId), isNot(contains(25)));
    expect(page.first.messageId, 1);
    expect(page.last.messageId, 50);
    expect(ChatHistoryPage.rowCountOf(page), 50);
    // A plain list without a server row count uses its own length.
    expect(ChatHistoryPage.rowCountOf(page.toList()), 49);
    control.dispose();
  });
}
