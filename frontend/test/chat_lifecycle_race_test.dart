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
// 함수역할: 화면 노출과 응답 순서에 따른 채팅 회귀 사례를 등록한다.
// 매개변수: 없음. 반환값: 없음.
void main() {
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
    // Verifies each scope identity change replaces drafts, subscriptions and pending recovery ownership.
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

  // Verifies same-conversation display changes retain composer and authenticated adapter lifetime.
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
    // 함수이름: 보이지 않는 채팅 읽음 차단 테스트
    // 함수역할: 다른 화면·백그라운드에서는 읽지 않고 채팅으로 돌아오면 읽음 처리한다.
    // 매개변수: tester 화면 시험 도구. 반환값: 비동기 검증 완료.
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

  // 함수이름: 읽음 응답 역전 테스트
  // 함수역할: 실시간 읽음 이벤트 이후 오래된 이력 응답이 와도 읽음 표시를 되돌리지 않는다.
  // 매개변수: tester 화면 시험 도구. 반환값: 비동기 검증 완료.
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

  // 함수이름: 이전 대화 스크롤 유지 테스트
  // 함수역할: 이전 메시지를 읽는 동안 주기적 조회와 새 메시지가 강제로 하단 이동하지 않는다.
  // 매개변수: tester 화면 시험 도구. 반환값: 비동기 검증 완료.
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

  // 함수이름: 최신 대화 수신 스크롤 테스트
  // 함수역할: 하단에서 대화 중이면 새 메시지가 도착할 때 계속 최신 메시지를 보여준다.
  // 매개변수: tester 화면 시험 도구. 반환값: 비동기 검증 완료.
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

// 함수이름: _message
// 함수역할: 개인정보 없는 채팅 메시지 응답을 만든다.
// 매개변수: id 메시지 번호, sender 발신자. 반환값: API 형식 메시지.
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

// 클래스명: _ChatFlow
// 역할: 실제 채팅 UI·Control에 격리된 HTTP 응답과 실시간 이벤트를 연결한다.
// 주요 책임: 읽음 요청을 기록하고 다음 이력 응답의 지연을 제어한다.
class _ChatFlow {
  final String userHash;
  final int linkId;
  final navigator = GlobalKey<NavigatorState>();
  final readRequests = <int>[];
  int historyRequests = 0;
  List<Map<String, dynamic>> history = [];
  Completer<List<Map<String, dynamic>>>? nextHistory;
  late final MockClient client;
  late final AuthenticatedApiClient authentication;
  late final ManageLinkedChat control;
  late final _Realtime realtime;

  // Function Name: _ChatFlow
  // Description: Connects history/read/context APIs without external network access.
  // Parameters: userHash/linkId: Authenticated conversation scope. Returns: An isolated chat flow.
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

  // 함수이름: _respond
  // 함수역할: 요청을 기록하고 선택한 이력 요청만 대기시킨다.
  // 매개변수: request Control의 요청. 반환값: 시험 응답.
  Future<http.Response> _respond(http.Request request) async {
    Object data = <Object>[];
    if (request.url.path.endsWith('/messages')) {
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
  // 함수역할: 실제 채팅 화면을 띄워 초기 요청과 화면 배치를 완료한다.
  // 매개변수: tester 화면 시험 도구. 반환값: 준비 완료 Future.
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
  // 함수역할: 화면·타이머·통신 대역을 닫고 앱 수명주기 상태를 복원한다.
  // 매개변수: tester 화면 시험 도구. 반환값: 정리 완료 Future.
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

// 클래스명: _Realtime
// 역할: 실제 소켓 없이 메시지와 연결 이벤트를 제공한다.
// 주요 책임: 이력 응답과 별도 순서로 실시간 이벤트를 주입한다.
class _Realtime extends LinkedChatRealtimeService {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  // Function Name: _Realtime
  // Description: Initializes a scoped, socket-free realtime adapter.
  // Parameters: client: Authentication boundary; linkId/userHash: Conversation scope.
  // Returns: A deterministic realtime adapter.
  _Realtime(
    AuthenticatedApiClient client, {
    super.linkId = 17,
    super.userHash = 'patient-a',
  }) : super(authenticationClient: client);
  // 함수이름: events
  // 함수역할: 시험이 제어하는 이벤트 스트림을 제공한다.
  // 매개변수: 없음. 반환값: 메시지 이벤트 스트림.
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  // 함수이름: emit
  // 함수역할: 메시지 또는 읽음 이벤트를 화면에 전달한다.
  // 매개변수: event 전달할 응답. 반환값: 없음.
  void emit(Map<String, dynamic> event) => _events.add(event);
  // 함수이름: start
  // 함수역할: 실제 연결 없이 시작 요청을 완료한다.
  // 매개변수: 없음. 반환값: 완료 Future.
  @override
  Future<void> start() async {}
  // 함수이름: stop
  // 함수역할: 실제 연결 없이 중지 요청을 완료한다.
  // 매개변수: 없음. 반환값: 완료 Future.
  @override
  Future<void> stop() async {}
  // 함수이름: dispose
  // 함수역할: 시험 이벤트 스트림과 상위 서비스 자원을 정리한다.
  // 매개변수: 없음. 반환값: 정리 완료 Future.
  @override
  Future<void> dispose() async {
    await _events.close();
    await super.dispose();
  }
}
