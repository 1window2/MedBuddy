// File Name: linked_chat_realtime_service_test.dart
// Role: Characterizes the chat socket's connect timeout, reconnect backoff and stop/start
//   ordering with a fake socket and the widget-test fake clock; no network is used.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/services/linked_chat_realtime_service.dart';

// Class Name: _FakeSocket
// Role: In-memory WebSocket exposing server frames and client side effects.
// Responsibilities:
// - Deliver controlled frames and closes while recording client writes, subscription, and delayed close behavior.
// Attributes:
// - _incoming (StreamController<dynamic>): source of server frames and stream completion.
// - sent (List<dynamic>): client frames, including heartbeat pings.
// - closeCodes (List<int?>): codes passed to client close calls.
// - closeGate (Completer<void>?): optional barrier delaying client close.
// - listened (bool): whether the service subscribed.
// - pingInterval (Duration?): accepted WebSocket setting with no automatic ping behavior.
// - closeCode (int?), closeReason (String?): most recent server close fields; null represents a dropped connection.
class _FakeSocket extends Fake implements WebSocket {
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final List<dynamic> sent = [];
  final List<int?> closeCodes = [];
  Completer<void>? closeGate;
  bool listened = false;

  @override
  Duration? pingInterval;

  @override
  int? closeCode;

  @override
  String? closeReason;

  // Function Name: listen
  // Description:
  // - Mark the socket subscribed and forward the listener configuration to the incoming stream.
  // Parameters:
  // - onData (void Function(dynamic)?): handler for server frames.
  // - onError (Function?): optional stream error handler.
  // - onDone (void Function()?): optional stream-completion handler.
  // - cancelOnError (bool?): forwarded stream cancellation policy.
  // Returns:
  // - StreamSubscription<dynamic>; subscription to the controlled incoming stream.
  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listened = true;
    return _incoming.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  // Function Name: add
  // Description:
  // - Record a client frame without writing to a network.
  // Parameters:
  // - data (dynamic): client payload retained unchanged in sent.
  // Returns:
  // - void; no return value.
  @override
  void add(dynamic data) => sent.add(data);

  // Function Name: close
  // Description:
  // - Record the client close code, wait for closeGate when present, and request incoming-stream closure if still open.
  // Parameters:
  // - code (int?): optional client close code, recorded even when null.
  // - reason (String?): accepted close reason, unused by the fake.
  // Returns:
  // - Future<dynamic>; completes after initiating stream closure, without waiting for the stream close future.
  @override
  Future<dynamic> close([int? code, String? reason]) async {
    closeCodes.add(code);
    await closeGate?.future;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  // Function Name: serverSend
  // Description:
  // - Encode and enqueue one server text frame for the subscribed service.
  // Parameters:
  // - frame (Object): JSON-encodable payload; invalid encodable values or a closed controller raise errors.
  // Returns:
  // - void; no return value.
  void serverSend(Object frame) => _incoming.add(jsonEncode(frame));

  // Function Name: serverClose
  // Description:
  // - Set server close metadata and end the incoming stream without awaiting its listeners.
  // Parameters:
  // - code (int?), reason (String?): server close fields; omitted values simulate an unclassified drop.
  // Returns:
  // - void; no return value.
  void serverClose([int? code, String? reason]) {
    closeCode = code;
    closeReason = reason;
    unawaited(_incoming.close());
  }
}

// Class Name: _Connector
// Role: Connector whose individual socket attempts are completed by the test.
// Responsibilities:
// - Record requested URLs and return controllable futures without network access.
// Attributes:
// - attempts (List<Completer<WebSocket>>): connections in creation order.
// - urls (List<String>): socket URL for each attempt.
class _Connector {
  final List<Completer<WebSocket>> attempts = [];
  final List<String> urls = [];

