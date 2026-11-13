// 파일명: manage_notification_inbox_control.dart
// 역할: 알림 목록 조회·읽음·삭제와 화면 갱신을 조율한다.
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../entities/caregiver_alert_context_entity.dart';
import '../entities/medication_notification_selection_entity.dart';
import '../entities/medication_reminder_text.dart';
import '../entities/medication_slot_label.dart';
import '../entities/notification_inbox_entity.dart';
import '../services/medication_notification_payload_codec.dart';
import '../services/notification_inbox_store.dart';
import 'manage_chat_list_control.dart';

// Class Name: ManageNotificationInbox
// Role: Maintains a signed-in account's local notification inbox.
// Responsibilities: Refresh stored entries, expose read state and localize titles using active peer names without rewriting stored notifications.
// Attributes: store: Account-scoped persistence; _chatList: Optional caller-owned names; entry/loading/error fields: Visible state; timer/subscription: Refresh sources.
class ManageNotificationInbox extends ChangeNotifier {
  final NotificationInboxStore store;
  final ManageChatList? _chatList;
  List<NotificationInboxEntry> _entries = const [];
  // Function Name: entries
  // Description: Exposes the currently loaded notification entries.
  // Parameters: None.
  // Returns: The retained list; this accessor does not create a defensive copy.
  List<NotificationInboxEntry> get entries => _entries;
  bool _isLoading = false;
  // Function Name: isLoading
  // Description: Reports loading that needs to be displayed before the first successful read.
  // Parameters: None.
  // Returns: The announced initial-loading flag, not every background refresh.
  bool get isLoading => _isLoading;
  bool _hasError = false;
  // Function Name: hasError
  // Description: Exposes failure of the latest applicable inbox read.
  // Parameters: None.
  // Returns: Whether refresh failed while retaining the previous entries.
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

  // Function Name: ManageNotificationInbox
  // Description: Subscribes to account-specific inbox changes and optional peer-name updates.
  // Parameters: store: Owning account's persistence; chatList: Optional caller-owned chat controller for the same account.
  // Returns: An inbox controller; mismatched account hashes throw ArgumentError.
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

  // Function Name: unreadCount
  // Description: Counts unread entries in the currently displayed inbox.
  // Parameters: None.
  // Returns: The number of loaded entries whose isRead flag is false.
  int get unreadCount => _entries.where((entry) => !entry.isRead).length;

