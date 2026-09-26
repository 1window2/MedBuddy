// 파일명: linked_chat_realtime_service.dart
// 역할: 채팅 WebSocket 연결, 재연결, 실시간 이벤트 수신을 캡슐화한다.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

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

// 클래스명: LinkedChatRealtimeService
// 역할: 한 환자·보호자 연동의 인증 WebSocket 연결을 관리한다.
// 주요 책임:
// - 공유 인증 헤더로 연결하고 ping·재연결·세대 검증을 수행하며 JSON 이벤트와 연결 상태를 방송한다.
// 속성:
// - linkId (int): 조회·전송·감시 대상 연동 ID
// - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
// - authenticationClient (AuthenticatedApiClient): REST와 소켓의 공통 인증 헤더 제공자
// - _socket (WebSocket?): 현재 heartbeat와 수신에 사용할 WebSocket
// - _generation (int): 이전 비동기 응답을 차단할 현재 작업 세대
class LinkedChatRealtimeService implements LinkedChatEventSource {
  static const List<Duration> _reconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  final int linkId;
  final String userHash;
  final AuthenticatedApiClient authenticationClient;
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<LinkedChatConnectionState> _stateController =
      StreamController<LinkedChatConnectionState>.broadcast();

  WebSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _generation = 0;
  int _reconnectAttempt = 0;
  bool _started = false;

  // 함수이름: LinkedChatRealtimeService
  // 함수역할: 감시할 연동 ID와 현재 사용자 및 인증 헤더 제공 클라이언트를 연결한다.
  // 매개변수:
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // - authenticationClient (AuthenticatedApiClient): REST와 소켓의 공통 인증 헤더 제공자
  // 반환값:
  // - LinkedChatRealtimeService: 초기화된 인스턴스.
  LinkedChatRealtimeService({
    required this.linkId,
    required this.userHash,
    required this.authenticationClient,
  });

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
    _stateController.add(
      reconnecting
          ? LinkedChatConnectionState.reconnecting
          : LinkedChatConnectionState.connecting,
    );
    try {
      final uri = Uri.parse(ApiConfig.chatWebSocketUrl('/links/$linkId/stream'))
          .replace(
            queryParameters: AuthConfig.mode == AuthenticationMode.disabled
                ? {'user_hash': userHash}
                : null,
          );
      final headers = await authenticationClient.buildAuthenticationHeaders(
        uri,
      );
      final socket = await WebSocket.connect(
        uri.toString(),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      if (!_started || generation != _generation) {
        await socket.close(WebSocketStatus.normalClosure);
        return;
      }
      _socket = socket;
      _reconnectAttempt = 0;
      _stateController.add(LinkedChatConnectionState.connected);
      _startHeartbeat(socket, generation);
      socket.listen(
        _handleSocketData,
        onError: /* 함수이름: onError 콜백
         * 함수역할: 웹소켓 오류를 보고하고 해당 소켓 세대의 연결 해제 처리를 진행한다.
         * 매개변수:
         * - error (Object): 처리하거나 기록할 원래 실패 객체
         * - stackTrace (StackTrace): 오류 진단에 함께 기록할 호출 스택
         * 반환값:
         * - 없음.
         */(Object error, StackTrace stackTrace) {
          _reportError(error, stackTrace);
          _handleDisconnected(socket, generation);
        },
        onDone: /* 함수이름: onDone 콜백
         * 함수역할: 웹소켓 종료를 현재 연결 세대에 대한 연결 해제로 처리한다.
         * 매개변수:
         * - 없음.
         * 반환값:
         * - 없음.
         */() => _handleDisconnected(socket, generation),
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
      _scheduleReconnect(generation);
    }
  }

  // 함수이름: _handleSocketData
  // 함수역할: 수신 문자열을 JSON 객체로 해석해 이벤트 스트림으로 전달하고 파싱 오류는 진단 로그에 남긴다.
  // 매개변수:
  // - rawData (dynamic): 해석 전 WebSocket 수신 데이터
  // 반환값:
  // - 없음.
  void _handleSocketData(dynamic rawData) {
    try {
      final decoded = jsonDecode(rawData.toString());
      if (decoded is Map) {
        _eventController.add(Map<String, dynamic>.from(decoded));
      }
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
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
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), /* 함수이름: periodic 콜백
     * 함수역할: 서비스가 시작 상태이고 같은 소켓 세대가 유지될 때만 ping을 전송한다.
     * 매개변수:
     * - _ (Timer): 콜백 계약으로 전달되지만 사용하지 않는 이벤트 값.
     * 반환값:
     * - 없음.
     */(_) {
      if (_started && generation == _generation && identical(_socket, socket)) {
        socket.add('ping');
      }
    });
  }

  // 함수이름: _handleDisconnected
  // 함수역할: 현재 소켓의 끊김에만 반응해 참조와 heartbeat를 정리하고 같은 세대의 재연결을 예약한다.
  // 매개변수:
  // - socket (WebSocket): 현재 heartbeat와 수신에 사용할 WebSocket
  // - generation (int): 이전 비동기 응답을 차단할 현재 작업 세대
  // 반환값:
  // - 없음.
  void _handleDisconnected(WebSocket socket, int generation) {
    if (!identical(_socket, socket)) {
      return;
    }
    _socket = null;
    _heartbeatTimer?.cancel();
    _scheduleReconnect(generation);
  }

  // 함수이름: _scheduleReconnect
  // 함수역할: 중복 예약과 이전 세대를 차단하고 1·2·5·10초로 늘어나는 지연 중 다음 연결 시도를 예약한다.
  // 매개변수:
  // - generation (int): 이전 비동기 응답을 차단할 현재 작업 세대
  // 반환값:
  // - 없음.
  void _scheduleReconnect(int generation) {
    if (!_started || generation != _generation || _reconnectTimer != null) {
      return;
    }
    _stateController.add(LinkedChatConnectionState.reconnecting);
    final index = _reconnectAttempt.clamp(0, _reconnectDelays.length - 1);
    final delay = _reconnectDelays[index];
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(delay, /* 함수이름: Timer 콜백
     * 함수역할: 재연결 예약 표시를 지운 뒤 같은 세대의 웹소켓 재접속을 시작한다.
     * 매개변수:
     * - 없음.
     * 반환값:
     * - 없음.
     */() {
      _reconnectTimer = null;
      unawaited(_connect(generation, reconnecting: true));
    });
  }

  // 함수이름: stop
  // 함수역할: 화면 종료 시 재연결과 heartbeat를 중지하고 소켓을 정상 종료한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> stop() async {
    if (!_started) {
      return;
    }
    _started = false;
    _generation += 1;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      await socket.close(WebSocketStatus.normalClosure);
    }
    _stateController.add(LinkedChatConnectionState.disconnected);
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
