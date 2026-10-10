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
// Role: In-memory WebSocket that a test drives from the server side.
// Responsibilities:
// - Deliver server frames and the server close to the single listener.
// - Record what the client sent and how it closed the socket.
// Attributes:
// - sent (List<dynamic>): Frames the client added (heartbeat pings).
// - closeCodes (List<int?>): Code of each client close call, oldest first.
// - closeGate (Completer<void>?): When set, a client close waits for it.
// - listened (bool): Whether the service subscribed to this socket.
// - closeCode, closeReason (int?, String?): Close frame the server sent; null for a dropped
//   connection.
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
  // Description: Subscribes the service to the frames a test sends from the server side.
  // Parameters: onData, onError, onDone, cancelOnError - the Stream.listen contract.
  // Returns: The subscription on the incoming frames.
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
  // Description: Records a frame sent by the client.
  // Parameters: data - frame payload. Returns: None.
  @override
  void add(dynamic data) => sent.add(data);

  // Function Name: close
  // Description: Records the client close, optionally waits for closeGate, then ends the stream.
  // Parameters: code, reason - close frame fields. Returns: Completion of the close handshake.
  @override
  Future<dynamic> close([int? code, String? reason]) async {
    closeCodes.add(code);
    await closeGate?.future;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  // Function Name: serverSend
  // Description: Delivers one JSON text frame from the server.
  // Parameters: frame - JSON-encodable payload. Returns: None.
  void serverSend(Object frame) => _incoming.add(jsonEncode(frame));

  // Function Name: serverClose
  // Description: Ends the connection from the server side, with the close frame when one is given.
  // Parameters: code, reason - close frame fields; omitted for a dropped connection. Returns: None.
  void serverClose([int? code, String? reason]) {
    closeCode = code;
    closeReason = reason;
    unawaited(_incoming.close());
  }
}

// Class Name: _Connector
// Role: Socket connector fake whose attempts a test completes one by one.
// Attributes: attempts - pending or completed connects, oldest first; urls - requested URLs.
class _Connector {
  final List<Completer<WebSocket>> attempts = [];
  final List<String> urls = [];

  // Function Name: connect
  // Description: Records the attempt and leaves its completion to the test.
  // Parameters: url - socket URL; headers - authentication headers (unused).
  // Returns: A future the test completes with a socket or an error.
  Future<WebSocket> connect(String url, {Map<String, dynamic>? headers}) {
    urls.add(url);
    final attempt = Completer<WebSocket>();
    attempts.add(attempt);
    return attempt.future;
  }
}

// Class Name: _Fixture
// Role: A realtime service on a fake connector with its emitted states and events.
// Attributes: connector - connect fake; states/events - everything the service broadcast.
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
  // Description: Builds the service with header providers that need no Firebase or network.
  // Parameters: None. Returns: The fixture, not started.
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
  // Description: Completes the given connect attempt with a new fake socket.
  // Parameters: tester - fake-clock driver; attempt - index of the connect attempt.
  // Returns: The accepted socket after the service processed it.
  Future<_FakeSocket> accept(WidgetTester tester, int attempt) async {
    final socket = _FakeSocket();
    connector.attempts[attempt].complete(socket);
    await tester.pump();
    return socket;
  }

  // Function Name: dispose
  // Description:
  // - Stops the service (cancelling its timers), fails connect attempts a test left open so
  //   their 15 s timeout timers end, and closes the header client.
  // Parameters: tester - fake-clock driver. Returns: Completion of the disposal.
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
// Description: Registers the socket lifecycle tests.
// Parameters: None. Returns: None.
void main() {
  // The connect attempt is abandoned after 15 s; a socket accepted later would otherwise stay
  // open unobserved and count against the server's per-user connection limit.
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

  // A late connect that fails must not surface as an unhandled error.
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

  // The server accepts and then closes a connection it rejects (limit reached, link removed).
  // Accepting alone must therefore not reset the delay to one second.
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

  // chat_ready means the server registered the connection: the next drop starts at 1 s again.
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

  // Without chat_ready, a connection that stayed up for 30 s also counts as healthy.
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

  // setForeground(false) then (true): the earlier stop finishes closing after the new
  // connection is up and must not report "disconnected" for it.
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

  // A stop still closing when the owner disposes the service must not add to closed streams.
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

  // A stop during a pending connect invalidates it: the socket is closed, never used.
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
  // The server closes an accepted stream with 4404 when the link was removed. Reconnecting gets
  // the same answer, so the client stops instead of knocking every few seconds.
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

  // 4401: one retry with a fresh token; a second 4401 ends the retries and reports the session,
  // which is the same cleanup an HTTP 401 triggers.
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

  // A connection that became ready proves the token works, so a later 4401 gets its own retry.
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

  // 4440: the token used at the handshake expired. The session is fine; reconnect at once with
  // a fresh token and do not report anything.
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

  // 4429 carries the seconds to wait as its reason. The client waits that long even when its own
  // backoff would be shorter, and never longer than five minutes.
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

  // 4403 (ownership or attestation refused) and 4409 (API contract mismatch) do not heal within
  // seconds: the client keeps trying, but only once a minute.
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

  // Today's server refuses during the handshake: the connect itself fails, no close code arrives,
  // and the client must simply back off without refreshing or reporting anything.
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
