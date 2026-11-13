// 파일명: chat_lifecycle_race_test.dart
// 역할: 채팅 화면 가림·백그라운드·지연 응답에서 읽음과 스크롤 상태가 보존되는지 검사한다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/linked_chat_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/services/linked_chat_realtime_service.dart';

// 함수이름: main
// 함수역할:
// - 화면 표시 상태·계정 및 연동 전환·지연 전송과 조회 응답이 읽음·초안·스크롤에 미치는 영향을 검사하는 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - void; 반환값 없음.
void main() {
  for (final fail in [false, true]) {
    // 함수이름: empty and duplicate sends stay inert after disposal: $fail
    // 함수역할:
    // - 공백 전송은 무시하고 대기 중 반복 입력은 한 번만 보내며, 화면 해제 뒤 전송 성공·실패가 와도 추가 요청이나 화면 예외를 만들지 않는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets('empty and duplicate sends stay inert after disposal: $fail', (
      tester,
    ) async {
      final flow = _ChatFlow();
      addTearDown(() => flow.close(tester));
      await flow.open(tester);
      final send = find.byKey(const ValueKey('chatSendButton'));
      await tester.enterText(find.byType(TextField), '   \n  ');
      await tester.pump();
      await tester.tap(send);
      expect(flow.sendRequests, 0);
      final response = Completer<Map<String, dynamic>>();
      flow.nextSend = response;
      await tester.enterText(find.byType(TextField), '한 번만 전송');
      await tester.pump();
      await tester.tap(send);
      await tester.tap(send);
      await tester.pump();
      expect(flow.sendRequests, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      if (fail) {
        response.completeError(StateError('늦은 전송 실패'));
      } else {
        response.complete(_message(100));
      }
      await tester.pumpAndSettle();
      expect(flow.sendRequests, 1);
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: read receipt before send response never shows unread again
  // 함수역할:
  // - 전송 응답보다 먼저 받은 읽음 이벤트를 새 메시지에 적용하여 응답 완료 후에도 미확인 배지를 다시 표시하지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('read receipt before send response never shows unread again', (
    tester,
  ) async {
    final flow = _ChatFlow();
    addTearDown(() => flow.close(tester));
    await flow.open(tester);
    final response = Completer<Map<String, dynamic>>();
    flow.nextSend = response;
    await tester.enterText(find.byType(TextField), '먼저 읽은 메시지');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chatSendButton')));
    await tester.pump();
    expect(flow.sendRequests, 1);
    flow.realtime.emit({
      'type': 'chat_read',
      'link_id': 17,
      'reader_hash': 'caregiver-a',
      'through_message_id': 100,
      'read_at': '2026-10-10T03:01:00Z',
    });
    await tester.pump();
    response.complete({..._message(100), 'body': '먼저 읽은 메시지'});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-message-100')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-unread-receipt-100')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final outgoingScope in [
    (name: 'account', userHash: 'patient-b', linkId: 17),
    (name: 'link', userHash: 'patient-a', linkId: 18),
  ]) {
    for (final fails in [false, true]) {
      // Function Name: ${outgoingScope.name} change ignores late send completion: failure=$fails
      // Description:
      // - After switching account or link, a late old send success/failure cannot clear the new draft, insert its message, display an old error, or send through the new scope.
      // Parameters:
      // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
      // Returns:
      // - Future<void>; completes after the asynchronous assertions.
      testWidgets(
        '${outgoingScope.name} change ignores late send completion: failure=$fails',
        (tester) async {
          final previous = _ChatFlow();
          final next = _ChatFlow(
            userHash: outgoingScope.userHash,
            linkId: outgoingScope.linkId,
          );
          addTearDown(() => previous.close(tester));
          addTearDown(() => next.close(tester));
          await previous.open(tester);
          final delayed = Completer<Map<String, dynamic>>();
          previous.nextSend = delayed;
          await tester.enterText(find.byType(TextField), 'Old outgoing draft');
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('chatSendButton')));
          await tester.pump();
          expect(previous.sendRequests, 1);
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: previous.navigator,
              home: LinkedChatUI(
                linkId: outgoingScope.linkId,
                currentUserHash: outgoingScope.userHash,
                patientHash: outgoingScope.userHash,
                control: next.control,
                apiClient: next.authentication,
                realtimeService: next.realtime,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'New private draft');
          if (fails) {
            delayed.completeError(StateError('Old account transport failure'));
          } else {
            delayed.complete({..._message(100), 'body': 'Old outgoing draft'});
          }
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'New private draft',
          );
          expect(find.byKey(const ValueKey('chat-message-100')), findsNothing);
          expect(find.text('메시지를 보내지 못했습니다. 다시 눌러주세요.'), findsNothing);
          expect(next.sendRequests, 0);
          expect(previous.sendRequests, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final scope in [
    (
      name: 'account',
      userHash: 'patient-b',
      linkId: 17,
      patientHash: 'patient-a',
    ),
    (name: 'link', userHash: 'patient-a', linkId: 18, patientHash: 'patient-a'),
    (
      name: 'patient',
      userHash: 'patient-a',
      linkId: 17,
      patientHash: 'patient-b',
    ),
  ]) {
    // Function Name: chat session replaces stale ${scope.name} state and ignores late history
    // Description:
    // - Changing account, link, or patient replaces the old draft and history owner; late old pages and realtime events cannot publish or trigger reads in the new conversation.
    // Parameters:
    // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    testWidgets(
      'chat session replaces stale ${scope.name} state and ignores late history',
      (tester) async {
        final previous = _ChatFlow()..history = [_message(1)];
        final next = _ChatFlow(userHash: scope.userHash, linkId: scope.linkId)
          ..history = [
            _message(2, sender: scope.userHash, linkId: scope.linkId),
          ];
        addTearDown(() => previous.close(tester));
        addTearDown(() => next.close(tester));
        await previous.open(tester);
        await tester.enterText(find.byType(TextField), 'Private draft');
        final delayed = Completer<List<Map<String, dynamic>>>();
        previous.nextHistory = delayed;
        await tester.pump(const Duration(seconds: 12));
        expect(previous.historyRequests, 2);
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: previous.navigator,
            home: LinkedChatUI(
              linkId: scope.linkId,
              currentUserHash: scope.userHash,
              patientHash: scope.patientHash,
              control: next.control,
              apiClient: next.authentication,
              realtimeService: next.realtime,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(find.text('시험 메시지 2'), findsOneWidget);
        delayed.complete([
          for (var id = 100; id < 150; id++)
            _message(id, sender: 'caregiver-a'),
        ]);
        previous.realtime.emit({
          'type': 'chat_message',
          'message': _message(200, sender: 'caregiver-a'),
        });
        await tester.pumpAndSettle();
        expect(previous.historyRequests, 2);
        expect(previous.readRequests, isEmpty);
        expect(find.text('시험 메시지 149'), findsNothing);
        expect(find.text('시험 메시지 200'), findsNothing);
        expect(find.text('시험 메시지 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  // Function Name: same-scope settings and peer updates preserve the draft
  // Description:
  // - Changing peer display name and language within the same conversation preserves the composer draft and avoids restarting history lookup.
  // Parameters:
  // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('same-scope settings and peer updates preserve the draft', (
    tester,
  ) async {
    final flow = _ChatFlow();
    addTearDown(() => flow.close(tester));
    await flow.open(tester);
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    final requestsBefore = flow.historyRequests;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: flow.navigator,
        home: LinkedChatUI(
          linkId: 17,
          currentUserHash: 'patient-a',
          patientHash: 'patient-a',
          peerName: 'Updated peer',
          userSetting: const UserSetting(language: 'en'),
          control: flow.control,
          apiClient: flow.authentication,
          realtimeService: flow.realtime,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep this draft',
    );
    expect(find.textContaining('Updated peer'), findsWidgets);
    expect(flow.historyRequests, requestsBefore);
  });

  for (final background in [false, true]) {
    // 함수이름: 가려진 채팅은 읽음 처리하지 않는다: background=$background
    // 함수역할:
    // - 다른 경로에 가려지거나 앱이 백그라운드에 있으면 상대 메시지를 읽음 처리하지 않고, 채팅으로 돌아온 뒤에만 읽음 요청을 보내는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets('가려진 채팅은 읽음 처리하지 않는다: background=$background', (tester) async {
      final flow = _ChatFlow();
      await flow.open(tester);
      addTearDown(() => flow.close(tester));
      if (background) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else {
        unawaited(
          flow.navigator.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('다른 화면')),
            ),
          ),
        );
      }
      await tester.pumpAndSettle();
      flow.history = [_message(1, sender: 'caregiver-a')];
      flow.realtime.emit({
        'type': 'chat_message',
        'message': flow.history.single,
      });
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(flow.readRequests, isEmpty);
      if (background) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } else {
        flow.navigator.currentState!.pop();
      }
      await tester.pumpAndSettle();
      expect(flow.readRequests, contains(1));
    });
  }

  // 함수이름: 늦게 도착한 이력은 읽음 표시를 되돌리지 않는다
  // 함수역할:
  // - 실시간 읽음 표시를 적용한 뒤 이전 이력 응답이 도착해도 미확인 배지를 되살리지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('늦게 도착한 이력은 읽음 표시를 되돌리지 않는다', (tester) async {
    final flow = _ChatFlow()..history = [_message(1)];
    await flow.open(tester);
    addTearDown(() => flow.close(tester));
    expect(find.byKey(const ValueKey('chat-unread-receipt-1')), findsOneWidget);
    final delayed = Completer<List<Map<String, dynamic>>>();
    flow.nextHistory = delayed;
    await tester.pump(const Duration(seconds: 12));
    flow.realtime.emit({
      'type': 'chat_read',
      'reader_hash': 'caregiver-a',
      'through_message_id': 1,
      'read_at': '2026-09-24T03:01:00Z',
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-unread-receipt-1')), findsNothing);
    delayed.complete(flow.history);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-unread-receipt-1')), findsNothing);
  });

  // 함수이름: 이전 대화를 읽는 동안 조회와 수신이 스크롤을 빼앗지 않는다
  // 함수역할:
  // - 이전 대화를 읽는 위치에서는 주기적 조회와 새 메시지가 스크롤 오프셋 600을 바꾸거나 아직 보지 않은 새 메시지를 읽음 처리하지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('이전 대화를 읽는 동안 조회와 수신이 스크롤을 빼앗지 않는다', (tester) async {
    final flow = _ChatFlow()
      ..history = List.generate(35, (i) => _message(i + 1));
    await flow.open(tester);
    addTearDown(() => flow.close(tester));
    final list = tester.widget<ListView>(find.byType(ListView).first);
    final controller = list.controller!;
    controller.jumpTo(600);
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(controller.offset, 600);
    flow.realtime.emit({
      'type': 'chat_message',
      'message': _message(36, sender: 'caregiver-a'),
    });
    await tester.pumpAndSettle();
    expect(controller.offset, 600);
    expect(flow.readRequests, isNot(contains(36)));
  });

  // 함수이름: 최신 대화를 보고 있으면 새 메시지를 따라간다
  // 함수역할:
  // - 최신 대화를 보는 상태에서는 새 메시지 도착 후에도 최신 위치를 유지하고 새 본문을 표시하며 해당 메시지를 읽음 처리하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('최신 대화를 보고 있으면 새 메시지를 따라간다', (tester) async {
    final flow = _ChatFlow()
      ..history = List.generate(35, (i) => _message(i + 1));
    await flow.open(tester);
    addTearDown(() => flow.close(tester));
    final controller = tester
        .widget<ListView>(find.byType(ListView).first)
        .controller!;
    expect(controller.position.extentBefore, 0);
    flow.realtime.emit({
      'type': 'chat_message',
      'message': _message(36, sender: 'caregiver-a'),
    });
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(controller.position.extentBefore, 0);
    expect(find.text('시험 메시지 36'), findsOneWidget);
    expect(flow.readRequests, contains(36));
  });
}

