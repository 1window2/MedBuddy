// 파일명: linked_chat_notification_monitor_service.dart
// 역할: 로컬 데모에서 연동된 가족의 새 채팅을 감시하고 기기 알림으로 변환한다.

import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../entities/chat_message_entity.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../entities/patient_hash_entity.dart';
import 'linked_chat_realtime_service.dart';

typedef LinkedChatLinkLoader = Future<List<PatientCaregiverLink>> Function();
typedef LinkedChatEventSourceFactory =
    LinkedChatEventSource Function(int linkId);
typedef LinkedChatAlertSender =
    Future<void> Function({required int linkId, required int messageId});
typedef LinkedChatPermissionRequester = Future<bool> Function();
typedef LinkedChatFeatureEnabledLoader = Future<bool> Function();

// 클래스명: LinkedChatNotificationMonitorService
// 역할:
// - Firebase 푸시를 사용하지 않는 로컬 데모에서 활성 연동별 WebSocket을 유지한다.
// - 상대가 보낸 새 메시지를 한 번만 개인정보 비노출 로컬 알림으로 표시한다.
// 주요 책임:
// - 연동 추가와 삭제를 주기적으로 동기화한다.
// - 본인이 보낸 메시지와 중복 이벤트를 알림 대상에서 제외한다.
// - 세션이 끝나면 모든 구독과 연결을 함께 정리한다.
class LinkedChatNotificationMonitorService {
  static const Duration defaultLinkRefreshInterval = Duration(seconds: 15);
  static const int _maximumRememberedMessageCount = 200;

  final String currentUserHash;
  final LinkedChatLinkLoader _loadLinks;
  final LinkedChatEventSourceFactory _eventSourceFactory;
  final LinkedChatAlertSender _sendAlert;
  final LinkedChatPermissionRequester _requestPermission;
  final LinkedChatFeatureEnabledLoader _isFeatureEnabled;
  final Duration linkRefreshInterval;
  final bool requestPermission;
  final VoidCallback? _onDispose;

  final Map<int, _LinkedChatWatcher> _watchers = <int, _LinkedChatWatcher>{};
  final LinkedHashSet<String> _notifiedMessageKeys = LinkedHashSet<String>();

  Timer? _refreshTimer;
  bool _isRefreshing = false;
  bool _isDisposed = false;
  bool _permissionRequested = false;
  bool _notificationPermissionGranted = true;
  Future<bool>? _permissionRequestFuture;

  LinkedChatNotificationMonitorService({
    required this.currentUserHash,
    required LinkedChatLinkLoader loadLinks,
    required LinkedChatEventSourceFactory eventSourceFactory,
    required LinkedChatAlertSender sendAlert,
    required LinkedChatPermissionRequester permissionRequester,
    LinkedChatFeatureEnabledLoader? featureEnabledLoader,
    this.linkRefreshInterval = defaultLinkRefreshInterval,
    this.requestPermission = true,
    VoidCallback? onDispose,
  }) : _loadLinks = loadLinks,
       _eventSourceFactory = eventSourceFactory,
       _sendAlert = sendAlert,
       _requestPermission = permissionRequester,
       _isFeatureEnabled = featureEnabledLoader ?? _alwaysEnabled,
       _onDispose = onDispose;

  static Future<bool> _alwaysEnabled() async => true;

  // 함수명: start
  // 역할:
  // - 현재 연동을 즉시 연결하고 이후 연동 목록 변경을 주기적으로 반영한다.
  Future<void> start() async {
    if (_isDisposed) {
      return;
    }
    await refreshNow();
    if (_isDisposed) {
      return;
    }
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(linkRefreshInterval, (_) {
      unawaited(refreshNow());
    });
  }

