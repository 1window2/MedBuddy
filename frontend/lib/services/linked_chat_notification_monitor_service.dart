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

// 함수이름: LinkedChatLinkLoader
// 함수역할: 현재 사용자가 참여한 활성 가족 연동 목록을 조회하는 경계이다.
// 매개변수:
// - 없음.
// 반환값:
// - Future<List<PatientCaregiverLink>>: 현재 사용자가 참여한 활성 가족 연동 목록을 조회하는 경계이다.
typedef LinkedChatLinkLoader = Future<List<PatientCaregiverLink>> Function();
// 함수이름: LinkedChatEventSourceFactory
// 함수역할: 한 연동 ID의 실시간 채팅 이벤트 소스를 생성해 감시 서비스에 제공하는 계약이다.
// 매개변수:
// - linkId (int): 조회·전송·감시 대상 연동 ID
// 반환값:
// - LinkedChatEventSource: 한 연동 ID의 실시간 채팅 이벤트 소스를 생성해 감시 서비스에 제공하는 계약이다.
typedef LinkedChatEventSourceFactory =
    LinkedChatEventSource Function(int linkId);
// 함수이름: LinkedChatAlertSender
// 함수역할: 연동·메시지 식별자, 본문, 유형과 시간대로 새 가족 메시지 알림을 표시하는 경계이다.
// 매개변수:
// - linkId (int): 조회·전송·감시 대상 연동 ID
// - messageId (int): 서버가 부여한 채팅 메시지 ID
// - messageBody (String): 전송하거나 표시할 메시지·알림 본문
// - messageKind (ChatMessageKind): 일반·복약·약국 맥락 메시지 유형
// - slotKey (String?): morning·lunch·evening·bedtime 복약 시간대 키
// 반환값:
// - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
typedef LinkedChatAlertSender =
    Future<void> Function({
      required int linkId,
      required int messageId,
      required String messageBody,
      required ChatMessageKind messageKind,
      required String? slotKey,
    });
// 함수이름: LinkedChatPermissionRequester
// 함수역할: 가족 채팅 로컬 알림의 표시 권한을 요청하고 허용 여부를 제공하는 계약이다.
// 매개변수:
// - 없음.
// 반환값:
// - Future<bool>: 가족 채팅 로컬 알림의 표시 권한을 요청하고 허용 여부를 제공하는 계약이다.
typedef LinkedChatPermissionRequester = Future<bool> Function();
// 함수이름: LinkedChatFeatureEnabledLoader
// 함수역할: 현재 사용자의 복약 맥락 채팅 실험 기능 활성 여부를 비동기로 조회하는 계약이다.
// 매개변수:
// - 없음.
// 반환값:
// - Future<bool>: 현재 사용자의 복약 맥락 채팅 실험 기능 활성 여부를 비동기로 조회하는 계약이다.
typedef LinkedChatFeatureEnabledLoader = Future<bool> Function();

