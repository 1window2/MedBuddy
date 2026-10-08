// 파일명: manage_notification_inbox_control.dart
// 역할: 알림 목록 조회·읽음·삭제와 화면 갱신을 조율한다.
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../entities/caregiver_alert_context_entity.dart';
import '../entities/notification_inbox_entity.dart';
import '../services/notification_inbox_store.dart';
import 'manage_chat_list_control.dart';

// 클래스명: ManageNotificationInbox
// 역할: 로그인 계정의 로컬 알림함 상태와 명령을 제공한다.
class ManageNotificationInbox extends ChangeNotifier {
  final NotificationInboxStore store;
  final ManageChatList? _chatList;
  List<NotificationInboxEntry> _entries = const [];
  // 외부에서는 읽기만 하고 값은 이 객체만 바꾼다.
  List<NotificationInboxEntry> get entries => _entries;
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  bool _hasError = false;
  bool get hasError => _hasError;
  bool _disposed = false;
  // 조회 진행 여부. isLoading은 화면에 불러오는 중 표시가 필요한 첫 조회 동안에만 참이다.
  bool _refreshing = false;
  bool _loadedOnce = false;
  bool _refreshAgain = false;
  // 화면에 마지막으로 알린 상대 이름. 이름이 실제로 바뀔 때만 다시 알린다.
  String _peerNameSignature = '';
  Timer? _timer;
  late final StreamSubscription<String> _subscription;

  // 함수이름: ManageNotificationInbox
  // 함수역할: 같은 계정의 수신 이벤트와 상대 이름 변경을 구독한다. 주입된 채팅 제어기는 소유하지 않는다.
  // 매개변수: store, 선택적 chatList. 반환값: 제어기. 서로 다른 계정이면 인수 오류.
  ManageNotificationInbox({required this.store, ManageChatList? chatList})
    : _chatList = chatList {
    if (chatList != null && chatList.userHash != store.userHash) {
      throw ArgumentError('Chat list and inbox must belong to the same user.');
    }
    _peerNameSignature = _currentPeerNameSignature();
    _chatList?.addListener(_onPeerNamesChanged);
    _subscription = NotificationInboxStore.changes.stream.listen((userHash) {
      if (userHash == store.userHash) unawaited(refresh());
    });
  }

  // 함수이름: unreadCount
  // 함수역할: 보이는 알림의 미확인 수를 반환한다. 매개변수: 없음. 반환값: 개수.
  int get unreadCount => _entries.where((entry) => !entry.isRead).length;

  // 함수이름: titleFor
  // 함수역할: 채팅·보호자 알림에 현재 활성 연동의 별칭을 표시하며 저장 원본은 변경하지 않는다.
  // 매개변수: entry, isEnglish, showSensitiveDetails. 반환값: 상대 별칭 또는 기존 알림 제목.
  String titleFor(
    NotificationInboxEntry entry, {
    required bool isEnglish,
    bool showSensitiveDetails = true,
  }) {
    final chatList = _chatList;
    if (_isCaregiverEntry(entry)) {
      if (!showSensitiveDetails) {
        return isEnglish ? 'Medication update' : '복약 상태 알림';
      }
      if (chatList == null) return entry.title;
      final patientHash = _caregiverEntryPatientHash(entry);
      if (patientHash == null) return entry.title;
      for (final link in chatList.links) {
        if (link.linkStatus &&
            link.caregiverHash == store.userHash &&
            link.patientHash == patientHash &&
            patientHash.isNotEmpty &&
            patientHash != store.userHash) {
          return chatList.peerName(link, isEnglish: isEnglish);
        }
      }
      return entry.title;
    }
    if (!showSensitiveDetails ||
        entry.category != NotificationInboxCategory.chat ||
        chatList == null) {
      return entry.title;
    }
    final match = RegExp(r'^chat:([1-9]\d*)$').firstMatch(entry.payload);
    final linkId = int.tryParse(match?.group(1) ?? '');
    if (linkId == null) return entry.title;
    for (final link in chatList.links) {
      if (link.linkId == linkId &&
          link.linkStatus &&
          (link.patientHash == store.userHash ||
              link.caregiverHash == store.userHash)) {
        return chatList.peerName(link, isEnglish: isEnglish);
      }
    }
    return entry.title;
  }