  // 함수명: refreshNow
  // 역할:
  // - 현재 사용자가 참여한 활성 연동과 실행 중인 실시간 감시 연결을 일치시킨다.
  // 반환값:
  // - 연동 목록을 정상적으로 반영했으면 true
  Future<bool> refreshNow() async {
    if (_isDisposed || _isRefreshing) {
      return false;
    }
    _isRefreshing = true;
    try {
      if (!await _isFeatureEnabled()) {
        await _removeStaleWatchers(const <int>{});
        return true;
      }
      final links = await _loadLinks();
      if (_isDisposed) {
        return false;
      }
      final activeLinkIds = _activeLinkIds(links);
      await _removeStaleWatchers(activeLinkIds);
      for (final linkId in activeLinkIds) {
        if (!_watchers.containsKey(linkId)) {
          await _addWatcher(linkId);
        }
      }
      return true;
    } catch (error, stackTrace) {
      developer.log(
        '가족 채팅 알림용 연동 목록을 갱신하지 못했습니다.',
        name: 'LinkedChatNotificationMonitorService',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  Set<int> _activeLinkIds(List<PatientCaregiverLink> links) {
    final normalizedUserHash = PatientHash.normalizePatientHash(
      currentUserHash,
    );
    return links
        .where((link) {
          final linkId = link.linkId;
          if (!link.linkStatus || linkId == null || linkId < 1) {
            return false;
          }
          return PatientHash.normalizePatientHash(link.patientHash) ==
                  normalizedUserHash ||
              PatientHash.normalizePatientHash(link.caregiverHash) ==
                  normalizedUserHash;
        })
        .map((link) => link.linkId!)
        .toSet();
  }

  Future<void> _removeStaleWatchers(Set<int> activeLinkIds) async {
    final staleLinkIds = _watchers.keys
        .where((linkId) => !activeLinkIds.contains(linkId))
        .toList(growable: false);
    for (final linkId in staleLinkIds) {
      final watcher = _watchers.remove(linkId);
      if (watcher != null) {
        await watcher.dispose();
      }
    }
  }

  Future<void> _addWatcher(int linkId) async {
    if (_isDisposed || _watchers.containsKey(linkId)) {
      return;
    }
    final source = _eventSourceFactory(linkId);
    late final StreamSubscription<Map<String, dynamic>> subscription;
    subscription = source.events.listen(
      (event) => unawaited(_handleEvent(linkId, event)),
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          '가족 채팅 알림 이벤트 수신 중 오류가 발생했습니다.',
          name: 'LinkedChatNotificationMonitorService',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
    final watcher = _LinkedChatWatcher(
      source: source,
      subscription: subscription,
    );
    _watchers[linkId] = watcher;
    try {
      await source.start();
    } catch (error, stackTrace) {
      if (identical(_watchers[linkId], watcher)) {
        _watchers.remove(linkId);
      }
      await watcher.dispose();
      developer.log(
        '가족 채팅 알림 연결을 시작하지 못했습니다.',
        name: 'LinkedChatNotificationMonitorService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _handleEvent(
    int watchedLinkId,
    Map<String, dynamic> event,
  ) async {
    if (_isDisposed || event['type']?.toString() != 'chat_message') {
      return;
    }
    final rawMessage = event['message'];
    if (rawMessage is! Map) {
      return;
    }
    try {
      final message = ChatMessage.fromJson(
        Map<String, dynamic>.from(rawMessage),
      );
      if (message.linkId != watchedLinkId ||
          PatientHash.normalizePatientHash(message.senderHash) ==
              PatientHash.normalizePatientHash(currentUserHash)) {
        return;
      }
      // 실험실 기능을 끈 직후 수신된 이벤트도 알림으로 노출하지 않는다.
      if (!await _isFeatureEnabled()) {
        return;
      }
      final messageKey = '$watchedLinkId:${message.messageId}';
      if (!_rememberMessage(messageKey)) {
        return;
      }
      if (!await _ensureNotificationPermission()) {
        _notifiedMessageKeys.remove(messageKey);
        return;
      }
      try {
        await _sendAlert(linkId: watchedLinkId, messageId: message.messageId);
      } catch (error, stackTrace) {
        _notifiedMessageKeys.remove(messageKey);
        developer.log(
          '새 가족 메시지 알림을 표시하지 못했습니다.',
          name: 'LinkedChatNotificationMonitorService',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } on FormatException {
      // 형식이 불완전한 실시간 이벤트는 다음 정상 메시지 수신을 방해하지 않게 건너뛴다.
    }
  }

  bool _rememberMessage(String messageKey) {
    if (!_notifiedMessageKeys.add(messageKey)) {
      return false;
    }
    while (_notifiedMessageKeys.length > _maximumRememberedMessageCount) {
      _notifiedMessageKeys.remove(_notifiedMessageKeys.first);
    }
    return true;
  }

  Future<bool> _ensureNotificationPermission() async {
    if (!requestPermission) {
      return true;
    }
    final pendingRequest = _permissionRequestFuture;
    if (pendingRequest != null) {
      return pendingRequest;
    }
    if (_permissionRequested) {
      return _notificationPermissionGranted;
    }
    _permissionRequested = true;
    final request = _requestPermission();
    _permissionRequestFuture = request;
    try {
      _notificationPermissionGranted = await request;
      return _notificationPermissionGranted;
    } finally {
      _permissionRequestFuture = null;
    }
  }

  // 함수명: dispose
  // 역할:
  // - 세션 종료 시 주기 작업과 모든 연동별 WebSocket을 정리한다.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final watchers = _watchers.values.toList(growable: false);
    _watchers.clear();
    for (final watcher in watchers) {
      await watcher.dispose();
    }
    _onDispose?.call();
  }
}

class _LinkedChatWatcher {
  final LinkedChatEventSource source;
  final StreamSubscription<Map<String, dynamic>> subscription;

  const _LinkedChatWatcher({required this.source, required this.subscription});

  Future<void> dispose() async {
    await subscription.cancel();
    await source.dispose();
  }
}
