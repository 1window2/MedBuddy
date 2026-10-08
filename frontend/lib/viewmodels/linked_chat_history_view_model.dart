// File Name: linked_chat_history_view_model.dart
// Role: Owns one conversation's history recovery, realtime reconciliation, and read receipts.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controls/manage_linked_chat_control.dart';
import '../entities/chat_message_entity.dart';
import '../services/api_response_parser.dart';
import '../services/linked_chat_realtime_service.dart';

// Class Name: LinkedChatHistoryViewModel
// Role: Maintains independently scoped conversation state outside the widget library.
// Responsibilities:
// - Coalesce history reads and recover missed pages without losing receipt/deletion evidence.
// - Poll only during transport/history failure and acknowledge only a visible latest position.
// - Stop polling and reconnecting once the server answers that the link is gone or forbidden.
// - Ignore disposed completions and events for another conversation.
// Attributes:
// - linkId/userHash: Immutable conversation and account scope.
// - control/realtime: Borrowed authenticated adapters; their owner disposes them.
// - Visibility/scroll callbacks: Presentation ports, never mutable sibling state.
class LinkedChatHistoryViewModel extends ChangeNotifier {
  final int linkId;
  final String userHash;
  final ManageLinkedChat control;
  final LinkedChatSessionTransport realtime;
  final bool Function() isVisible;
  final bool Function() isAtLatest;
  final void Function(bool force) onScrollRequested;
  final void Function() onScheduleChanged;
  final void Function(List<int> ids) onDeleted;
  List<ChatMessage> _messages = const [];
  final Set<int> _hiddenIds = {};
  final Set<int> _deletedIds = {};
  StreamSubscription<Map<String, dynamic>>? _events;
  StreamSubscription<LinkedChatConnectionState>? _states;
  Timer? _fallback;
  Future<void>? _refresh;
  bool _refreshAgain = false;
  bool _needsRecovery = false;
  bool _linkUnavailable = false;
  int? _recoveryBoundary;
  bool _boundaryCaptured = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _markingRead = false;
  int? _lastMarkedId;

  // Function Name: LinkedChatHistoryViewModel
  // Description: Subscribes to borrowed realtime adapters for one immutable conversation scope.
  // Parameters: Scope, control/realtime adapters, visibility predicates and presentation callbacks.
  // Returns: A history owner with no navigation, composer or platform-widget dependencies.
  LinkedChatHistoryViewModel({
    required this.linkId,
    required this.userHash,
    required this.control,
    required this.realtime,
    required this.isVisible,
    required this.isAtLatest,
    required this.onScrollRequested,
    required this.onScheduleChanged,
    required this.onDeleted,
  }) {
    _events = realtime.events.listen(handleEvent);
    _states = realtime.states.listen(_connectionChanged);
  }

  bool _isLoading = true;
  bool _historyFailed = false;
  bool _hasOlderMessages = false;
  bool _loadingOlderMessages = false;
  bool _olderMessagesFailed = false;
  int? _firstUnreadMessageId;
  LinkedChatConnectionState _connectionState =
      LinkedChatConnectionState.connecting;

  // Function Name: isLoading
  // Description: Exposes read-only conversation presentation state.
  // Parameters: None. Returns: Whether initial/retry history is loading.
  bool get isLoading => _isLoading;

  // Function Name: historyFailed
  // Description: Exposes read-only conversation presentation state.
  // Parameters: None. Returns: Whether empty history currently has a retryable failure.
  bool get historyFailed => _historyFailed;

  // Function Name: hasOlderMessages
  // Description: Exposes read-only conversation presentation state.
  // Parameters: None. Returns: Whether another backward page may exist.
  bool get hasOlderMessages => _hasOlderMessages;

  // Function Name: loadingOlderMessages
  // Description: Exposes read-only conversation presentation state.
  // Parameters: None. Returns: Whether one older page is in flight.
  bool get loadingOlderMessages => _loadingOlderMessages;

  // Function Name: olderMessagesFailed
  // Description: Exposes read-only conversation presentation state.
  // Parameters: None. Returns: Whether the last older page failed.
  bool get olderMessagesFailed => _olderMessagesFailed;

  // Function Name: firstUnreadMessageId
  // Description: Exposes read-only conversation presentation state.
  // Parameters: None. Returns: Fixed first-unread separator for this visit.
  int? get firstUnreadMessageId => _firstUnreadMessageId;

  // Function Name: connectionState
  // Description: Exposes read-only conversation presentation state.
  // Parameters: None. Returns: Current borrowed transport connection state.
  LinkedChatConnectionState get connectionState => _connectionState;