  // Function Name: connect
  // Description:
  // - Record a socket URL and leave connection success or failure under test control.
  // Parameters:
  // - url (String): requested socket address.
  // - headers (Map<String, dynamic>?): authentication headers accepted but not inspected.
  // Returns:
  // - Future<WebSocket>; completed or failed through the corresponding attempts entry.
  Future<WebSocket> connect(String url, {Map<String, dynamic>? headers}) {
    urls.add(url);
    final attempt = Completer<WebSocket>();
    attempts.add(attempt);
    return attempt.future;
  }
}

// Class Name: _Fixture
// Role: Owns a realtime service, fake connector, and its emitted observations.
// Responsibilities:
// - Provide non-network authentication, count credential/session callbacks, and clean up pending attempts.
// Attributes:
// - connector (_Connector): controlled socket connector.
// - states (List<LinkedChatConnectionState>), events (List<Map<String, dynamic>>): service broadcasts in order.
// - credentialRefreshes, unauthorizedReports (int): authentication callback counts.
// - _client (AuthenticatedApiClient): owned header/authentication client.
// - service (LinkedChatRealtimeService): link-17 service for patient-a.
class _Fixture {
  final _Connector connector = _Connector();
  final List<LinkedChatConnectionState> states = [];
  final List<Map<String, dynamic>> events = [];
  // Number of credential refreshes the service asked for.
  int credentialRefreshes = 0;
  // Number of times the service reported the session as unauthorized.
  int unauthorizedReports = 0;
  late final AuthenticatedApiClient _client;
  late final LinkedChatRealtimeService service;

  // Function Name: _Fixture
  // Description:
  // - Create the unstarted realtime service with mock authentication, a controlled connector, and listeners recording states and events.
  // Parameters:
  // - None.
  // Returns:
  // - _Fixture; no connection starts until service.start is called.
  _Fixture() {
    _client = AuthenticatedApiClient(
      inner: MockClient((_) async => http.Response('{}', 200)),
      tokenProvider: () async => null,
      appCheckTokenProvider: () async => null,
      appCheckRequired: false,
      onUnauthorized: () async => unauthorizedReports++,
    );
    service = LinkedChatRealtimeService(
      linkId: 17,
      userHash: 'patient-a',
      authenticationClient: _client,
      connector: connector.connect,
      credentialRefresher: () async => credentialRefreshes++,
    );
    service.states.listen(states.add);
    service.events.listen(events.add);
  }

  // Function Name: accept
  // Description:
  // - Complete a selected connection attempt with a fresh socket and allow the service to process it.
  // Parameters:
  // - tester (WidgetTester): drains fake-clock work after acceptance.
  // - attempt (int): index of an existing, uncompleted connector attempt.
  // Returns:
  // - Future<_FakeSocket>; accepted socket after one pump; invalid or completed indices fail the fixture.
  Future<_FakeSocket> accept(WidgetTester tester, int attempt) async {
    final socket = _FakeSocket();
    connector.attempts[attempt].complete(socket);
    await tester.pump();
    return socket;
  }

  // Function Name: dispose
  // Description:
  // - Dispose the service, fail unfinished connections so their timeout timers end, drain callbacks, and close the owned authentication client.
  // Parameters:
  // - tester (WidgetTester): processes connection-failure cleanup.
  // Returns:
  // - Future<void>; completes when the controlled service and client are cleaned up.
  Future<void> dispose(WidgetTester tester) async {
    await service.dispose();
    for (final attempt in connector.attempts) {
      if (!attempt.isCompleted) {
        attempt.completeError(const SocketException('test ended'));
      }
    }
    await tester.pump();
    _client.close();
  }
}

// Function Name: main
// Description:
// - Register fake-clock socket tests for timeout, reconnect delays, stop/start ordering, and close-code authentication policy.
// Parameters:
// - None.
// Returns:
// - void; no return value.
void main() {
  // Function Name: a socket accepted after the connect timeout is closed
  // Description:
  // - After the 15-second connection timeout, close a late socket without listening to it or reporting connected; retain the scheduled retry and accept its new socket normally.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('a socket accepted after the connect timeout is closed', (
    tester,
  ) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();
    expect(fixture.connector.attempts, hasLength(1));
    expect(fixture.connector.urls.single, contains('/chat/links/17/stream'));

    await tester.pump(const Duration(seconds: 15));
    expect(fixture.states, [
      LinkedChatConnectionState.connecting,
      LinkedChatConnectionState.reconnecting,
    ]);

    final late = await fixture.accept(tester, 0);
    expect(late.closeCodes, [WebSocketStatus.normalClosure]);
    expect(late.listened, isFalse);
    expect(fixture.states, isNot(contains(LinkedChatConnectionState.connected)));

