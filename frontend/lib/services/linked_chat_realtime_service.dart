// 파일명: linked_chat_realtime_service.dart
// 역할: 채팅 WebSocket 연결, 재연결, 실시간 이벤트 수신을 캡슐화한다.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import 'api_config.dart';
import 'auth_config.dart';
import 'authenticated_api_client.dart';

// 클래스명: LinkedChatEventSource
// 역할: 연동 채팅 이벤트 구독과 연결 수명주기를 제공하는 계약이다.
// 주요 책임: 구현체가 이벤트 스트림·시작·해제를 제공하도록 한다.
// 속성: events (Stream<Map<String, dynamic>>): 서버 이벤트; 구현체별 연결 상태는 노출하지 않는다.
abstract interface class LinkedChatEventSource {
  // 함수이름: events
  // 함수역할: 채팅 메시지와 읽음 등 서버의 구조화된 실시간 이벤트 스트림을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Stream<Map<String, dynamic>>: 채팅 메시지와 읽음 등 서버의 구조화된 실시간 이벤트 스트림을 제공한다.
  Stream<Map<String, dynamic>> get events;

  // 함수이름: start
  // 함수역할: 실시간 이벤트 수신을 시작하는 비동기 연결 계약을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> start();

  // 함수이름: dispose
  // 함수역할: 이벤트 소스의 연결과 수신 자원을 종료하는 비동기 계약을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> dispose();
}

// 클래스명: LinkedChatConnectionState
// 역할: 연동 채팅 전송 계층의 연결 진행 상태를 구분한다.
// 주요 책임: 최초 연결과 재연결을 화면에서 구별하게 한다.
// 속성: connecting/connected/reconnecting/disconnected: 연결 상태.
enum LinkedChatConnectionState {
  connecting,
  connected,
  reconnecting,
  disconnected,
}

// Class Name: LinkedChatSessionTransport
// Role: Provides connection visibility and foreground control for a scoped chat session.
// Responsibilities: Extend the event-source contract without expanding existing monitor consumers.
// Attributes: states: Connection state stream; stop: Reversible foreground transport suspension.
abstract interface class LinkedChatSessionTransport
    implements LinkedChatEventSource {
  // Function Name: states
  // Description: Exposes connection state independently of message events.
  // Parameters: None. Returns: Connection state stream for a borrowed session transport.
  Stream<LinkedChatConnectionState> get states;

  // Function Name: stop
  // Description: Suspends transport and reconnect work without disposing the adapter.
  // Parameters: None. Returns: Completion of background suspension.
  Future<void> stop();
}

// 함수이름: LinkedChatSocketConnector
// 함수역할: 채팅 WebSocket을 여는 연결 계약이다. 기본값은 WebSocket.connect이며 테스트는 네트워크 없는 대역을 주입한다.
// 매개변수:
// - url (String): 연결할 WebSocket 주소
// - headers (Map<String, dynamic>?): 연결 요청에 붙일 인증 헤더
// 반환값:
// - Future<WebSocket>: 서버가 수락한 소켓.
typedef LinkedChatSocketConnector =
    Future<WebSocket> Function(String url, {Map<String, dynamic>? headers});

// 함수이름: LinkedChatCredentialRefresher
// 함수역할: 다음 연결이 새 인증 토큰을 쓰도록 자격 증명을 갱신하는 계약이다. 기본값은 Firebase ID 토큰 강제 갱신이다.
// 매개변수:
// - 없음.
// 반환값:
// - Future<void>: 갱신을 마치면 완료.
typedef LinkedChatCredentialRefresher = Future<void> Function();