  // Function Name: titleFor
  // Description: Selects a localized reminder title or current authorized peer alias without changing stored data.
  // Parameters: entry: Stored notification; isEnglish: Display language; showSensitiveDetails: Whether caregiver/chat identifying details may be shown.
  // Returns: A generic caregiver title when hidden, a current linked name when eligible, otherwise the stored title.
  String titleFor(
    NotificationInboxEntry entry, {
    required bool isEnglish,
    bool showSensitiveDetails = true,
  }) {
    final reminderTitle = _localizedReminder(entry, isEnglish).title;
    if (reminderTitle != null) return reminderTitle;
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

  // Function Name: bodyFor
  // Description: Localizes recognized reminder text and hides caregiver details when requested.
  // Parameters: entry: Stored notification; isEnglish: Display language; showSensitiveDetails: Privacy preference.
  // Returns: Localized reminder text, generic caregiver guidance, or the original received body; never a reconstruction of current dose status.
  String bodyFor(
    NotificationInboxEntry entry, {
    required bool isEnglish,
    bool showSensitiveDetails = true,
  }) {
    final reminderBody = _localizedReminder(entry, isEnglish).body;
    if (reminderBody != null) return reminderBody;
    if (_isCaregiverEntry(entry) && !showSensitiveDetails) {
      return isEnglish
          ? 'Check your linked patient\'s medication status.'
          : '연동된 환자의 복약 상태를 확인해 주세요.';
    }
    return entry.body;
  }

  // Function Name: _reminderSlot
  // Description: Extracts a slot only from a medication notification targeting the schedule screen.
  // Parameters: entry: Stored notification to decode.
  // Returns: The decoded slot key, or null for another category/destination or invalid payload.
  String? _reminderSlot(NotificationInboxEntry entry) {
    if (entry.category != NotificationInboxCategory.medication) return null;
    final selection = MedicationNotificationPayloadCodec.decode(entry.payload);
    if (selection?.destination != MedicationNotificationDestination.schedule) {
      return null;
    }
    return selection!.slotKey;
  }

  // Function Name: _localizedReminder
  // Description: Relocalizes known reminder strings while preserving unrecognized historical wording.
  // Parameters: entry: Stored notification; isEnglish: Current language.
  // Returns: Nullable title/body replacements; each unmatched component remains null.
  ({String? title, String? body}) _localizedReminder(
    NotificationInboxEntry entry,
    bool isEnglish,
  ) {
    final slot = _reminderSlot(entry);
    if (slot == null) return (title: null, body: null);
    // Function Name: title
    // Description: Builds the standard title for the decoded slot in either supported language.
    // Parameters: english: Whether to use English.
    // Returns: A localized reminder title used for comparison and replacement.
    String title(bool english) => medicationReminderTitle(
      slot,
      slotTitle: medicationSlotLabel(slot, isEnglish: english),
      isEnglish: english,
    );
    // Function Name: body
    // Description: Builds the standard body for the decoded slot in either supported language.
    // Parameters: english: Whether to use English.
    // Returns: A localized reminder body used for comparison and replacement.
    String body(bool english) =>
        medicationReminderBody(slot, isEnglish: english);
    return (
      title: entry.title == title(false) || entry.title == title(true)
          ? title(isEnglish)
          : null,
      body: entry.body == body(false) || entry.body == body(true)
          ? body(isEnglish)
          : null,
    );
  }

  // Function Name: _isCaregiverEntry
  // Description: Checks both medication category and a recognized caregiver payload prefix.
  // Parameters: entry: Notification to classify.
  // Returns: Whether the entry uses either supported caregiver payload family.
  bool _isCaregiverEntry(NotificationInboxEntry entry) =>
      entry.category == NotificationInboxCategory.medication &&
      (entry.payload.startsWith(
            MedicationNotificationPayloadCodec.caregiverPayloadPrefix,
          ) ||
          entry.payload.startsWith(CaregiverAlertContext.payloadPrefix));

  // Function Name: _caregiverEntryPatientHash
  // Description: Reads a patient hash from the appropriate caregiver payload format.
  // Parameters: entry: Caregiver notification whose payload is decoded.
  // Returns: The action-context or URI-decoded patient hash, or null for a caught decoding error.
  String? _caregiverEntryPatientHash(NotificationInboxEntry entry) {
    if (entry.payload.startsWith(CaregiverAlertContext.payloadPrefix)) {
      return CaregiverAlertContext.fromPayload(entry.payload)?.patientHash;
    }
    try {
      return Uri.decodeComponent(
        entry.payload.substring(
          MedicationNotificationPayloadCodec.caregiverPayloadPrefix.length,
        ),
      );
    } on ArgumentError {
      return null;
    }
  }

  // Function Name: _currentPeerNameSignature
  // Description: Encodes active relationships and both localized peer names for change detection.
  // Parameters: None.
  // Returns: A stable ordered signature, or an empty string without a chat controller.
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

  // Function Name: _onPeerNamesChanged
  // Description: Notifies inbox listeners only when active peer-name information changes.
  // Parameters: None.
  // Returns: None; ignores disposal and unrelated chat-list changes.
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

  // Function Name: refresh
  // Description: Loads entries while coalescing overlapping refreshes and preserving prior data on failure.
  // Parameters: None.
  // Returns: Completion of this read; an overlapping call queues another pass and returns immediately.
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

  // Function Name: _sameVisibleEntries
  // Description: Compares displayed entry identity, order and read flags without comparing immutable stored text.
  // Parameters: before/after: Notification entry lists.
  // Returns: True when the list reference or each ordered ID/read pair matches.
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
    await store.markRead(
      entry == null ? _entries.map((e) => e.id) : [entry.id],
    );
    await refresh();
  }

  // Function Name: remove
  // Description: Removes notification history without deleting chat or medication records.
  // Parameters: entry: One entry to remove, or null for the currently loaded entries.
  // Returns: Completion of delegated removal and refresh; persistence failures propagate.
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
