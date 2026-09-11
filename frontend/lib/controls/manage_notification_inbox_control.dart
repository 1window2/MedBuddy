// 파일명: manage_notification_inbox_control.dart
// 역할: 알림 목록 조회·읽음·삭제와 화면 갱신을 조율한다.
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../entities/notification_inbox_entity.dart';
import '../services/notification_inbox_store.dart';

// 클래스명: ManageNotificationInbox
// 역할: 로그인 계정의 로컬 알림함 상태와 명령을 제공한다.
class ManageNotificationInbox extends ChangeNotifier {
  final NotificationInboxStore store;
  List<NotificationInboxEntry> entries = const [];
  bool isLoading = false;
  bool hasError = false;
  bool _disposed = false;
  bool _refreshAgain = false;
  Timer? _timer;
  late final StreamSubscription<String> _subscription;

  // 함수이름: ManageNotificationInbox
  // 함수역할: 같은 계정의 수신 이벤트를 구독한다. 매개변수: store. 반환값: 제어기.
  ManageNotificationInbox({required this.store}) {
    _subscription = NotificationInboxStore.changes.stream.listen((userHash) {
      if (userHash == store.userHash) unawaited(refresh());
    });
  }

  // 함수이름: unreadCount
  // 함수역할: 보이는 알림의 미확인 수를 반환한다. 매개변수: 없음. 반환값: 개수.
  int get unreadCount => entries.where((entry) => !entry.isRead).length;

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
  // 함수역할: 동시 조회를 합치고 실패하면 기존 목록을 유지한다. 매개변수: 없음. 반환값: 조회 완료.
  Future<void> refresh() async {
    if (_disposed) return;
    if (isLoading) {
      _refreshAgain = true;
      return;
    }
    isLoading = true;
    notifyListeners();
    try {
      final loaded = await store.load();
      if (!_disposed) {
        entries = loaded;
        hasError = false;
      }
    } catch (_) {
      if (!_disposed) hasError = true;
    } finally {
      isLoading = false;
      if (!_disposed) {
        notifyListeners();
        if (_refreshAgain) {
          _refreshAgain = false;
          unawaited(refresh());
        }
      }
    }
  }

  // 함수이름: markRead
  // 함수역할: 선택 항목 또는 현재 목록 전체를 읽음 처리한다. 매개변수: 선택적 entry. 반환값: 갱신 완료.
  Future<void> markRead([NotificationInboxEntry? entry]) async {
    await store.markRead(entry == null ? entries.map((e) => e.id) : [entry.id]);
    await refresh();
  }

  // 함수이름: remove
  // 함수역할: 알림 내역만 삭제하며 채팅·복약 기록에는 영향이 없다. 매개변수: 선택적 entry. 반환값: 갱신 완료.
  Future<void> remove([NotificationInboxEntry? entry]) async {
    await store.remove(entry == null ? entries.map((e) => e.id) : [entry.id]);
    await refresh();
  }

  // 함수이름: dispose
  // 함수역할: 알림함의 타이머와 구독을 종료한다. 매개변수: 없음. 반환값: 없음.
  @override
  void dispose() {
    _disposed = true;
    stop();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