    // The scheduled reconnect is unaffected by the late socket.
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.connector.attempts, hasLength(2));
    final socket = await fixture.accept(tester, 1);
    expect(fixture.states.last, LinkedChatConnectionState.connected);
    expect(socket.listened, isTrue);
    expect(socket.closeCodes, isEmpty);

    await fixture.dispose(tester);
    expect(tester.takeException(), isNull);
  });

  // Function Name: a connect that fails after the timeout is ignored
  // Description:
  // - A connector failure arriving after its timeout is consumed without becoming an unhandled asynchronous exception.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('a connect that fails after the timeout is ignored', (
    tester,
  ) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    fixture.connector.attempts[0].completeError(
      const SocketException('refused'),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await fixture.dispose(tester);
  });

  // Function Name: backoff grows while the server closes right after accepting
  // Description:
  // - Immediate server drops after acceptance increase reconnect delays through 1, 2, 5, and capped 10 seconds; acceptance alone does not reset backoff.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('backoff grows while the server closes right after accepting', (
    tester,
  ) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();

    var attempt = 0;
    for (final seconds in [1, 2, 5, 10, 10]) {
      final socket = await fixture.accept(tester, attempt);
      expect(fixture.states.last, LinkedChatConnectionState.connected);
      socket.serverClose();
      await tester.pump();
      expect(fixture.states.last, LinkedChatConnectionState.reconnecting);
      await tester.pump(Duration(seconds: seconds) - const Duration(milliseconds: 1));
      expect(
        fixture.connector.attempts,
        hasLength(attempt + 1),
        reason: 'reconnect ${attempt + 1} must wait $seconds s',
      );
      await tester.pump(const Duration(milliseconds: 1));
      attempt += 1;
      expect(fixture.connector.attempts, hasLength(attempt + 1));
    }

    await fixture.dispose(tester);
  });

  // Function Name: chat_ready resets the backoff
  // Description:
  // - A chat_ready event is forwarded and resets accumulated reconnect backoff to exactly one second.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('chat_ready resets the backoff', (tester) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();
    for (var attempt = 0; attempt < 3; attempt++) {
      (await fixture.accept(tester, attempt)).serverClose();
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
    }
    expect(fixture.connector.attempts, hasLength(4));

    final ready = await fixture.accept(tester, 3);
    ready.serverSend({'type': 'chat_ready', 'link_id': 17});
    await tester.pump();
    expect(fixture.events.single['type'], 'chat_ready');
    ready.serverClose();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 999));
    expect(fixture.connector.attempts, hasLength(4));
    await tester.pump(const Duration(milliseconds: 1));
    expect(fixture.connector.attempts, hasLength(5));

    await fixture.dispose(tester);
  });

  // Function Name: a connection kept for 30 s resets the backoff
  // Description:
  // - A connection surviving 30 seconds sends one heartbeat and resets its next reconnect delay to one second.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('a connection kept for 30 s resets the backoff', (tester) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();
    for (var attempt = 0; attempt < 3; attempt++) {
      (await fixture.accept(tester, attempt)).serverClose();
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
    }

    final stable = await fixture.accept(tester, 3);
    await tester.pump(const Duration(seconds: 30));
    // The heartbeat ran once in that time.
    expect(stable.sent, ['ping']);
    stable.serverClose();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.connector.attempts, hasLength(5));

    await fixture.dispose(tester);
  });

  // Function Name: stop followed by start ends connected
  // Description:
  // - Starting again while an old stop awaits socket closure keeps the new connection alive; only a later uninterrupted stop reports one disconnect.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('stop followed by start ends connected', (tester) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();
    final first = await fixture.accept(tester, 0);
    first.closeGate = Completer<void>();

    final stopping = fixture.service.stop();
    unawaited(fixture.service.start());
    await tester.pump();
    final second = await fixture.accept(tester, 1);
    expect(fixture.states.last, LinkedChatConnectionState.connected);

    first.closeGate!.complete();
    await stopping;
    await tester.pump();
    expect(fixture.states, [
      LinkedChatConnectionState.connecting,
      LinkedChatConnectionState.connected,
      LinkedChatConnectionState.connecting,
      LinkedChatConnectionState.connected,
    ]);
    // The old socket's end is not mistaken for a drop of the new one.
    await tester.pump(const Duration(seconds: 5));
    expect(fixture.connector.attempts, hasLength(2));
    expect(second.closeCodes, isEmpty);

    // A stop that nothing interrupts still reports the disconnect, once.
    await fixture.service.stop();
    await tester.pump();
    expect(fixture.states.last, LinkedChatConnectionState.disconnected);
    expect(
      fixture.states.where(
        (state) => state == LinkedChatConnectionState.disconnected,
      ),
      hasLength(1),
    );
    expect(second.closeCodes, [WebSocketStatus.normalClosure]);

    await fixture.dispose(tester);
  });

  // Function Name: dispose during a pending stop does not throw
  // Description:
  // - Disposing during a gated stop must not throw or emit a late disconnected state after the old socket finally closes.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('dispose during a pending stop does not throw', (tester) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();
    final socket = await fixture.accept(tester, 0);
    socket.closeGate = Completer<void>();

    final stopping = fixture.service.stop();
    await fixture.dispose(tester);
    socket.closeGate!.complete();
    await stopping;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(fixture.states, [
      LinkedChatConnectionState.connecting,
      LinkedChatConnectionState.connected,
    ]);
  });

  // Function Name: a socket accepted after stop is closed and not reconnected
  // Description:
  // - A socket accepted after stop is closed without subscription, and no reconnect is attempted during the following 30 seconds.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('a socket accepted after stop is closed and not reconnected', (
    tester,
  ) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();
    await fixture.service.stop();
    final socket = await fixture.accept(tester, 0);
    expect(socket.closeCodes, [WebSocketStatus.normalClosure]);
    expect(socket.listened, isFalse);
    await tester.pump(const Duration(seconds: 30));
    expect(fixture.connector.attempts, hasLength(1));
    expect(fixture.states.last, LinkedChatConnectionState.disconnected);

    await fixture.dispose(tester);
  });
  // Function Name: a link-removed close stops reconnecting
  // Description:
  // - Close code 4404 stops automatic reconnects without reporting unauthorized; an explicit start can attempt the conversation again.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('a link-removed close stops reconnecting', (tester) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();
    final socket = await fixture.accept(tester, 0);
    socket.serverSend({'type': 'chat_ready', 'link_id': 17});
    await tester.pump();

    socket.serverClose(4404);
    await tester.pump();
    expect(fixture.states.last, LinkedChatConnectionState.disconnected);
    await tester.pump(const Duration(minutes: 5));
    expect(fixture.connector.attempts, hasLength(1));
    expect(fixture.unauthorizedReports, 0);

    // Opening the conversation again (start) tries once more.
    unawaited(fixture.service.start());
    await tester.pump();
    expect(fixture.connector.attempts, hasLength(2));

    await fixture.dispose(tester);
  });

  // Function Name: an authentication close refreshes the token once, then reports the session
  // Description:
  // - The first 4401 close schedules one credential refresh and retry; a second consecutive rejection reports unauthorized and stops reconnecting.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('an authentication close refreshes the token once, then reports the session', (
    tester,
  ) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();

    (await fixture.accept(tester, 0)).serverClose(4401);
    await tester.pump();
    expect(fixture.states.last, LinkedChatConnectionState.reconnecting);
    expect(fixture.credentialRefreshes, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.credentialRefreshes, 1);
    expect(fixture.connector.attempts, hasLength(2));
    expect(fixture.unauthorizedReports, 0);

    (await fixture.accept(tester, 1)).serverClose(4401);
    await tester.pump();
    expect(fixture.unauthorizedReports, 1);
    expect(fixture.states.last, LinkedChatConnectionState.disconnected);
    await tester.pump(const Duration(minutes: 5));
    expect(fixture.connector.attempts, hasLength(2));
    expect(fixture.credentialRefreshes, 1);

    await fixture.dispose(tester);
  });

  // Function Name: chat_ready renews the single authentication retry
  // Description:
  // - Receiving chat_ready renews the one-time authentication retry allowance, permitting another refresh after a later 4401 close.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('chat_ready renews the single authentication retry', (tester) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();
    (await fixture.accept(tester, 0)).serverClose(4401);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final ready = await fixture.accept(tester, 1);
    ready.serverSend({'type': 'chat_ready', 'link_id': 17});
    await tester.pump();
    ready.serverClose(4401);
    await tester.pump();
    expect(fixture.unauthorizedReports, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.credentialRefreshes, 2);
    expect(fixture.connector.attempts, hasLength(3));

    await fixture.dispose(tester);
  });

  // Function Name: an expired-credential close reconnects with a fresh token
  // Description:
  // - Code 4440 renews credentials and reconnects after each established ready session without reporting an unauthorized account.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('an expired-credential close reconnects with a fresh token', (tester) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();
    final socket = await fixture.accept(tester, 0);
    socket.serverSend({'type': 'chat_ready', 'link_id': 17});
    await tester.pump();

    for (var round = 1; round <= 2; round++) {
      final current = round == 1 ? socket : await fixture.accept(tester, round - 1);
      if (round == 2) {
        current.serverSend({'type': 'chat_ready', 'link_id': 17});
        await tester.pump();
      }
      current.serverClose(4440);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.credentialRefreshes, round);
      expect(fixture.connector.attempts, hasLength(round + 1));
    }
    expect(fixture.unauthorizedReports, 0);

    await fixture.dispose(tester);
  });

  // Function Name: a quota close waits as long as the server says
  // Description:
  // - Honor a 4429 retry delay of 42 seconds, cap an excessive reason at 300 seconds, and use ordinary backoff when no usable delay is supplied.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('a quota close waits as long as the server says', (tester) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();

    (await fixture.accept(tester, 0)).serverClose(4429, '42');
    await tester.pump();
    await tester.pump(const Duration(seconds: 41, milliseconds: 999));
    expect(fixture.connector.attempts, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(fixture.connector.attempts, hasLength(2));

    (await fixture.accept(tester, 1)).serverClose(4429, '86400');
    await tester.pump();
    await tester.pump(const Duration(seconds: 299, milliseconds: 999));
    expect(fixture.connector.attempts, hasLength(2));
    await tester.pump(const Duration(milliseconds: 1));
    expect(fixture.connector.attempts, hasLength(3));

    // Without a usable reason (pings sent too fast) the ordinary backoff applies: third step, 5 s.
    (await fixture.accept(tester, 2)).serverClose(4429);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4, milliseconds: 999));
    expect(fixture.connector.attempts, hasLength(3));
    await tester.pump(const Duration(milliseconds: 1));
    expect(fixture.connector.attempts, hasLength(4));

    await fixture.dispose(tester);
  });

  // Function Name: a refusal close is retried a minute later
  // Description:
  // - Refusal codes 4403 and 4409 stay reconnecting but wait exactly one minute before another connection attempt.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('a refusal close is retried a minute later', (tester) async {
    for (final code in [4403, 4409]) {
      final fixture = _Fixture();
      unawaited(fixture.service.start());
      await tester.pump();
      (await fixture.accept(tester, 0)).serverClose(code);
      await tester.pump();
      expect(fixture.states.last, LinkedChatConnectionState.reconnecting);
      await tester.pump(const Duration(seconds: 59, milliseconds: 999));
      expect(fixture.connector.attempts, hasLength(1), reason: 'code $code');
      await tester.pump(const Duration(milliseconds: 1));
      expect(fixture.connector.attempts, hasLength(2), reason: 'code $code');
      await fixture.dispose(tester);
    }
  });

  // Function Name: a handshake refusal backs off without reading a close code
  // Description:
  // - Handshake exceptions use bounded 1/2/5/10-second reconnect backoff without reading close codes, refreshing credentials, or reporting unauthorized.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains scheduled asynchronous work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('a handshake refusal backs off without reading a close code', (tester) async {
    final fixture = _Fixture();
    unawaited(fixture.service.start());
    await tester.pump();

    var attempt = 0;
    for (final seconds in [1, 2, 5, 10, 10]) {
      fixture.connector.attempts[attempt].completeError(
        const WebSocketException('Connection was not upgraded to websocket'),
      );
      await tester.pump();
      expect(fixture.states.last, LinkedChatConnectionState.reconnecting);
      await tester.pump(Duration(seconds: seconds) - const Duration(milliseconds: 1));
      expect(fixture.connector.attempts, hasLength(attempt + 1));
      await tester.pump(const Duration(milliseconds: 1));
      attempt += 1;
      expect(fixture.connector.attempts, hasLength(attempt + 1));
    }
    expect(fixture.credentialRefreshes, 0);
    expect(fixture.unauthorizedReports, 0);

    await fixture.dispose(tester);
  });
}
