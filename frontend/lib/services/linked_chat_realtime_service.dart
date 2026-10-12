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
// 역할: 채팅 이벤트 소비자가 사용할 연결 및 수신 계약이다.
// 주요 책임:
// - 구체 WebSocket 구현을 감추고 이벤트 스트림·시작·정리 수명을 함께 제공한다.
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
// 역할: 채팅 소켓의 연결 중·연결됨·재연결 중·연결 해제 상태를 구분한다.
// 주요 책임:
// - 화면이 메시지 스트림과 별도로 연결 진행 및 복구 상태를 표시하게 한다.
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

// 클래스명: LinkedChatRealtimeService
// 역할: 한 환자·보호자 연동의 인증 WebSocket 연결을 관리한다.
// 주요 책임:
// - 공유 인증 헤더로 연결하고 ping·재연결·세대 검증을 수행하며 JSON 이벤트와 연결 상태를 방송한다.
// - 서버가 수락 직후 닫는 연결(한도 초과·권한 거부)에는 재연결 간격을 줄이지 않는다.
// - 서버의 종료 코드를 읽어 연동 해제(4404)에는 재연결을 멈추고, 인증 실패(4401)에는 새 토큰으로 한 번만
//   다시 시도한 뒤 세션 문제로 알리며, 연결 한도(4429)에는 서버가 알려 준 시간만큼 기다린다.
//   핸드셰이크에서 거절하는 서버는 종료 코드를 전달하지 못하므로 그때는 간격만 늘려 다시 시도한다.
// 속성:
// - linkId (int): 조회·전송·감시 대상 연동 ID
// - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
// - authenticationClient (AuthenticatedApiClient): REST와 소켓의 공통 인증 헤더 제공자
// - _connector (LinkedChatSocketConnector): 소켓을 여는 연결 함수
// - _refreshCredential (LinkedChatCredentialRefresher): 인증 실패·만료로 닫힌 뒤 새 토큰을 받는 함수
// - _socket (WebSocket?): 현재 heartbeat와 수신에 사용할 WebSocket
// - _generation (int): 이전 비동기 응답을 차단할 현재 작업 세대
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

  // 함수이름: LinkedChatRealtimeService
  // 함수역할: 감시할 연동 ID와 현재 사용자 및 인증 헤더 제공 클라이언트를 연결한다.
  // 매개변수:
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // - authenticationClient (AuthenticatedApiClient): REST와 소켓의 공통 인증 헤더 제공자
  // - connector (LinkedChatSocketConnector?): 소켓 연결 함수; 생략하면 WebSocket.connect
  // - credentialRefresher (LinkedChatCredentialRefresher?): 새 인증 토큰을 받는 함수; 생략하면 Firebase ID 토큰을 강제로 갱신한다
  // 반환값:
  // - LinkedChatRealtimeService: 초기화된 인스턴스.
  LinkedChatRealtimeService({
    required this.linkId,
    required this.userHash,
    required this.authenticationClient,
    LinkedChatSocketConnector? connector,
    LinkedChatCredentialRefresher? credentialRefresher,
  }) : _connector = connector ?? WebSocket.connect,
       _refreshCredential = credentialRefresher ?? _refreshFirebaseIdToken;

  // 함수이름: _refreshFirebaseIdToken
  // 함수역할: 인증을 쓰는 실행에서 현재 Firebase 사용자의 ID 토큰을 서버에서 새로 받아, 이어지는 연결의
  //   인증 헤더가 새 토큰을 쓰게 한다. 인증을 끈 로컬 실행에서는 아무 일도 하지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 갱신을 마치면 완료.
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
  // 함수이름: states
  // 함수역할: 연결 시작·성공·재연결·종료 상태를 구독자에게 방송하는 스트림을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Stream<LinkedChatConnectionState>: 연결 시작·성공·재연결·종료 상태를 구독자에게 방송하는 스트림을 제공한다.
  @override
  Stream<LinkedChatConnectionState> get states => _stateController.stream;

  // 함수이름: start
  // 함수역할: 채팅 실시간 연결을 한 번 시작하고 끊기면 제한된 간격으로 재연결한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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

  // 함수이름: _connect
  // 함수역할: 현재 세대의 인증 소켓을 연결하고 늦게 도착한 이전 연결은 닫으며 수신·heartbeat를 시작하고 실패 시 재연결을 예약한다.
  // 매개변수:
  // - generation (int): 이전 비동기 응답을 차단할 현재 작업 세대
  // - reconnecting (bool): 최초 연결이 아닌 복구 연결인지 여부
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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

  // 함수이름: _closeLateSocket
  // 함수역할: 연결 제한 시간이 지난 뒤에 완료된 연결을 닫고, 그 연결의 늦은 실패는 무시한다.
  // 매개변수:
  // - connecting (Future<WebSocket>): 제한 시간 안에 끝나지 않은 연결 시도
  // 반환값:
  // - Future<void>: 늦은 소켓을 닫았거나 연결이 실패하면 완료.
  Future<void> _closeLateSocket(Future<WebSocket> connecting) async {
    try {
      final late = await connecting;
      await late.close(WebSocketStatus.normalClosure);
    } catch (_) {
      // 이미 시간 초과로 재연결을 예약했으므로 늦은 실패는 따로 처리하지 않는다.
    }
  }

  // 함수이름: _handleSocketData
  // 함수역할: 수신 문자열을 JSON 객체로 해석해 이벤트 스트림으로 전달하고 파싱 오류는 진단 로그에 남긴다.
  //           현재 소켓의 chat_ready는 서버가 연결을 등록했다는 뜻이므로 재연결 간격을 처음으로 되돌린다.
  // 매개변수:
  // - socket (WebSocket): 데이터를 받은 소켓
  // - rawData (dynamic): 해석 전 WebSocket 수신 데이터
  // 반환값:
  // - 없음.
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

  // 함수이름: _emitState
  // 함수역할: 해제로 스트림이 닫힌 뒤에 끝난 비동기 작업이 상태를 추가하지 않게 막고 연결 상태를 방송한다.
  // 매개변수:
  // - state (LinkedChatConnectionState): 구독자에게 알릴 연결 상태
  // 반환값:
  // - 없음.
  void _emitState(LinkedChatConnectionState state) {
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  // 함수이름: _startHeartbeat
  // 함수역할: 현재 연결과 세대가 유지되는 동안 20초 간격으로 ping을 보내도록 이전 heartbeat를 교체한다.
  // 매개변수:
  // - socket (WebSocket): 현재 heartbeat와 수신에 사용할 WebSocket
  // - generation (int): 이전 비동기 응답을 차단할 현재 작업 세대
  // 반환값:
  // - 없음.
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

  // 함수이름: _handleDisconnected
  // 함수역할: 현재 소켓의 끊김에만 반응해 참조와 heartbeat를 정리하고, 서버가 보낸 종료 코드에 따라
  //           재연결을 멈추거나 새 토큰·대기 시간을 정해 같은 세대의 재연결을 예약한다.
  // 매개변수:
  // - socket (WebSocket): 현재 heartbeat와 수신에 사용할 WebSocket
  // - generation (int): 이전 비동기 응답을 차단할 현재 작업 세대
  // 반환값:
  // - 없음.
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

  // 함수이름: _haltReconnection
  // 함수역할: 서버가 다시 연결해도 소용없다고 알린 뒤 재연결을 멈추고 연결 해제 상태를 알린다.
  //           start()를 다시 호출하면(화면 재진입·앱 복귀) 한 번 더 연결을 시도한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void _haltReconnection() {
    _started = false;
    _generation += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _emitState(LinkedChatConnectionState.disconnected);
  }

  // 함수이름: _scheduleReconnect
  // 함수역할: 중복 예약과 이전 세대를 차단하고 1·2·5·10초로 늘어나는 지연 중 다음 연결 시도를 예약한다.
  // 매개변수:
  // - generation (int): 이전 비동기 응답을 차단할 현재 작업 세대
  // - minimumDelay (Duration?): 서버가 요구했거나 거절 사유에 맞춘 최소 대기; 늘어나는 지연보다 길 때만 적용한다
  // 반환값:
  // - 없음.
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

  // 함수이름: stop
  // 함수역할: 화면 종료 시 재연결과 heartbeat를 중지하고 소켓을 정상 종료한다.
  //           소켓을 닫는 동안 start()가 다시 호출되었으면 새 연결의 상태를 연결 해제로 덮어쓰지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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