  // 함수이름: bodyFor
  // 함수역할: 실제 수신 내용을 표시하되 내용 숨김으로 바꾸면 이전 보호자 알림도 가린다.
  // 매개변수: entry는 저장 알림, isEnglish는 언어, showSensitiveDetails는 공개 설정.
  // 반환값: 수신 시점의 설명 또는 일반 상태 안내. 과거 상태를 현재 일정으로 추측하지 않는다.
  String bodyFor(
    NotificationInboxEntry entry, {
    required bool isEnglish,
    bool showSensitiveDetails = true,
  }) {
    if (_isCaregiverEntry(entry) && !showSensitiveDetails) {
      return isEnglish
          ? 'Check your linked patient\'s medication status.'
          : '연동된 환자의 복약 상태를 확인해 주세요.';
    }
    return entry.body;
  }

  // 함수이름: _isCaregiverEntry
  // 함수역할: 분류와 이동 경로가 모두 보호자 알림인지 확인한다.
  // 매개변수: entry는 검사할 알림. 반환값: 보호자 복약 알림 여부.
  bool _isCaregiverEntry(NotificationInboxEntry entry) =>
      entry.category == NotificationInboxCategory.medication &&
      (entry.payload.startsWith('caregiver:') ||
          entry.payload.startsWith('caregiver-v1:'));

  // 함수이름: _caregiverEntryPatientHash
  // 함수역할: 보호자 알림의 이동 경로에서 환자 해시를 읽는다. 완료 알림(caregiver:)과 동작 버튼이 있는
  //   미복용 알림(caregiver-v1:)은 형식이 다르므로 각각 해석한다.
  // 매개변수: entry는 보호자 알림. 반환값: 환자 해시 또는 해석할 수 없으면 null.
  String? _caregiverEntryPatientHash(NotificationInboxEntry entry) {
    if (entry.payload.startsWith('caregiver-v1:')) {
      return CaregiverAlertContext.fromPayload(entry.payload)?.patientHash;
    }
    try {
      return Uri.decodeComponent(entry.payload.substring('caregiver:'.length));
    } on ArgumentError {
      return null;
    }
  }

  // 함수이름: _currentPeerNameSignature
  // 함수역할: 알림 제목에 쓰이는 활성 연동과 상대 이름을 한 문자열로 만들어 이전 상태와 비교할 수 있게 한다.
  // 매개변수: 없음. 반환값: 채팅 목록이 없으면 빈 문자열.
  String _currentPeerNameSignature() {
    final chatList = _chatList;
    if (chatList == null) return '';
    return [
      for (final link in chatList.links)
        if (link.linkStatus)
          [
            link.linkId,
            link.patientHash,
            link.caregiverHash,
            chatList.peerName(link, isEnglish: false),
            chatList.peerName(link, isEnglish: true),
          ].join('\u0001'),
    ].join('\u0002');
  }

  // 함수이름: _onPeerNamesChanged
  // 함수역할: 별칭 변경·연동 해제를 기존 알림 제목에도 반영한다. 채팅 목록의 다른 변경은 알리지 않는다.
  // 매개변수: 없음. 반환값: 없음.
  void _onPeerNamesChanged() {
    if (_disposed) return;
    final signature = _currentPeerNameSignature();
    if (signature == _peerNameSignature) return;
    _peerNameSignature = signature;
    notifyListeners();
  }

  // 함수이름: start
  // 함수역할: 앱 전경에서 예약 시각과 백그라운드 기록을 갱신한다. 매개변수: 없음. 반환값: 없음.
  void start() {
    _timer?.cancel();
    unawaited(refresh());
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
  }

