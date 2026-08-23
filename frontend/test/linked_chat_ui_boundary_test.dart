// 파일명: linked_chat_ui_boundary_test.dart
// 역할: 채팅 화면의 재전송 중복 방지와 큰 글씨 레이아웃을 검증한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/linked_chat_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/services/linked_chat_realtime_service.dart';

class _RetryChatControl extends ManageLinkedChat {
  final List<String> clientMessageIds = [];
  int sendAttempts = 0;
  int detailRequests = 0;

  _RetryChatControl()
    : super(
        userHash: 'patient-a',
        client: MockClient((request) async => http.Response('{}', 200)),
      );

  @override
  Future<List<ChatMessage>> requestHistory({
    required int linkId,
    int? beforeMessageId,
    int limit = 50,
  }) async => const [];

  @override
  Future<List<ChatMedicationContext>> requestMedicationContexts({
    required int linkId,
  }) async => const [
    ChatMedicationContext(
      medicationId: 91,
      medicationName: '테스트정',
      dosagePerTime: '1정',
      scheduleSlotKeys: ['morning'],
    ),
  ];

  @override
  Future<MedicationDetail> requestMedicationDetail({
    required int linkId,
    required int medicationId,
  }) async {
    detailRequests += 1;
    return const MedicationDetail(
      id: 91,
      itemName: '테스트정',
      efficacy: '테스트 효능',
      usageMethod: '하루 한 번 복용하세요.',
      warning: '주의사항을 확인하세요.',
      dosagePerTime: '1정',
    );
  }

  @override
  Future<ChatMessage> sendMessage({
    required int linkId,
    required String clientMessageId,
    required String body,
    required int medicationId,
  }) async {
    sendAttempts += 1;
    clientMessageIds.add(clientMessageId);
    if (sendAttempts == 1) {
      throw StateError('temporary failure');
    }
    return ChatMessage(
      messageId: 1,
      linkId: linkId,
      senderHash: 'patient-a',
      clientMessageId: clientMessageId,
      body: body,
      createdAt: DateTime.utc(2026, 8, 23, 9),
      medicationContext: const ChatMedicationContext(
        medicationId: 91,
        medicationName: '테스트정',
        dosagePerTime: '1정',
      ),
    );
  }

  @override
  Future<void> markRead({
    required int linkId,
    required int throughMessageId,
  }) async {}
}

class _FakeRealtimeService extends LinkedChatRealtimeService {
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<LinkedChatConnectionState> _states =
      StreamController<LinkedChatConnectionState>.broadcast();

  _FakeRealtimeService()
    : super(
        linkId: 17,
        userHash: 'patient-a',
        authenticationClient: AuthenticatedApiClient(
          inner: MockClient((request) async => http.Response('{}', 200)),
          tokenProvider: () async => null,
          appCheckTokenProvider: () async => null,
          trustedBaseUri: Uri.parse('http://localhost/api/v1/medication'),
        ),
      );

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  Stream<LinkedChatConnectionState> get states => _states.stream;

  @override
  Future<void> start() async {
    _states.add(LinkedChatConnectionState.connected);
  }

  @override
  Future<void> stop() async {
    _states.add(LinkedChatConnectionState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
    await _states.close();
    authenticationClient.close();
  }
}

void main() {
  testWidgets('큰 글씨에서도 메시지 실패 재시도는 같은 요청 식별자를 사용한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final control = _RetryChatControl();
    final realtimeService = _FakeRealtimeService();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.6),
          ),
          child: LinkedChatUI(
            linkId: 17,
            currentUserHash: 'patient-a',
            patientHash: 'patient-a',
            peerName: '보호자 이름이 매우 긴 경우',
            control: control,
            realtimeService: realtimeService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('chatMedicationSelector')));
    await tester.pumpAndSettle();
    expect(find.text('대화할 약 선택'), findsOneWidget);
    expect(find.text('아침'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('scheduleMedicationSelectionOption_91')),
    );
    await tester.pumpAndSettle();
    final messageField = tester.widget<TextField>(find.byType(TextField));
    expect(messageField.controller?.text, isEmpty);
    expect(messageField.decoration?.hintText, '예: 테스트정 복용을 완료했어요.');
    await tester.enterText(find.byType(TextField), '저녁 약을 복용했어요.');
    await tester.pump();
    final sendButtonFinder = find.byKey(const ValueKey('chatSendButton'));
    final firstSendButton = tester.widget<IconButton>(sendButtonFinder);
    expect(firstSendButton.onPressed, isNotNull);
    firstSendButton.onPressed!();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('메시지를 보내지 못했습니다. 다시 눌러주세요.'), findsOneWidget);
    final retryButton = tester.widget<IconButton>(sendButtonFinder);
    expect(retryButton.onPressed, isNotNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '저녁 약을 복용했어요.',
    );
    retryButton.onPressed!();
    await tester.pumpAndSettle();

    expect(control.sendAttempts, 2);
    expect(control.clientMessageIds, hasLength(2));
    expect(control.clientMessageIds[0], control.clientMessageIds[1]);
    expect(find.text('저녁 약을 복용했어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('테스트정'));
    await tester.pumpAndSettle();
    expect(control.detailRequests, 1);
    expect(find.text('약 상세정보'), findsOneWidget);
    expect(find.text('테스트 효능'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await realtimeService.dispose();
    control.dispose();
  });
}