// Function Name: _message
// Description:
// - Create a non-sensitive wire message with explicit sender and conversation identity.
// Parameters:
// - id (int): message number and suffix used for body/client ID.
// - sender (String): sender account, default patient-a.
// - linkId (int): conversation scope, default 17.
// Returns:
// - Map<String, dynamic>; complete message payload at the fixed test timestamp.
Map<String, dynamic> _message(
  int id, {
  String sender = 'patient-a',
  int linkId = 17,
}) => {
  'message_id': id,
  'link_id': linkId,
  'sender_hash': sender,
  'client_message_id': 'audit_message_$id',
  'body': '시험 메시지 $id',
  'created_at': '2026-09-24T03:00:00Z',
};

// Class Name: _ChatFlow
// Role: Connects real chat UI/control to controlled HTTP and realtime boundaries.
// Responsibilities:
// - Record history, send, and read operations while independently delaying the next history or send response.
// Attributes:
// - userHash (String), linkId (int): constructor-selected adapter scope.
// - navigator (GlobalKey<NavigatorState>): controls covering routes in the test app.
// - readRequests (List<int>): acknowledged message boundaries.
// - historyRequests, sendRequests (int): request counters.
// - history (List<Map<String, dynamic>>): default server history.
// - nextHistory (Completer<List<Map<String, dynamic>>>?), nextSend (Completer<Map<String, dynamic>>?): one-shot response gates.
// - client (MockClient), authentication (AuthenticatedApiClient): owned HTTP boundaries.
// - control (ManageLinkedChat), realtime (_Realtime): conversation adapters.
class _ChatFlow {
  final String userHash;
  final int linkId;
  final navigator = GlobalKey<NavigatorState>();
  final readRequests = <int>[];
  int historyRequests = 0;
  int sendRequests = 0;
  List<Map<String, dynamic>> history = [];
  Completer<List<Map<String, dynamic>>>? nextHistory;
  Completer<Map<String, dynamic>>? nextSend;
  late final MockClient client;
  late final AuthenticatedApiClient authentication;
  late final ManageLinkedChat control;
  late final _Realtime realtime;