  // Function Name: linkUnavailable
  // Description: Reports the terminal state entered when the last history read was rejected with 403/404.
  // Parameters: None. Returns: Whether periodic recovery is suspended until a resume or explicit refresh succeeds.
  bool get linkUnavailable => _linkUnavailable;

  // Function Name: messages
  // Description: Exposes an immutable history snapshot ordered by message ID.
  // Parameters: None. Returns: Current visible messages with monotonic receipt/deletion evidence.
  List<ChatMessage> get messages => _messages;

  // Function Name: initialize
  // Description: Starts transport and the initial history read without taking adapter ownership.
  // Parameters: None. Returns: Completion of both initial operations.
  Future<void> initialize() async {
    if (_disposed) return;
    await Future.wait([refresh(showLoading: true), realtime.start()]);
    _updateFallback();
  }

  // Function Name: setForeground
  // Description: Stops background polling/transport and catches up when the app resumes.
  // Parameters: foreground: Whether the application is resumed.
  // Returns: None; asynchronous transport and history work retains this immutable scope.
  void setForeground(bool foreground) {
    if (_disposed) return;
    _foreground = foreground;
    if (foreground) {
      unawaited(realtime.start());
      unawaited(refresh(showLoading: false, catchUp: true));
    } else {
      unawaited(realtime.stop());
    }
    _updateFallback();
  }

  // Function Name: _connectionChanged
  // Description: Updates presentation state and requests a coalesced catch-up after reconnection.
  // Parameters: state: Current borrowed transport state. Returns: None.
  void _connectionChanged(LinkedChatConnectionState state) {
    if (_disposed) return;
    _connectionState = state;
    notifyListeners();
    _updateFallback();
    if (state == LinkedChatConnectionState.connected && isVisible()) {
      unawaited(refresh(showLoading: false, catchUp: true));
    }
  }

