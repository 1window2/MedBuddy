// 파일명: linked_chat_realtime_service.dart
// 역할: 채팅 WebSocket 연결, 재연결, 실시간 이벤트 수신을 캡슐화한다.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'api_config.dart';
import 'auth_config.dart';
import 'authenticated_api_client.dart';

// 인터페이스명: LinkedChatEventSource
// 역할:
// - 채팅 이벤트 소비자가 구체 WebSocket 구현에 의존하지 않도록 연결 계약을 제공한다.
abstract interface class LinkedChatEventSource {
  Stream<Map<String, dynamic>> get events;

  Future<void> start();

  Future<void> dispose();
}

enum LinkedChatConnectionState {
  connecting,
  connected,
  reconnecting,
  disconnected,
}

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

  LinkedChatRealtimeService({
    required this.linkId,
    required this.userHash,
    required this.authenticationClient,
  });

  @override
  Stream<Map<String, dynamic>> get events => _eventController.stream;
  Stream<LinkedChatConnectionState> get states => _stateController.stream;

  // 함수명: start
  // 역할:
  // - 채팅 실시간 연결을 한 번 시작하고 끊기면 제한된 간격으로 재연결한다.
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
        onError: (Object error, StackTrace stackTrace) {
          _reportError(error, stackTrace);
          _handleDisconnected(socket, generation);
        },
        onDone: () => _handleDisconnected(socket, generation),
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
      _scheduleReconnect(generation);
    }
  }

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

  void _startHeartbeat(WebSocket socket, int generation) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_started && generation == _generation && identical(_socket, socket)) {
        socket.add('ping');
      }
    });
  }

  void _handleDisconnected(WebSocket socket, int generation) {
    if (!identical(_socket, socket)) {
      return;
    }
    _socket = null;
    _heartbeatTimer?.cancel();
    _scheduleReconnect(generation);
  }

  void _scheduleReconnect(int generation) {
    if (!_started || generation != _generation || _reconnectTimer != null) {
      return;
    }
    _stateController.add(LinkedChatConnectionState.reconnecting);
    final index = _reconnectAttempt.clamp(0, _reconnectDelays.length - 1);
    final delay = _reconnectDelays[index];
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_connect(generation, reconnecting: true));
    });
  }

  // 함수명: stop
  // 역할:
  // - 화면 종료 시 재연결과 heartbeat를 중지하고 소켓을 정상 종료한다.
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

  @override
  Future<void> dispose() async {
    await stop();
    await _eventController.close();
    await _stateController.close();
  }

  void _reportError(Object error, StackTrace stackTrace) {
    developer.log(
      '채팅 실시간 연결을 처리하지 못했습니다.',
      name: 'LinkedChatRealtimeService',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