  // Function Name: _ChatFlow
  // Description:
  // - Create the HTTP, authentication, and realtime adapters for the requested conversation scope.
  // Parameters:
  // - userHash (String): active account, default patient-a.
  // - linkId (int): adapter conversation ID, default 17.
  // Returns:
  // - _ChatFlow; isolated request logs, no visible screen yet.
  _ChatFlow({this.userHash = 'patient-a', this.linkId = 17}) {
    client = MockClient(_respond);
    authentication = AuthenticatedApiClient(
      inner: client,
      tokenProvider: () async => null,
      appCheckTokenProvider: () async => null,
      trustedBaseUri: Uri.parse('http://localhost/api/v1/medication'),
    );
    control = ManageLinkedChat(userHash: userHash, client: client);
    realtime = _Realtime(authentication, linkId: linkId, userHash: userHash);
  }

  // Function Name: _respond
  // Description:
  // - Consume the next optional send/history gate, record relevant requests, and return successful JSON; unmatched endpoints return empty data.
  // Parameters:
  // - request (http.Request): intercepted messages/read/context request.
  // Returns:
  // - Future<http.Response>; JSON 200 response; gated errors or malformed request bodies propagate.
  Future<http.Response> _respond(http.Request request) async {
    Object data = <Object>[];
    if (request.url.path.endsWith('/messages') && request.method == 'POST') {
      sendRequests++;
      final delayed = nextSend;
      nextSend = null;
      final outgoing = jsonDecode(request.body) as Map<String, dynamic>;
      data = delayed == null
          ? {..._message(100, sender: userHash, linkId: linkId), ...outgoing}
          : await delayed.future;
    } else if (request.url.path.endsWith('/messages')) {
      historyRequests++;
      final delayed = nextHistory;
      nextHistory = null;
      data = delayed == null ? history : await delayed.future;
    } else if (request.url.path.endsWith('/read')) {
      readRequests.add(jsonDecode(request.body)['through_message_id'] as int);
    }
    return http.Response(
      jsonEncode({'success': true, 'data': data}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  // 함수이름: open
  // 함수역할:
  // - 앱을 전경으로 복원하고 기본 환자 patient-a·연동 17 화면에 이 fixture의 어댑터를 연결하여 초기 배치를 완료한다.
  // 매개변수:
  // - tester (WidgetTester): 앱 수명주기와 화면 표시를 제어한다.
  // 반환값:
  // - Future<void>; 초기 화면이 안정되면 완료한다.
  Future<void> open(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: LinkedChatUI(
          linkId: 17,
          currentUserHash: 'patient-a',
          patientHash: 'patient-a',
          control: control,
          apiClient: authentication,
          realtimeService: realtime,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // 함수이름: close
  // 함수역할:
  // - 중지된 앱 상태를 전경으로 복원하고 화면·실시간 대역·컨트롤·인증 클라이언트를 순서대로 정리한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 제거와 수명주기 상태 복원을 수행한다.
  // 반환값:
  // - Future<void>; 대역을 해제하고 전경 상태로 돌아오면 완료한다.
  Future<void> close(WidgetTester tester) async {
    if (tester.binding.lifecycleState == AppLifecycleState.paused) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await realtime.dispose();
    control.dispose();
    authentication.close();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

// Class Name: _Realtime
// Role: Realtime subclass with a test-controlled message stream and no socket startup.
// Responsibilities:
// - Inject message/read events independently from HTTP completions while retaining inherited cleanup.
// Attributes:
// - _events (StreamController<Map<String, dynamic>>): owned broadcast event source.
class _Realtime extends LinkedChatRealtimeService {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  // Function Name: _Realtime
  // Description:
  // - Bind the realtime adapter to the supplied authentication client and conversation scope.
  // Parameters:
  // - client (AuthenticatedApiClient): authentication boundary passed to the base service.
  // - linkId (int): conversation ID, default 17.
  // - userHash (String): account identity, default patient-a.
  // Returns:
  // - _Realtime; events are manually driven, with start/stop overridden as no-ops.
  _Realtime(
    AuthenticatedApiClient client, {
    super.linkId = 17,
    super.userHash = 'patient-a',
  }) : super(authenticationClient: client);
  // 함수이름: events
  // 함수역할:
  // - 테스트가 제어하는 메시지 이벤트 스트림을 노출한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Stream<Map<String, dynamic>>; fixture가 소유하는 브로드캐스트 스트림.
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  // 함수이름: emit
  // 함수역할:
  // - 지정한 메시지·읽음 이벤트를 가짜 실시간 스트림에 추가한다.
  // 매개변수:
  // - event (Map<String, dynamic>): 화면에 전달할 서버 이벤트 payload.
  // 반환값:
  // - void; 반환값 없음.
  void emit(Map<String, dynamic> event) => _events.add(event);
  // 함수이름: start
  // 함수역할:
  // - 소켓이나 타이머를 만들지 않고 시작 호출을 완료한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 즉시 완료한다.
  @override
  Future<void> start() async {}
  // 함수이름: stop
  // 함수역할:
  // - 소켓 상태를 변경하지 않고 중지 호출을 완료한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 즉시 완료한다.
  @override
  Future<void> stop() async {}
  // 함수이름: dispose
  // 함수역할:
  // - 가짜 이벤트 스트림을 닫고 상위 실시간 서비스 자원도 정리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 스트림과 상위 서비스 해제 후 완료한다.
  @override
  Future<void> dispose() async {
    await _events.close();
    await super.dispose();
  }
}