  // 함수이름: stop
  // 함수역할: 앱 비활성 상태의 폴링을 중지한다. 매개변수: 없음. 반환값: 없음.
  void stop() => _timer?.cancel();

  // 함수이름: refresh
  // 함수역할: 동시 조회를 합치고 실패하면 기존 목록을 유지한다. 아직 한 번도 불러오지 못해 불러오는 중 표시가
  //   필요할 때와, 조회 뒤 목록·읽음 상태·오류 상태가 실제로 바뀌었을 때만 화면에 알린다.
  // 매개변수: 없음. 반환값: 조회 완료.
  Future<void> refresh() async {
    if (_disposed) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    // 이미 불러온 목록(빈 목록 포함)은 그대로 보여 주므로 주기 갱신의 시작은 알리지 않는다.
    final announcedLoading = !_loadedOnce;
    if (announcedLoading) {
      _isLoading = true;
      notifyListeners();
    }
    final previousEntries = _entries;
    final previousError = _hasError;
    try {
      final loaded = await store.load();
      if (!_disposed) {
        _entries = loaded;
        _hasError = false;
        _loadedOnce = true;
      }
    } catch (_) {
      if (!_disposed) _hasError = true;
    } finally {
      _refreshing = false;
      _isLoading = false;
      if (!_disposed) {
        if (announcedLoading ||
            _hasError != previousError ||
            !_sameVisibleEntries(previousEntries, _entries)) {
          notifyListeners();
        }
        if (_refreshAgain) {
          _refreshAgain = false;
          unawaited(refresh());
        }
      }
    }
  }

  // 함수이름: _sameVisibleEntries
  // 함수역할: 두 목록의 순서·항목·읽음 상태가 같은지 비교한다. 저장된 알림의 내용은 바뀌지 않으므로 ID와 읽음 여부만 본다.
  // 매개변수: before, after: 비교할 목록. 반환값: 화면에 보이는 내용이 같으면 true.
  bool _sameVisibleEntries(
    List<NotificationInboxEntry> before,
    List<NotificationInboxEntry> after,
  ) {
    if (identical(before, after)) return true;
    if (before.length != after.length) return false;
    for (var index = 0; index < before.length; index++) {
      if (before[index].id != after[index].id ||
          before[index].isRead != after[index].isRead) {
        return false;
      }
    }
    return true;
  }

  // 함수이름: markRead
  // 함수역할: 선택 항목 또는 현재 목록 전체를 읽음 처리한다. 매개변수: 선택적 entry. 반환값: 갱신 완료.
  Future<void> markRead([NotificationInboxEntry? entry]) async {
    await store.markRead(entry == null ? _entries.map((e) => e.id) : [entry.id]);
    await refresh();
  }

  // 함수이름: remove
  // 함수역할: 알림 내역만 삭제하며 채팅·복약 기록에는 영향이 없다. 매개변수: 선택적 entry. 반환값: 갱신 완료.
  Future<void> remove([NotificationInboxEntry? entry]) async {
    await removeEntries(entry == null ? _entries : [entry]);
  }

  // 함수이름: removeEntries
  // 함수역할: 선택한 알림만 삭제하여 확인 중 새로 도착한 항목을 보존한다.
  // 매개변수: selected: 삭제를 요청한 시점의 선택 목록. 반환값: 저장과 화면 갱신 완료.
  Future<void> removeEntries(Iterable<NotificationInboxEntry> selected) async {
    final ids = selected.map((entry) => entry.id).toSet();
    await store.remove(ids);
    await refresh();
  }

  // 함수이름: dispose
  // 함수역할: 알림함의 타이머와 구독을 종료한다. 매개변수: 없음. 반환값: 없음.
  @override
  void dispose() {
    _disposed = true;
    _chatList?.removeListener(_onPeerNamesChanged);
    stop();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
