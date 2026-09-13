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
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  // 함수이름: _selectedEntries
  // 함수역할: 현재 목록에 남아 있는 선택만 반환한다. 매개변수: 없음. 반환값: 선택 항목 목록.
  List<NotificationInboxEntry> get _selectedEntries => widget.control.entries
      .where((entry) => _selectedIds.contains(entry.id))
      .toList(growable: false);

  // 함수이름: _startSelection
  // 함수역할: 선택 버튼 또는 길게 누른 항목으로 삭제 선택을 시작한다. 매개변수: 선택적 entry. 반환값: 없음.
  void _startSelection([NotificationInboxEntry? entry]) {
    if (_busy) return;
    setState(() {
      _selecting = true;
      _selectedIds.clear();
      if (entry != null) _selectedIds.add(entry.id);
    });
  }

  // 함수이름: _endSelection
  // 함수역할: 삭제하지 않고 선택 화면을 종료한다. 매개변수: 없음. 반환값: 없음.
  void _endSelection() {
    if (_busy) return;
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  // 함수이름: _toggleSelection
  // 함수역할: 알림 이동 없이 한 항목의 선택을 바꾼다. 매개변수: entry. 반환값: 없음.
  void _toggleSelection(NotificationInboxEntry entry) {
    if (_busy) return;
    setState(() {
      if (!_selectedIds.remove(entry.id)) _selectedIds.add(entry.id);
    });
  }

  // 함수이름: _toggleAll
  // 함수역할: 현재 목록 전체를 선택하거나 선택을 비운다. 매개변수: 없음. 반환값: 없음.
  void _toggleAll() {
    if (_busy) return;
    final allSelected =
        _selectedEntries.length == widget.control.entries.length;
    setState(() {
      _selectedIds.clear();
      if (!allSelected) {
        _selectedIds.addAll(widget.control.entries.map((entry) => entry.id));
      }
    });
  }

  // 함수이름: _handleBack
  // 함수역할: 뒤로가기 시 먼저 선택 모드를 닫는다. 매개변수: didPop, result. 반환값: 없음.
  void _handleBack(bool didPop, Object? result) {
    if (!didPop && _selecting) _endSelection();
  }

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
  // 함수역할: 선택 당시의 목록을 확인받고 알림 내역만 지운다. 매개변수: entries. 반환값: 완료.
  Future<void> _delete(List<NotificationInboxEntry> entries) async {
    if (_busy || entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MedBuddyColors.surface,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          height: 1.35,
          letterSpacing: 0,
          color: MedBuddyColors.textStrong,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.45,
          letterSpacing: 0,
          color: MedBuddyColors.textMuted,
        ),
        title: Text(_english ? 'Delete notifications?' : '알림을 삭제할까요?'),
        content: Text(
          _english
              ? 'Chat messages and medication records will remain.'
              : '채팅 내용과 복약 기록은 삭제되지 않아요.',
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: MedBuddyColors.textMuted,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: Text(_english ? 'Cancel' : '취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: MedBuddyColors.danger,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_english ? 'Delete' : '삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() async {
        await widget.control.removeEntries(entries);
        if (mounted) {
          setState(() {
            _selectedIds.clear();
            _selecting = false;
          });
        }
      });
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
  Widget build(BuildContext context) => PopScope(
    canPop: !_selecting,
    onPopInvokedWithResult: _handleBack,
    child: ListenableBuilder(
      listenable: widget.control,
      builder: (context, _) {
        final control = widget.control;
        final entries = control.entries;
        final selected = _selectedEntries;
        return Scaffold(
          backgroundColor: MedBuddyColors.pageBackground,
          appBar: AppBar(
            backgroundColor: MedBuddyColors.pageBackground,
            foregroundColor: MedBuddyColors.textStrong,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
            leading: _selecting
                ? IconButton(
                    key: const Key('inbox-cancel-selection'),
                    tooltip: _english ? 'Cancel selection' : '선택 취소',
                    onPressed: _busy ? null : _endSelection,
                    icon: const Icon(Icons.close),
                  )
                : null,
            title: Text(
              _selecting
                  ? (_english ? 'Select' : '알림 선택')
                  : (_english ? 'Notifications' : '알림'),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                color: MedBuddyColors.textStrong,
              ),
            ),
            actions: _selecting
                ? []
                : [
                    IconButton(
                      key: const Key('inbox-mark-all-read'),
                      tooltip: _english ? 'Mark all as read' : '모두 읽음',
                      onPressed: _busy || control.unreadCount == 0
                          ? null
                          : () => _run(() => control.markRead()),
                      icon: const Icon(Icons.done_all),
                    ),
                    IconButton(
                      key: const Key('inbox-select'),
                      tooltip: _english ? 'Select notifications' : '알림 선택',
                      onPressed: _busy || control.entries.isEmpty
                          ? null
                          : () => _startSelection(),
                      icon: const Icon(Icons.checklist),
                    ),
                  ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (_selecting)
                  Material(
                    color: MedBuddyColors.surfaceSubtle,
                    shape: const Border(
                      bottom: BorderSide(color: MedBuddyColors.divider),
                    ),
                    child: CheckboxListTile(
                      key: const Key('inbox-select-all'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: MedBuddySpacing.pageHorizontal,
                        vertical: 8,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: MedBuddyColors.primary,
                      checkColor: MedBuddyColors.surface,
                      checkboxShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      value:
                          entries.isNotEmpty &&
                              selected.length == entries.length
                          ? true
                          : (selected.isEmpty ? false : null),
                      tristate: true,
                      onChanged: _busy || entries.isEmpty
                          ? null
                          : (_) => _toggleAll(),
                      // 큰 글씨에서는 개수만 다음 줄로 이동해 선택 문구를 자르지 않는다.
                      title: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          Text(
                            _english ? 'Select all' : '전체 선택',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                              letterSpacing: 0,
                              color: MedBuddyColors.textStrong,
                            ),
                          ),
                          Text(
                            _english
                                ? '${selected.length} selected'
                                : '${selected.length}개 선택',
                            key: const Key('inbox-selection-count'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                              letterSpacing: 0,
                              color: selected.isEmpty
                                  ? MedBuddyColors.textMuted
                                  : MedBuddyColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                                    color: MedBuddyColors.textStrong,
                                    letterSpacing: 0,
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
                              color: MedBuddyColors.divider,
                            ),
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              final isSelected = _selectedIds.contains(
                                entry.id,
                              );
                              return Material(
                                color: (_selecting ? isSelected : !entry.isRead)
                                    ? MedBuddyColors.successSurface
                                    : Colors.transparent,
                                child: InkWell(
                                  key: ValueKey('inbox-entry-${entry.id}'),
                                  onTap: _busy
                                      ? null
                                      : _selecting
                                      ? () => _toggleSelection(entry)
                                      : () => _run(() async {
                                          await control.markRead(entry);
                                          if (mounted) widget.onOpen(entry);
                                        }),
                                  onLongPress: _busy || _selecting
                                      ? null
                                      : () => _startSelection(entry),
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (_selecting)
                                          Checkbox(
                                            key: ValueKey(
                                              'inbox-check-${entry.id}',
                                            ),
                                            value: isSelected,
                                            activeColor: MedBuddyColors.primary,
                                            checkColor: MedBuddyColors.surface,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            onChanged: _busy
                                                ? null
                                                : (_) =>
                                                      _toggleSelection(entry),
                                          )
                                        else
                                          Icon(
                                            entry.category ==
                                                    NotificationInboxCategory
                                                        .chat
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
                                                control.titleFor(
                                                  entry,
                                                  isEnglish: _english,
                                                  showSensitiveDetails: widget
                                                      .userSetting
                                                      .showNotificationDetails,
                                                ),
                                                style: TextStyle(
                                                  fontSize: 17,
                                                  height: 1.35,
                                                  letterSpacing: 0,
                                                  color:
                                                      MedBuddyColors.textStrong,
                                                  fontWeight: entry.isRead
                                                      ? FontWeight.w700
                                                      : FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                entry.body,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  height: 1.45,
                                                  letterSpacing: 0,
                                                  color:
                                                      MedBuddyColors.textMuted,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '${_date(entry.occurredAt)}${entry.isRead ? '' : (_english ? ' · Unread' : ' · 안 읽음')}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  height: 1.35,
                                                  letterSpacing: 0,
                                                  color:
                                                      MedBuddyColors.textSubtle,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!_selecting)
                                          PopupMenuButton<String>(
                                            tooltip: _english
                                                ? 'Notification options'
                                                : '알림 더보기',
                                            enabled: !_busy,
                                            onSelected: (_) => _delete([entry]),
                                            itemBuilder: (context) => [
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Text(
                                                  _english ? 'Delete' : '삭제',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 0,
                                                    color:
                                                        MedBuddyColors.danger,
                                                  ),
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
          bottomNavigationBar: _selecting
              ? SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: FilledButton.icon(
                      key: const Key('inbox-delete-selected'),
                      onPressed: _busy || selected.isEmpty
                          ? null
                          : () => _delete(selected),
                      style: FilledButton.styleFrom(
                        backgroundColor: MedBuddyColors.primary,
                        foregroundColor: MedBuddyColors.surface,
                        disabledBackgroundColor: MedBuddyColors.divider,
                        disabledForegroundColor: MedBuddyColors.textMuted,
                        textStyle: const TextStyle(
                          fontSize: 16,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: MedBuddyRadii.pill,
                        ),
                        minimumSize: const Size.fromHeight(56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(
                        selected.isEmpty
                            ? (_english ? 'Delete selected' : '선택한 알림 삭제')
                            : (_english
                                  ? 'Delete (${selected.length})'
                                  : '알림 ${selected.length}개 삭제'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              : null,
        );
      },
    ),
  );
}
