// 파일명: manage_linked_chat_control_test.dart
// 역할: 연동 채팅 REST 요청과 응답 변환을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';

http.Response _jsonResponse(Object body, int statusCode) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  const baseUrl = 'https://api.example.test/api/v1/chat';

  test('최근 채팅 기록을 사용자와 연동 범위로 조회한다', () async {
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

  test('클라이언트 요청 식별자와 여러 약 식별자를 함께 전송한다', () async {
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
      message.attachedMedicationContexts.map((item) => item.medicationId),
      [91, 92],
    );
    control.dispose();
  });

  test('약을 선택하지 않은 일반 메시지는 복약 식별자 없이 전송한다', () async {
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

  test('연동 환자의 활성 복약 목록을 채팅 선택 정보로 변환한다', () async {
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
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    final medications = await control.requestMedicationContexts(linkId: 17);

    expect(medications, hasLength(1));
    expect(medications.single.medicationId, 91);
    expect(medications.single.medicationName, '테스트정');
    expect(medications.single.dosagePerTime, '1정');
    control.dispose();
  });

  test('오늘 복약 상태를 시간대별 진행 카드로 변환한다', () async {
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

  test('복약 확인 요청은 시간대와 서버가 만든 일정 스냅샷을 유지한다', () async {
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

  test('마지막으로 확인한 상대 메시지까지 읽음 처리한다', () async {
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
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    await control.markRead(linkId: 17, throughMessageId: 52);

    control.dispose();
  });

  test('서버 오류를 사용자 동작에 맞는 예외로 변환한다', () async {
    final control = ManageLinkedChat(
      userHash: 'patient-a',
      client: MockClient(
        (request) async =>
            _jsonResponse({'detail': 'Active chat was not found.'}, 404),
      ),
      chatUrlBuilder: (path) => '$baseUrl$path',
    );

    await expectLater(
      control.requestHistory(linkId: 17),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('404'),
        ),
      ),
    );
    control.dispose();
  });
}