  // Function Name: _updateFallback
  // Description: Preserves a running retry cadence rather than postponing it on every reconnect event.
  // Parameters: None. Returns: None; owns at most one twelve-second timer, and none for an unavailable link.
  void _updateFallback() {
    if (_disposed ||
        !_foreground ||
        _linkUnavailable ||
        (_connectionState == LinkedChatConnectionState.connected &&
            !_needsRecovery)) {
      _fallback?.cancel();
      _fallback = null;
      return;
    }
    if (_fallback?.isActive == true) return;
    _fallback = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!_disposed && isVisible()) unawaited(refresh(showLoading: false));
    });
  }

  // Function Name: refresh
  // Description: Shares in-flight reads and retains one follow-up when reconnect/resume occurs mid-read.
  // Parameters: showLoading: Initial/retry loading UI; catchUp: Request a follow-up for missed events.
  // Returns: Shared refresh completion; disposed owners perform no work.
  Future<void> refresh({required bool showLoading, bool catchUp = false}) {
    if (_disposed) return Future.value();
    final pending = _refresh;
    if (pending != null) {
      _refreshAgain |= catchUp;
      return pending;
    }
    return _refresh = _refreshLoop(
      showLoading,
    ).whenComplete(() => _refresh = null);
  }

  // Function Name: _refreshLoop
  // Description: Runs a pending recovery request only while the conversation remains visible.
  // Parameters: showLoading: Whether the first read should show a loading indicator.
  // Returns: Completion of the coalesced history reads.
  Future<void> _refreshLoop(bool showLoading) async {
    do {
      _refreshAgain = false;
      await _loadMessages(showLoading);
      showLoading = false;
    } while (!_disposed && _refreshAgain && isVisible());
  }

  // Function Name: _initialUnread
  // Description: Uses older-server message evidence when unread-summary lookup fails.
  // Parameters: None. Returns: Unread summary, or null without blocking history.
  Future<ChatUnreadSummary?> _initialUnread() async {
    try {
      return await control.requestUnreadSummary(linkId: linkId);
    } catch (_) {
      return null;
    }
  }

  // Function Name: _loadMessages
  // Description: Reads through the last known message and fixes the first visit's unread boundary once.
  // Parameters: showLoading: Whether to reset initial loading/failure presentation.
  // Returns: Completion; late/disposed responses never publish or start another page.
  Future<void> _loadMessages(bool showLoading) async {
    if (showLoading) {
      _isLoading = true;
      _historyFailed = false;
      notifyListeners();
    }
    try {
      final unreadFuture = _boundaryCaptured
          ? Future<ChatUnreadSummary?>.value()
          : _initialUnread();
      _recoveryBoundary ??= _messages.isEmpty ? null : _messages.last.messageId;
      final newestKnownId = _recoveryBoundary;
      var page = await control.requestHistory(linkId: linkId);
      // A skipped unparseable row still counts as a server row for paging.
      final initialPageIsFull = ChatHistoryPage.rowCountOf(page) == 50;
      final incoming = [...page];
      final unread = await unreadFuture;
      int? previousBoundary;
      while (newestKnownId != null &&
          page.isNotEmpty &&
          ChatHistoryPage.rowCountOf(page) == 50) {
        final oldest = page
            .map((m) => m.messageId)
            .reduce((a, b) => a < b ? a : b);
        if (oldest <= newestKnownId ||
            (previousBoundary != null && oldest >= previousBoundary)) {
          break;
        }
        if (_disposed || !isVisible()) {
          _needsRecovery = true;
          return;
        }
        previousBoundary = oldest;
        page = await control.requestHistory(
          linkId: linkId,
          beforeMessageId: oldest,
        );
        incoming.addAll(page);
      }
      if (_disposed) return;
      _recoveryBoundary = null;
      _needsRecovery = false;
      if (_linkUnavailable) {
        // An explicit retry or a resume reached the link again: resume realtime delivery.
        _linkUnavailable = false;
        if (_foreground) unawaited(realtime.start());
      }
      _merge(incoming);
      if (!_boundaryCaptured) {
        _firstUnreadMessageId = unread?.firstMessageId;
        if (_firstUnreadMessageId == null &&
            (unread == null || unread.count > 0)) {
          for (final message in _messages) {
            if (message.senderHash != userHash &&
                message.readAt == null &&
                !message.deletedForEveryone) {
              _firstUnreadMessageId = message.messageId;
              break;
            }
          }
        }
        _hasOlderMessages = initialPageIsFull;
        _boundaryCaptured = true;
      }
      _isLoading = false;
      _historyFailed = false;
      notifyListeners();
      _updateFallback();
      onScrollRequested(showLoading);
      await markLatestIncomingRead();
    } catch (error) {
      if (_disposed) return;
      _needsRecovery = true;
      _isLoading = false;
      if (_messages.isEmpty) _historyFailed = true;
      if (error is ApiRequestException &&
          (error.statusCode == 403 || error.statusCode == 404)) {
        // The link was removed or access was revoked: polling every 12 s and reconnecting
        // every 10 s cannot recover it. A resume or an explicit refresh tries again.
        _linkUnavailable = true;
        unawaited(realtime.stop());
      }
      notifyListeners();
      _updateFallback();
    }
  }

  // Function Name: loadOlderMessages
  // Description: Serializes backwards pagination and preserves already merged realtime evidence.
  // Parameters: None. Returns: Completion; failures remain retryable without dropping current history.
  Future<void> loadOlderMessages() async {
    if (_disposed ||
        _loadingOlderMessages ||
        !_hasOlderMessages ||
        _messages.isEmpty) {
      return;
    }
    final beforeId = _messages.first.messageId;
    _loadingOlderMessages = true;
    _olderMessagesFailed = false;
    notifyListeners();
    try {
      final older = await control.requestHistory(
        linkId: linkId,
        beforeMessageId: beforeId,
      );
      if (_disposed) return;
      _merge(older);
      _hasOlderMessages =
          ChatHistoryPage.rowCountOf(older) == 50 &&
          older.any((m) => m.messageId < beforeId);
    } catch (_) {
      if (!_disposed) _olderMessagesFailed = true;
    } finally {
      if (!_disposed) {
        _loadingOlderMessages = false;
        notifyListeners();
      }
    }
  }

  // Function Name: _merge
  // Description: Retains monotonic read/delete evidence and excludes another conversation's messages.
  // Parameters: incoming: HTTP, send-result, or realtime messages.
  // Returns: None; updates the private history snapshot without publishing partial merges.
  void _merge(List<ChatMessage> incoming) {
    final byId = {for (final message in _messages) message.messageId: message};
    for (final message in incoming) {
      if (message.linkId != linkId) continue;
      final knownReadAt = byId[message.messageId]?.readAt;
      byId[message.messageId] =
          knownReadAt != null &&
              (message.readAt == null || message.readAt!.isBefore(knownReadAt))
          ? message.copyWith(readAt: knownReadAt)
          : message;
      if (message.hiddenForMe) _hiddenIds.add(message.messageId);
      if (message.deletedForEveryone) _deletedIds.add(message.messageId);
    }
    final merged =
        byId.values
            .where((m) => !_hiddenIds.contains(m.messageId))
            .map(
              (m) => _deletedIds.contains(m.messageId)
                  ? m.copyWith(deletedForEveryone: true)
                  : m,
            )
            .toList()
          ..sort((a, b) => a.messageId.compareTo(b.messageId));
    _messages = List.unmodifiable(merged);
  }

  // Function Name: addMessage
  // Description: Applies an accepted send/dose result without changing composer or navigation state.
  // Parameters: message: Server-confirmed message for this conversation. Returns: None.
  void addMessage(ChatMessage message) {
    if (_disposed || message.linkId != linkId) return;
    _merge([message]);
    _historyFailed = false;
    notifyListeners();
  }

  // Function Name: applyDeletion
  // Description: Keeps tombstones/hiding authoritative even when an older HTTP response arrives later.
  // Parameters: ids: Deleted message identifiers; scope: Server-confirmed deletion scope.
  // Returns: None; publishes reconciled history and lets the UI clear its selection.
  void applyDeletion(List<int> ids, ChatDeletionScope scope) {
    if (_disposed) return;
    (scope == ChatDeletionScope.me ? _hiddenIds : _deletedIds).addAll(ids);
    _merge(const []);
    notifyListeners();
    onDeleted(ids);
  }

  // Function Name: handleEvent
  // Description: Validates transport events and applies only this immutable conversation's evidence.
  // Parameters: event: Realtime message/deletion/read event; legacy events may omit link_id.
  // Returns: None; malformed or mismatched events are ignored.
  void handleEvent(Map<String, dynamic> event) {
    if (_disposed ||
        (event.containsKey('link_id') &&
            event['link_id'].toString() != '$linkId')) {
      return;
    }
    final type = event['type'];
    if (type == 'chat_messages_deleted') {
      final ids = event['message_ids'];
      if (ids is List &&
          (event['scope'] == 'me' || event['scope'] == 'everyone')) {
        applyDeletion(
          ids.whereType<int>().toList(),
          event['scope'] == 'me'
              ? ChatDeletionScope.me
              : ChatDeletionScope.everyone,
        );
      }
    } else if (type == 'chat_message') {
      final raw = event['message'];
      if (raw is! Map) return;
      try {
        final message = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
        if (message.linkId != linkId) return;
        if (!_isLoading &&
            !isAtLatest() &&
            message.senderHash != userHash &&
            !message.deletedForEveryone &&
            message.readAt == null) {
          _firstUnreadMessageId ??= message.messageId;
        }
        addMessage(message);
        onScrollRequested(false);
        if (message.messageKind == ChatMessageKind.slotCheckRequest ||
            message.messageKind == ChatMessageKind.slotCompletion) {
          onScheduleChanged();
        }
        if (message.senderHash != userHash) unawaited(markLatestIncomingRead());
      } on FormatException {
        return;
      }
    } else if (type == 'chat_read' &&
        event['reader_hash']?.toString() != userHash) {
      final through = int.tryParse(
        event['through_message_id']?.toString() ?? '',
      );
      final readAt = DateTime.tryParse(event['read_at']?.toString() ?? '');
      if (through == null || readAt == null) return;
      _merge([
        for (final m in _messages)
          if (m.senderHash == userHash && m.messageId <= through)
            m.copyWith(readAt: readAt),
      ]);
      notifyListeners();
    }
  }

  // Function Name: markLatestIncomingRead
  // Description: Coalesces acknowledgements and retries failures only while the latest position remains visible.
  // Parameters: None. Returns: Completion; disposal invalidates late receipts and recursive follow-ups.
  Future<void> markLatestIncomingRead() async {
    if (_disposed ||
        !isVisible() ||
        _isLoading ||
        !isAtLatest() ||
        _markingRead) {
      return;
    }
    final incoming = _messages.where((m) => m.senderHash != userHash).toList();
    if (incoming.isEmpty) return;
    final latestId = incoming.last.messageId;
    if (_lastMarkedId != null && latestId <= _lastMarkedId!) return;
    _markingRead = true;
    try {
      await control.markRead(linkId: linkId, throughMessageId: latestId);
      if (_disposed) return;
      if (_lastMarkedId == null || latestId > _lastMarkedId!) {
        _lastMarkedId = latestId;
      }
    } catch (_) {
      /* Later visible refresh/events retry without claiming a receipt. */
    } finally {
      _markingRead = false;
    }
    if (!_disposed &&
        _lastMarkedId == latestId &&
        _messages.any(
          (m) => m.senderHash != userHash && m.messageId > latestId,
        )) {
      unawaited(markLatestIncomingRead());
    }
  }

  // Function Name: dispose
  // Description: Invalidates callbacks and cancels owned subscriptions/timers without closing borrowed adapters.
  // Parameters: None. Returns: None; HTTP work may finish but cannot publish into this or a new session.
  @override
  void dispose() {
    _disposed = true;
    _fallback?.cancel();
    unawaited(_events?.cancel());
    unawaited(_states?.cancel());
    super.dispose();
  }
}