// 클래스명: LinkedChatNotificationMonitorService
// 역할: Firebase 푸시를 사용하지 않는 로컬 데모에서 활성 연동별 WebSocket을 유지한다. 상대가 보낸 새 메시지를 한 번만 내용 미리보기와 함께 로컬 알림으로 표시한다.
// 주요 책임:
// - 연동 추가와 삭제를 주기적으로 동기화한다.
// - 본인이 보낸 메시지와 중복 이벤트를 알림 대상에서 제외한다.
// - 세션이 끝나면 모든 구독과 연결을 함께 정리한다.
// 속성:
// - currentUserHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
// - _loadLinks (LinkedChatLinkLoader): 활성 환자·보호자 연동 조회 경계
// - _eventSourceFactory (LinkedChatEventSourceFactory): 연동 ID별 이벤트 소스 생성 경계
// - _sendAlert (LinkedChatAlertSender): 실제 로컬 알림 표시를 수행할 경계
// - _requestPermission (LinkedChatPermissionRequester): 감시 중 운영체제 권한 요청을 수행할지 여부
// - linkRefreshInterval (Duration): 활성 채팅 연동 목록 갱신 간격
// - requestPermission (bool): 감시 중 운영체제 권한 요청을 수행할지 여부
// - _onDispose (VoidCallback?): 소유한 의존성 정리 콜백
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

  // 함수이름: LinkedChatNotificationMonitorService
  // 함수역할: 현재 사용자와 연동 조회·이벤트 소스·알림·권한·실험 기능 경계를 묶고 연동 갱신 주기 및 종료 콜백을 설정한다.
  // 매개변수:
  // - currentUserHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // - loadLinks (LinkedChatLinkLoader): 활성 환자·보호자 연동 조회 경계
  // - eventSourceFactory (LinkedChatEventSourceFactory): 연동 ID별 이벤트 소스 생성 경계
  // - sendAlert (LinkedChatAlertSender): 실제 로컬 알림 표시를 수행할 경계
  // - permissionRequester (LinkedChatPermissionRequester): 기기 알림 권한 요청 경계
  // - featureEnabledLoader (LinkedChatFeatureEnabledLoader?): 채팅 실험 기능 활성 여부 조회 경계
  // - linkRefreshInterval (Duration): 활성 채팅 연동 목록 갱신 간격
  // - requestPermission (bool): 감시 중 운영체제 권한 요청을 수행할지 여부
  // - onDispose (VoidCallback?): 소유한 의존성 정리 콜백
  // 반환값:
  // - LinkedChatNotificationMonitorService: 초기화된 인스턴스.
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

  // 함수이름: _alwaysEnabled
  // 함수역할: 별도 기능 허용 조회가 없을 때 채팅 감시를 활성 상태로 처리하는 기본 비동기 값을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 별도 기능 허용 조회가 없을 때 채팅 감시를 활성 상태로 처리하는 기본 비동기 값을 제공한다.
  static Future<bool> _alwaysEnabled() async => true;

  // 함수이름: start
  // 함수역할: 현재 연동을 즉시 연결하고 이후 연동 목록 변경을 주기적으로 반영한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> start() async {
    if (_isDisposed) {
      return;
    }
    await refreshNow();
    if (_isDisposed) {
      return;
    }
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(linkRefreshInterval, /* 함수이름: periodic 콜백
     * 함수역할: 주기마다 활성 가족 연결과 채팅 구독을 비동기로 새로 확인한다.
     * 매개변수:
     * - _ (Timer): 콜백 계약으로 전달되지만 사용하지 않는 이벤트 값.
     * 반환값:
     * - 없음.
     */(_) {
      unawaited(refreshNow());
    });
  }

  // 함수이름: refreshNow
  // 함수역할: 현재 사용자가 참여한 활성 연동과 실행 중인 실시간 감시 연결을 일치시킨다.
  // 매개변수:
  // - 없음.
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

  // 함수이름: _activeLinkIds
  // 함수역할: 현재 사용자가 환자 또는 보호자로 참여한 활성 연동 중 양수 ID만 중복 없이 모은다.
  // 매개변수:
  // - links (List<PatientCaregiverLink>): 참여자·활성 상태를 확인할 환자·보호자 연동 목록
  // 반환값:
  // - Set<int>: 현재 사용자가 환자 또는 보호자로 참여한 활성 연동 중 양수 ID만 중복 없이 모은다.
  Set<int> _activeLinkIds(List<PatientCaregiverLink> links) {
    final normalizedUserHash = PatientHash.normalizePatientHash(
      currentUserHash,
    );
    return links
        .where(/* 함수이름: where 콜백
         * 함수역할: 현재 사용자가 환자 또는 보호자인 유효한 활성 가족 연결만 선택한다.
         * 매개변수:
         * - link (PatientCaregiverLink): 해당 환자·보호자 연동 관계
         * 반환값:
         * - 현재 사용자에게 속한 양의 연결 ID의 활성 연결이면 true.
         */(link) {
          final linkId = link.linkId;
          if (!link.linkStatus || linkId == null || linkId < 1) {
            return false;
          }
          return PatientHash.normalizePatientHash(link.patientHash) ==
                  normalizedUserHash ||
              PatientHash.normalizePatientHash(link.caregiverHash) ==
                  normalizedUserHash;
        })
        .map(/* 함수이름: map 콜백
         * 함수역할: 유효성 검사를 마친 가족 연결에서 연결 ID를 추출한다.
         * 매개변수:
         * - link (PatientCaregiverLink): 해당 환자·보호자 연동 관계
         * 반환값:
         * - null이 아닌 활성 연결 ID.
         */(link) => link.linkId!)
        .toSet();
  }

  // 함수이름: _removeStaleWatchers
  // 함수역할: 더 이상 활성 연동에 포함되지 않는 감시 항목을 제거하고 해당 구독과 이벤트 소스를 종료한다.
  // 매개변수:
  // - activeLinkIds (Set<int>): 감시를 유지할 활성 연동 ID 집합
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _removeStaleWatchers(Set<int> activeLinkIds) async {
    final staleLinkIds = _watchers.keys
        .where(/* 함수이름: where 콜백
         * 함수역할: 더 이상 활성 목록에 없는 구독 연결을 찾는다.
         * 매개변수:
         * - linkId (int): 조회·전송·감시 대상 연동 ID
         * 반환값:
         * - 현재 활성 연결 집합에 없으면 true.
         */(linkId) => !activeLinkIds.contains(linkId))
        .toList(growable: false);
    for (final linkId in staleLinkIds) {
      final watcher = _watchers.remove(linkId);
      if (watcher != null) {
        await watcher.dispose();
      }
    }
  }

  // 함수이름: _addWatcher
  // 함수역할: 연동의 이벤트 소스와 구독을 만들고 연결을 시작하며 시작 실패 시 동일 감시 항목과 자원을 정리한다.
  // 매개변수:
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _addWatcher(int linkId) async {
    if (_isDisposed || _watchers.containsKey(linkId)) {
      return;
    }
    final source = _eventSourceFactory(linkId);
    late final StreamSubscription<Map<String, dynamic>> subscription;
    subscription = source.events.listen(
      // 함수이름: listen 콜백
      // 함수역할: 수신한 채팅 이벤트를 해당 가족 연결의 알림 처리기로 전달한다.
      // 매개변수:
      // - event (Map<String, dynamic>): 소켓에서 받은 구조화된 채팅 이벤트
      // 반환값:
      // - 없음; 이벤트 처리는 비동기로 이어진다.
      (event) => unawaited(_handleEvent(linkId, event)),
      onError: /* 함수이름: onError 콜백
       * 함수역할: 가족 채팅 이벤트 구독 실패를 오류와 스택 정보로 기록한다.
       * 매개변수:
       * - error (Object): 처리하거나 기록할 원래 실패 객체
       * - stackTrace (StackTrace): 오류 진단에 함께 기록할 호출 스택
       * 반환값:
       * - 없음.
       */(Object error, StackTrace stackTrace) {
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

  // 함수이름: _handleEvent
  // 함수역할: 유효한 상대방 새 메시지만 처리하고 연동·기능·중복·권한을 확인한 뒤 알림을 보내며 권한 거절이나 전송 실패는 재시도 가능하게 기록을 되돌린다.
  // 매개변수:
  // - watchedLinkId (int): 조회·전송·감시 대상 연동 ID
  // - event (Map<String, dynamic>): 소켓에서 받은 구조화된 채팅 이벤트
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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
        await _sendAlert(
          linkId: watchedLinkId,
          messageId: message.messageId,
          messageBody: message.body,
          messageKind: message.messageKind,
          slotKey: message.scheduleContext?.slotKey,
        );
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

  // 함수이름: _rememberMessage
  // 함수역할: 처음 본 연동·메시지 키만 등록하고 중복 방지 기록이 200개를 넘으면 가장 오래된 키부터 버린다.
  // 매개변수:
  // - messageKey (String): 연동과 메시지 ID를 합친 중복 방지 키
  // 반환값:
  // - bool: 처음 본 연동·메시지 키만 등록하고 중복 방지 기록이 200개를 넘으면 가장 오래된 키부터 버린다.
  bool _rememberMessage(String messageKey) {
    if (!_notifiedMessageKeys.add(messageKey)) {
      return false;
    }
    while (_notifiedMessageKeys.length > _maximumRememberedMessageCount) {
      _notifiedMessageKeys.remove(_notifiedMessageKeys.first);
    }
    return true;
  }

  // 함수이름: _ensureNotificationPermission
  // 함수역할: 권한 요청 생략 정책을 적용하고 진행 중 권한 요청 또는 최초 결과를 재사용한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 권한 요청 생략 정책을 적용하고 진행 중 권한 요청 또는 최초 결과를 재사용한다.
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

  // 함수이름: dispose
  // 함수역할: 세션 종료 시 주기 작업과 모든 연동별 WebSocket을 정리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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

// 클래스명: _LinkedChatWatcher
// 역할: 한 연동의 이벤트 소스와 스트림 구독을 함께 소유한다.
// 주요 책임:
// - 감시 제거 시 구독을 먼저 취소한 뒤 연결 자원을 해제한다.
// 속성:
// - source (LinkedChatEventSource): 해당 가족 연결의 실시간 이벤트 소스
// - subscription (StreamSubscription<Map<String, dynamic>>): 이벤트 소스와 함께 정리할 수신 구독
class _LinkedChatWatcher {
  final LinkedChatEventSource source;
  final StreamSubscription<Map<String, dynamic>> subscription;

  // 함수이름: _LinkedChatWatcher
  // 함수역할: 연동 이벤트 소스와 수신 구독을 함께 묶어 동일 수명으로 관리한다.
  // 매개변수:
  // - source (LinkedChatEventSource): 해당 가족 연결의 실시간 이벤트 소스
  // - subscription (StreamSubscription<Map<String, dynamic>>): 이벤트 소스와 함께 정리할 수신 구독
  // 반환값:
  // - _LinkedChatWatcher: 초기화된 인스턴스.
  const _LinkedChatWatcher({required this.source, required this.subscription});

  // 함수이름: dispose
  // 함수역할: 이벤트 수신 구독을 취소한 다음 연동 이벤트 소스를 종료한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> dispose() async {
    await subscription.cancel();
    await source.dispose();
  }
}