// Class Name: LinkedChatRealtimeService
// Role: Maintain an authenticated linked-chat WebSocket session.
// Responsibilities: Publish events and connection states, send heartbeats and apply close-code-specific reconnection policies.
// Attributes: linkId/userHash/authenticationClient: session identity and authentication; _connector/_refreshCredential: injected boundaries; socket, timers, generation and retry fields: connection lifecycle.
class LinkedChatRealtimeService implements LinkedChatSessionTransport {
  static const List<Duration> _reconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];
  static const Duration _connectTimeout = Duration(seconds: 15);
  // chat_ready를 보내지 않는 서버에서도 이만큼 유지된 연결은 정상으로 본다.
  static const Duration _stableConnectionDuration = Duration(seconds: 30);
  // 서버(backend/api/chat_router.py)가 보내는 종료 코드.
  static const int _closeAuthenticationFailed = 4401;
  static const int _closeAccessRefused = 4403;
  static const int _closeLinkInactive = 4404;
  static const int _closeContractMismatch = 4409;
  static const int _closeQuotaExceeded = 4429;
  static const int _closeCredentialExpired = 4440;
  // 다시 시도해도 곧바로 풀리지 않는 거절(권한·API 계약)에 두는 최소 대기.
  static const Duration _refusalDelay = Duration(seconds: 60);
  // 서버가 알려 준 대기 시간을 그대로 믿지 않고 이 범위 안에서만 따른다.
  static const int _maximumQuotaWaitSeconds = 300;

  final int linkId;
  final String userHash;
  final AuthenticatedApiClient authenticationClient;
  final LinkedChatSocketConnector _connector;
  final LinkedChatCredentialRefresher _refreshCredential;
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<LinkedChatConnectionState> _stateController =
      StreamController<LinkedChatConnectionState>.broadcast();

  WebSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _stableTimer;
  int _generation = 0;
  int _reconnectAttempt = 0;
  bool _started = false;
  // 다음 연결 전에 새 토큰을 받아야 하는지 여부.
  bool _refreshCredentialBeforeConnect = false;
  // 인증 실패로 닫힌 뒤 새 토큰으로 이미 한 번 다시 시도했는지 여부. chat_ready를 받으면 되돌린다.
  bool _retriedAfterAuthenticationFailure = false;

  // Function Name: LinkedChatRealtimeService
  // Description: Bind one link and user to authentication and replaceable socket/credential boundaries; do not connect yet.
  // Parameters: linkId (int): link; userHash (String): user; authenticationClient (AuthenticatedApiClient): borrowed authentication; connector (LinkedChatSocketConnector?): socket opener; credentialRefresher (LinkedChatCredentialRefresher?): forced credential refresh.
  // Returns: LinkedChatRealtimeService: inactive session transport.
  LinkedChatRealtimeService({
    required this.linkId,
    required this.userHash,
    required this.authenticationClient,
    LinkedChatSocketConnector? connector,
    LinkedChatCredentialRefresher? credentialRefresher,
  }) : _connector = connector ?? WebSocket.connect,
       _refreshCredential = credentialRefresher ?? _refreshFirebaseIdToken;

  // Function Name: _refreshFirebaseIdToken
  // Description: Force-refresh the current Firebase user's ID token unless authentication is disabled.
  // Parameters: None.
  // Returns: Future<void>: refresh completion, or no-op without a current user; refresh errors propagate.
  static Future<void> _refreshFirebaseIdToken() async {
    if (AuthConfig.mode == AuthenticationMode.disabled) {
      return;
    }
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  // 함수이름: events
  // 함수역할: 채팅 메시지와 읽음 등 서버의 구조화된 실시간 이벤트 스트림을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Stream<Map<String, dynamic>>: 채팅 메시지와 읽음 등 서버의 구조화된 실시간 이벤트 스트림을 제공한다.
  @override
  Stream<Map<String, dynamic>> get events => _eventController.stream;
  // Function Name: states
  // Description: Expose connection-state changes to subscribers.
  // Parameters: None.
  // Returns: Stream<LinkedChatConnectionState>: state events.
  @override
  Stream<LinkedChatConnectionState> get states => _stateController.stream;

  // Function Name: start
  // Description: Start once, reset retry counters and connect under a new generation.
  // Parameters: None.
  // Returns: Future<void>: initial connection attempt completion; repeated starts are ignored.
  @override
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _reconnectAttempt = 0;
    _retriedAfterAuthenticationFailure = false;
    final generation = ++_generation;
    await _connect(generation, reconnecting: false);
  }

  // Function Name: _connect
  // Description: Connect with current credentials under a generation guard, close late/stale sockets, and attach heartbeat/event handlers; report failures and schedule retry.
  // Parameters: generation (int): active session revision; reconnecting (bool): state to announce.
  // Returns: Future<void>: connection attempt settles; failures are reported through the service.
  Future<void> _connect(int generation, {required bool reconnecting}) async {
    if (!_started || generation != _generation) {
      return;
    }
    _emitState(
      reconnecting
          ? LinkedChatConnectionState.reconnecting
          : LinkedChatConnectionState.connecting,
    );
    try {
      if (_refreshCredentialBeforeConnect) {
        _refreshCredentialBeforeConnect = false;
        try {
          await _refreshCredential();
        } catch (error, stackTrace) {
          // 갱신하지 못하면 가진 토큰으로 연결해 본다. 다시 거절되면 그때 세션 문제로 알린다.
          _reportError(error, stackTrace);
        }
        if (!_started || generation != _generation) {
          return;
        }
      }
      final uri = Uri.parse(ApiConfig.chatWebSocketUrl('/links/$linkId/stream'))
          .replace(
            queryParameters: AuthConfig.mode == AuthenticationMode.disabled
                ? {'user_hash': userHash}
                : null,
          );
      final headers = await authenticationClient.buildAuthenticationHeaders(
        uri,
      );
      final connecting = _connector(uri.toString(), headers: headers);
      final WebSocket socket;
      try {
        socket = await connecting.timeout(_connectTimeout);
      } on TimeoutException {
        // 제한 시간 뒤에 수락된 소켓은 아무도 쓰지 않으므로 닫아 서버의 연결 한도를 차지하지 않게 한다.
        unawaited(_closeLateSocket(connecting));
        rethrow;
      }
      if (!_started || generation != _generation) {
        await socket.close(WebSocketStatus.normalClosure);
        return;
      }
      _socket = socket;
      // 응답 없는 연결도 장애로 감지해 재연결과 REST 보완 조회로 전환한다.
      socket.pingInterval = const Duration(seconds: 30);
      // 수락만으로는 재연결 간격을 되돌리지 않는다. 서버는 한도 초과·권한 거부도 수락 뒤에 닫는다.
      _stableTimer?.cancel();
      _stableTimer = Timer(_stableConnectionDuration, /* 함수이름: Timer 콜백
       * 함수역할: 같은 소켓이 충분히 유지되면 다음 끊김의 재연결을 가장 짧은 간격부터 시작하게 한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 없음.
       */ () {
        if (identical(_socket, socket)) {
          _reconnectAttempt = 0;
        }
      });
      _emitState(LinkedChatConnectionState.connected);
      _startHeartbeat(socket, generation);
      socket.listen(
        /* 함수이름: onData 콜백
         * 함수역할: 수신 데이터를 해당 소켓의 이벤트로 처리한다.
         * 매개변수:
         * - rawData (dynamic): 해석 전 WebSocket 수신 데이터
         * 반환값:
         * - 없음.
         */
        (dynamic rawData) => _handleSocketData(socket, rawData),
        onError: /* 함수이름: onError 콜백
         * 함수역할: 웹소켓 오류를 보고하고 해당 소켓 세대의 연결 해제 처리를 진행한다.
         * 매개변수:
         * - error (Object): 처리하거나 기록할 원래 실패 객체
         * - stackTrace (StackTrace): 오류 진단에 함께 기록할 호출 스택
         * 반환값:
         * - 없음.
         */ (Object error, StackTrace stackTrace) {
          _reportError(error, stackTrace);
          _handleDisconnected(socket, generation);
        },
        onDone: /* 함수이름: onDone 콜백
         * 함수역할: 웹소켓 종료를 현재 연결 세대에 대한 연결 해제로 처리한다.
         * 매개변수:
         * - 없음.
         * 반환값:
         * - 없음.
         */ () =>
            _handleDisconnected(socket, generation),
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
      _scheduleReconnect(generation);
    }
  }

  // Function Name: _closeLateSocket
  // Description: Close a socket that completes after its connection attempt timed out; ignore connection or close failures.
  // Parameters: connecting (Future<WebSocket>): timed-out pending connection.
  // Returns: Future<void>: late cleanup completion.
  Future<void> _closeLateSocket(Future<WebSocket> connecting) async {
    try {
      final late = await connecting;
      await late.close(WebSocketStatus.normalClosure);
    } catch (_) {
      // 이미 시간 초과로 재연결을 예약했으므로 늦은 실패는 따로 처리하지 않는다.
    }
  }

  // Function Name: _handleSocketData
  // Description: Decode map-shaped socket events; chat_ready resets authentication retry state only for the current socket. Report malformed events.
  // Parameters: socket (WebSocket): emitting connection; rawData (dynamic): wire event.
  // Returns: void; publishes decoded maps or reports decoding errors.
  void _handleSocketData(WebSocket socket, dynamic rawData) {
    try {
      final decoded = jsonDecode(rawData.toString());
      if (decoded is Map) {
        if (decoded['type'] == 'chat_ready' && identical(_socket, socket)) {
          _reconnectAttempt = 0;
          _retriedAfterAuthenticationFailure = false;
        }
        _eventController.add(Map<String, dynamic>.from(decoded));
      }
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }
  }

  // Function Name: _emitState
  // Description: Publish a connection state only while the state stream is open.
  // Parameters: state (LinkedChatConnectionState): new state.
  // Returns: void.
  void _emitState(LinkedChatConnectionState state) {
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  // Function Name: _startHeartbeat
  // Description: Replace the heartbeat timer and send ping every 20 seconds only for the active socket generation.
  // Parameters: socket (WebSocket): connected socket; generation (int): session revision.
  // Returns: void.
  void _startHeartbeat(WebSocket socket, int generation) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 20),
      /* 함수이름: periodic 콜백
     * 함수역할: 서비스가 시작 상태이고 같은 소켓 세대가 유지될 때만 ping을 전송한다.
     * 매개변수:
     * - _ (Timer): 콜백 계약으로 전달되지만 사용하지 않는 이벤트 값.
     * 반환값:
     * - 없음.
     */ (_) {
        if (_started &&
            generation == _generation &&
            identical(_socket, socket)) {
          socket.add('ping');
        }
      },
    );
  }

  // Function Name: _handleDisconnected
  // Description: Handle current-socket closure: halt inactive links/repeated authentication failures, refresh expired credentials, and honor quota/refusal delays.
  // Parameters: socket (WebSocket): disconnected socket; generation (int): originating session revision.
  // Returns: void; stale socket notifications are ignored.
  void _handleDisconnected(WebSocket socket, int generation) {
    if (!identical(_socket, socket)) {
      return;
    }
    final closeCode = socket.closeCode;
    final closeReason = socket.closeReason;
    _socket = null;
    _heartbeatTimer?.cancel();
    _stableTimer?.cancel();
    if (!_started || generation != _generation) {
      return;
    }
    switch (closeCode) {
      case _closeLinkInactive:
        // 연동이 해제되었거나 참여자가 아니다. 다시 연결해도 같은 답이므로 멈춘다.
        _haltReconnection();
        return;
      case _closeAuthenticationFailed:
        if (_retriedAfterAuthenticationFailure) {
          // 새 토큰으로도 거절되었다. 계속 두드리지 않고 REST의 401과 같은 세션 정리로 넘긴다.
          _haltReconnection();
          unawaited(
            authenticationClient.reportUnauthorized().catchError(_reportError),
          );
          return;
        }
        _retriedAfterAuthenticationFailure = true;
        _refreshCredentialBeforeConnect = true;
        _scheduleReconnect(generation);
      case _closeCredentialExpired:
        // 연결을 열 때 쓴 토큰의 수명이 끝났을 뿐이다. 새 토큰으로 바로 이어 간다.
        _refreshCredentialBeforeConnect = true;
        _scheduleReconnect(generation);
      case _closeQuotaExceeded:
        final waitSeconds = int.tryParse(closeReason?.trim() ?? '');
        _scheduleReconnect(
          generation,
          minimumDelay: waitSeconds == null || waitSeconds < 1
              ? null
              : Duration(
                  seconds: waitSeconds.clamp(1, _maximumQuotaWaitSeconds),
                ),
        );
      case _closeAccessRefused:
      case _closeContractMismatch:
        _scheduleReconnect(generation, minimumDelay: _refusalDelay);
      default:
        _scheduleReconnect(generation);
    }
  }

  // Function Name: _haltReconnection
  // Description: Stop retries, invalidate pending generations and publish disconnected state.
  // Parameters: None.
  // Returns: void.
  void _haltReconnection() {
    _started = false;
    _generation += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _emitState(LinkedChatConnectionState.disconnected);
  }

  // Function Name: _scheduleReconnect
  // Description: Schedule one retry for the current generation using the backoff ladder and any larger server minimum.
  // Parameters: generation (int): session revision; minimumDelay (Duration?): lower bound for retry wait.
  // Returns: void; ignores stopped, stale or already scheduled requests.
  void _scheduleReconnect(int generation, {Duration? minimumDelay}) {
    if (!_started || generation != _generation || _reconnectTimer != null) {
      return;
    }
    _emitState(LinkedChatConnectionState.reconnecting);
    final index = _reconnectAttempt.clamp(0, _reconnectDelays.length - 1);
    final ladderDelay = _reconnectDelays[index];
    final delay = minimumDelay != null && minimumDelay > ladderDelay
        ? minimumDelay
        : ladderDelay;
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(delay, /* 함수이름: Timer 콜백
     * 함수역할: 재연결 예약 표시를 지운 뒤 같은 세대의 웹소켓 재접속을 시작한다.
     * 매개변수:
     * - 없음.
     * 반환값:
     * - 없음.
     */ () {
      _reconnectTimer = null;
      unawaited(_connect(generation, reconnecting: true));
    });
  }

  // Function Name: stop
  // Description: Stop an active session, invalidate pending connects, cancel timers and close its socket; publish disconnected only if no newer generation starts.
  // Parameters: None.
  // Returns: Future<void>: socket close completion; a stopped service is unchanged.
  @override
  Future<void> stop() async {
    if (!_started) {
      return;
    }
    _started = false;
    final generation = ++_generation;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _stableTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer = null;
    _stableTimer = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      await socket.close(WebSocketStatus.normalClosure);
    }
    if (generation == _generation) {
      _emitState(LinkedChatConnectionState.disconnected);
    }
  }

  // 함수이름: dispose
  // 함수역할: 소켓·재연결 작업을 중지한 다음 이벤트 및 연결 상태 스트림을 닫는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  @override
  Future<void> dispose() async {
    await stop();
    await _eventController.close();
    await _stateController.close();
  }

  // 함수이름: _reportError
  // 함수역할: 채팅 실시간 처리 오류와 스택을 진단 로그에 남긴다.
  // 매개변수:
  // - error (Object): 처리하거나 기록할 원래 실패 객체
  // - stackTrace (StackTrace): 오류 진단에 함께 기록할 호출 스택
  // 반환값:
  // - 없음.
  void _reportError(Object error, StackTrace stackTrace) {
    developer.log(
      '채팅 실시간 연결을 처리하지 못했습니다.',
      name: 'LinkedChatRealtimeService',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
