// 파일명: notification_inbox_ui_boundary.dart
// 역할: 받은 알림을 최신순으로 모아 보여주고 읽음·삭제·관련 화면 이동을 제공한다.
import 'package:flutter/material.dart';
import '../controls/manage_notification_inbox_control.dart';
import '../entities/notification_inbox_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 클래스명: NotificationInboxUI
// 역할: 알림함 화면. 목록과 저장 명령은 Control에 위임한다.
class NotificationInboxUI extends StatefulWidget {
  final ManageNotificationInbox control;
  final UserSetting userSetting;
  final ValueChanged<NotificationInboxEntry> onOpen;

  // 함수이름: NotificationInboxUI
  // 함수역할: 계정별 제어기와 설정·이동 콜백을 연결한다. 매개변수: control, userSetting, onOpen. 반환값: 화면.
  const NotificationInboxUI({
    super.key,
    required this.control,
    required this.userSetting,
    required this.onOpen,
  });

  // 함수이름: createState
  // 함수역할: 알림 작업 상태를 생성한다. 매개변수: 없음. 반환값: 화면 상태.
  @override
  State<NotificationInboxUI> createState() => _NotificationInboxUIState();
}

// 클래스명: _NotificationInboxUIState
// 역할: 알림 확인 창을 관리하며 큰 글씨에서도 통합 목록의 전체 내용을 표시한다.
class _NotificationInboxUIState extends State<NotificationInboxUI> {
  bool _busy = false;

  // 함수이름: _english
  // 함수역할: 현재 언어를 판별한다. 매개변수: 없음. 반환값: 영어 여부.
  bool get _english => widget.userSetting.language == 'en';

  // 함수이름: initState
  // 함수역할: 열릴 때 최신 기록을 조회한다. 매개변수: 없음. 반환값: 없음.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.control.refresh();
    });
  }

  // 함수이름: _run
  // 함수역할: 중복 클릭을 막고 저장 오류를 안내한다. 매개변수: action. 반환값: 명령 완료.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _english
                  ? 'Could not update notifications. Please try again.'
                  : '알림을 변경하지 못했어요. 다시 시도해주세요.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 함수이름: _delete
  // 함수역할: 삭제 범위를 확인받고 알림 내역만 지운다. 매개변수: 선택적 entry. 반환값: 완료.
  Future<void> _delete([NotificationInboxEntry? entry]) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_english ? 'Delete notifications?' : '알림을 삭제할까요?'),
        content: Text(
          _english
              ? 'Chat messages and medication records will remain.'
              : '채팅 내용과 복약 기록은 삭제되지 않아요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_english ? 'Cancel' : '취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_english ? 'Delete' : '삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => widget.control.remove(entry));
    }
  }

  // 함수이름: _date
  // 함수역할: 알림 시각을 지역 날짜·시간으로 표시한다. 매개변수: date. 반환값: 시각 문자열.
  String _date(DateTime date) {
    final local = date.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  // 함수이름: build
  // 함수역할: 상태 안내와 최신순 통합 알림 목록을 구성한다. 매개변수: context. 반환값: 알림함 화면.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.control,
    builder: (context, _) {
      final control = widget.control;
      final entries = control.entries;
      return Scaffold(
        backgroundColor: MedBuddyColors.pageBackground,
        appBar: AppBar(
          backgroundColor: MedBuddyColors.pageBackground,
          title: Text(
            _english ? 'Notifications' : '알림',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              key: const Key('inbox-mark-all-read'),
              tooltip: _english ? 'Mark all as read' : '모두 읽음',
              onPressed: _busy || control.unreadCount == 0
                  ? null
                  : () => _run(() => control.markRead()),
              icon: const Icon(Icons.done_all),
            ),
            IconButton(
              key: const Key('inbox-delete-all'),
              tooltip: _english ? 'Delete all notifications' : '알림 전체 삭제',
              onPressed: _busy || control.entries.isEmpty
                  ? null
                  : () => _delete(),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (control.hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _english
                              ? 'Could not load notifications.'
                              : '알림을 불러오지 못했어요.',
                        ),
                      ),
                      IconButton(
                        tooltip: _english ? 'Retry' : '다시 시도',
                        onPressed: control.refresh,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              if (control.isLoading && control.entries.isEmpty)
                const LinearProgressIndicator(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: control.refresh,
                  child: entries.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 80),
                            const Icon(
                              Icons.notifications_none_outlined,
                              size: 48,
                              color: MedBuddyColors.textSubtle,
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Text(
                                _english ? 'No notifications' : '아직 알림이 없어요',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: entries.length,
                          separatorBuilder: (context, index) => const Divider(
                            height: 1,
                            indent: 20,
                            endIndent: 20,
                          ),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return Material(
                              color: entry.isRead
                                  ? Colors.transparent
                                  : MedBuddyColors.successSurface,
                              child: InkWell(
                                key: ValueKey('inbox-entry-${entry.id}'),
                                onTap: _busy
                                    ? null
                                    : () => _run(() async {
                                        await control.markRead(entry);
                                        if (mounted) widget.onOpen(entry);
                                      }),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        entry.category ==
                                                NotificationInboxCategory.chat
                                            ? Icons.chat_bubble_outline
                                            : Icons
                                                  .notifications_active_outlined,
                                        color: MedBuddyColors.primaryDark,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              entry.title,
                                              style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: entry.isRead
                                                    ? FontWeight.w600
                                                    : FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              entry.body,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                height: 1.45,
                                                color: MedBuddyColors.textMuted,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${_date(entry.occurredAt)}${entry.isRead ? '' : (_english ? ' · Unread' : ' · 안 읽음')}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color:
                                                    MedBuddyColors.textSubtle,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: _english
                                            ? 'Notification options'
                                            : '알림 더보기',
                                        onSelected: (_) => _delete(entry),
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text(
                                              _english ? 'Delete' : '삭제',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
