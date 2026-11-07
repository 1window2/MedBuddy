// 파일명: manage_chat_list_control.dart
// 역할: 현재 사용자의 활성 대화 상대, 표시 이름·최근 메시지·안 읽은 개수를 조회한다.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../entities/chat_message_entity.dart';
import '../entities/patient_caregiver_link_entity.dart';
import 'link_patient_caregiver_control.dart';
import 'manage_caregiver_patient_local_state_control.dart';
import 'manage_linked_chat_control.dart';

// Class Name: ManageChatList
// Role: Maintains account-scoped chat previews and link state for conversation lists.
// Responsibilities: Validate active participants, restore aliases, coalesce refreshes and discard responses after disposal.
// Attributes: userHash: Owner; isEnglish: Fallback label language; link/message/count maps: Current display state; pending flags: Refresh coordination.
class ManageChatList extends ChangeNotifier {
  final String userHash;
  // 다음 조회부터 적용된다. 설정 언어가 바뀌면 생성한 쪽에서 갱신한다.
  bool isEnglish;
  final LinkPatientCaregiver _linkControl;
  final ManageLinkedChat _chatControl;
  final ManageCaregiverPatientLocalState _localState;
  final bool _ownsLinkControl;
  final bool _ownsChatControl;
  List<PatientCaregiverLink> _links = const [];
  Map<String, String> _labels = const {};
  Map<int, ChatMessage> _latestMessages = {};
  Map<int, int> _unreadCounts = {};
  Set<int> _previewErrors = {};
  Future<void>? _pending;
  bool _refreshAgain = false;
  bool _includeMessages = false;
  bool _requested = false;
  String? _publishedSignature;
  bool _disposed = false;
  bool _isLoading = false;
  bool _hasResolvedLinks = false;

  // 함수이름: hasResolvedLinks
  // 함수역할: 현재 계정의 연동 목록을 서버에서 한 번 이상 확인했는지 구분한다.
  // 매개변수: 없음.
  // 반환값: 빈 목록도 정상 응답으로 확인했으면 true; 최초 조회 실패는 false.
  bool get hasResolvedLinks => _hasResolvedLinks;

  // Function Name: isLoading
  // Description: Exposes whether an initial or explicitly announced refresh is loading.
  // Parameters: None.
  // Returns: The controller-owned loading flag; silent periodic reads need not set it.
  bool get isLoading => _isLoading;
  bool _hasError = false;
  // Function Name: hasError
  // Description: Reports whether the applicable link-list refresh failed.
  // Parameters: None.
  // Returns: The list error flag, independent of per-chat preview errors.
  bool get hasError => _hasError;

  // Function Name: ManageChatList
  // Description: Binds account-scoped chat, link and alias dependencies.
  // Parameters: userHash: Owner; linkControl/chatControl/localState: Optional dependencies; client: Caller-owned shared transport for default controls; isEnglish: Fallback label language.
  // Returns: A chat-list controller that disposes only controls it creates.
  ManageChatList({
    required this.userHash,
    LinkPatientCaregiver? linkControl,
    ManageLinkedChat? chatControl,
    ManageCaregiverPatientLocalState? localState,
    http.Client? client,
    this.isEnglish = false,
  }) : _linkControl =
           linkControl ??
           LinkPatientCaregiver(userHash: userHash, client: client),
       _chatControl =
           chatControl ?? ManageLinkedChat(userHash: userHash, client: client),
       _localState = localState ?? const ManageCaregiverPatientLocalState(),
       _ownsLinkControl = linkControl == null,
       _ownsChatControl = chatControl == null;

  // 함수이름: links
  // 함수역할: 외부에서 변경할 수 없는 활성 연동 목록을 반환한다.
  // 매개변수: 없음. 반환값: 활성 대화 상대 목록.
  List<PatientCaregiverLink> get links => List.unmodifiable(_links);

  // 함수이름: latestMessage
  // 함수역할: 선택한 연동의 최근 메시지를 읽는다.
  // 매개변수: linkId: 연동 ID. 반환값: 최근 메시지 또는 null.
  ChatMessage? latestMessage(int linkId) => _latestMessages[linkId];

  // 함수이름: unreadCount
  // 함수역할: 읽지 않은 메시지 수를 조회 실패나 미조회 상태와 구분해 제공한다.
  // 매개변수: linkId: 조회할 연동 ID.
  // 반환값: 확인된 개수 또는 미확인 상태를 나타내는 null.
  int? unreadCount(int linkId) => _unreadCounts[linkId];

  // 함수이름: previewFailed
  // 함수역할: 특정 대화의 미리보기 조회 실패 여부를 구분한다.
  // 매개변수: linkId: 연동 ID. 반환값: 조회 실패 여부.
  bool previewFailed(int linkId) => _previewErrors.contains(linkId);

  // 함수이름: isCaregiver
  // 함수역할: 현재 사용자가 해당 연동의 보호자인지 확인한다.
  // 매개변수: link: 조회한 연동. 반환값: 보호자이면 true.
  bool isCaregiver(PatientCaregiverLink link) => link.caregiverHash == userHash;

  // Function Name: peerName
  // Description: Chooses the peer's active alias with localized, privacy-preserving fallbacks.
  // Parameters: link: Conversation relationship; isEnglish: Fallback language.
  // Returns: Patient alias with server precedence for caregivers, otherwise caregiver alias or a label with only the hash suffix.
  String peerName(PatientCaregiverLink link, {required bool isEnglish}) {
    if (isCaregiver(link)) {
      // 서버 값이 있으면 동시 로컬 저장 중의 오래된 캐시로 덮어쓰지 않는다.
      final serverAlias = link.patientAlias?.trim();
      if (serverAlias != null) {
        return serverAlias.isNotEmpty
            ? serverAlias
            : _localState.fallbackLabel(link.patientHash, isEnglish: isEnglish);
      }
      final alias = _labels[link.patientHash];
      if (alias != null && alias.trim().isNotEmpty) return alias;
      return _localState.fallbackLabel(link.patientHash, isEnglish: isEnglish);
    }
    final caregiverAlias = link.caregiverAlias?.trim();
    if (caregiverAlias != null && caregiverAlias.isNotEmpty) {
      return caregiverAlias;
    }
    // 계정 해시 전체를 화면에 노출하지 않고 연동 화면과 같은 끝 네 글자만 보여준다.
    final caregiverHash = link.caregiverHash.trim();
    final suffix = caregiverHash.length <= 4
        ? caregiverHash
        : caregiverHash.substring(caregiverHash.length - 4);
    return '${isEnglish ? 'Caregiver' : '보호자'} ${suffix.toUpperCase()}';
  }

  // Function Name: refresh
  // Description: Coalesces concurrent refresh requests and schedules another pass for changes arriving during a load.
  // Parameters: includeMessages: Also fetch previews; showLoading: Announce loading, with the first request always announced.
  // Returns: The shared refresh Future, or an already completed Future after disposal.
  Future<void> refresh({
    bool includeMessages = false,
    bool showLoading = false,
  }) {
    if (_disposed) return Future.value();
    _includeMessages |= includeMessages;
    // 주기 조회는 진행 표시 없이 조용히 실행해 15초마다 화면이 흔들리지 않게 한다.
    if ((showLoading || !_requested) && !_isLoading) {
      _isLoading = true;
      notifyListeners();
    }
    _requested = true;
    if (_pending != null) {
      _refreshAgain = true;
      return _pending!;
    }
    _pending = _refreshLoop();
    return _pending!;
  }

  // Function Name: _refreshLoop
  // Description: Loads links, aliases and optional previews, then publishes sorted state only when it changes.
  // Parameters: None.
  // Returns: Completion after queued refresh passes; list errors preserve prior state, and alias failure falls back to server names.
  Future<void> _refreshLoop() async {
    try {
      do {
        _refreshAgain = false;
        final withMessages = _includeMessages;
        _includeMessages = false;
        try {
          final received = await _linkControl.requestLinkScreen();
          if (_disposed) return;
          final active = <int, PatientCaregiverLink>{};
          for (final link in received) {
            final id = link.linkId;
            if (id != null &&
                id > 0 &&
                link.linkStatus &&
                link.patientHash.isNotEmpty &&
                link.caregiverHash.isNotEmpty &&
                link.patientHash != link.caregiverHash &&
                (link.patientHash == userHash ||
                    link.caregiverHash == userHash)) {
              active[id] = link;
            }
          }
          final links = active.values.toList();
          // 해제된 연동의 미리보기는 새 목록과 함께 제거한다.
          final latestMessages = Map<int, ChatMessage>.of(_latestMessages)
            ..removeWhere((id, _) => !active.containsKey(id));
          final unreadCounts = Map<int, int>.of(_unreadCounts)
            ..removeWhere((id, _) => !active.containsKey(id));
          final previewErrors = _previewErrors
              .where(active.containsKey)
              .toSet();
          Map<String, String> labels;
          try {
            labels = await _localState.loadLabels(
              caregiverHash: userHash,
              links: links,
              isEnglish: isEnglish,
            );
            if (_disposed) return;
          } catch (_) {
            // 별칭 저장소 장애가 대화 진입을 막지 않도록 서버 이름을 사용한다.
            labels = const {};
          }
          if (withMessages && !_disposed) {
            // 여러 환자가 있어도 한 번에 네 요청까지만 실행한다.
            for (var offset = 0; offset < links.length; offset += 4) {
              await Future.wait(
                links
                    .skip(offset)
                    .take(4)
                    .map(
                      (link) => _loadPreview(
                        link,
                        latestMessages,
                        unreadCounts,
                        previewErrors,
                      ),
                    ),
              );
              if (_disposed) return;
            }
          }
          if (_disposed) return;
          // 서버 순서(연동 ID)의 목록이 잠시 보였다가 다시 바뀌지 않도록 정렬을 마친 뒤 교체한다.
          links.sort((a, b) => _compareLinks(a, b, latestMessages));
          _links = links;
          _hasResolvedLinks = true;
          _labels = labels;
          _latestMessages = latestMessages;
          _unreadCounts = unreadCounts;
          _previewErrors = previewErrors;
          _hasError = false;
        } catch (_) {
          if (_disposed) return;
          _hasError = true;
        }
      } while (_refreshAgain && !_disposed);
    } finally {
      _pending = null;
      final wasLoading = _isLoading;
      _isLoading = false;
      if (!_disposed) {
        final signature = _stateSignature();
        if (wasLoading || signature != _publishedSignature) {
          _publishedSignature = signature;
          notifyListeners();
        }
      }
    }
  }

  // Function Name: _stateSignature
  // Description: Encodes the ordered visible list state to suppress redundant notifications.
  // Parameters: None.
  // Returns: A signature covering link resolution, links, aliases, unread counts, preview errors and visible message fields.
  String _stateSignature() => jsonEncode([
    _hasResolvedLinks,
    _hasError,
    for (final link in _links)
      [
        link.toJson(),
        _labels[link.patientHash],
        _unreadCounts[link.linkId],
        _previewErrors.contains(link.linkId),
        if (_latestMessages[link.linkId] case final message?)
          [
            message.messageId,
            message.body,
            message.deletedForEveryone,
            message.createdAt.toIso8601String(),
          ],
      ],
  ]);

  // Function Name: _loadPreview
  // Description: Reads a recent message and unread count without marking the conversation read.
  // Parameters: link: Active relationship; latestMessages/unreadCounts/previewErrors: Mutable results for this refresh.
  // Returns: Completion after both independent lookups; failures remove uncertain preview/count values.
  Future<void> _loadPreview(
    PatientCaregiverLink link,
    Map<int, ChatMessage> latestMessages,
    Map<int, int> unreadCounts,
    Set<int> previewErrors,
  ) async {
    final id = link.linkId!;
    try {
      final messages = await _chatControl.requestHistory(linkId: id, limit: 1);
      if (_disposed) return;
      latestMessages.remove(id);
      previewErrors.remove(id);
      if (messages.isNotEmpty &&
          messages.last.linkId == id &&
          !messages.last.hiddenForMe) {
        latestMessages[id] = messages.last;
      }
    } catch (_) {
      if (_disposed) return;
      latestMessages.remove(id);
      previewErrors.add(id);
    }
    try {
      final unread = await _chatControl.requestUnreadSummary(linkId: id);
      if (_disposed) return;
      unreadCounts[id] = unread.count;
    } catch (_) {
      if (_disposed) return;
      unreadCounts.remove(id);
    }
  }

  // Function Name: _compareLinks
  // Description: Orders conversations by most recent message, with link IDs as a deterministic fallback.
  // Parameters: a/b: Active relationships; latestMessages: Available preview timestamps.
  // Returns: A comparator result putting conversations with newer messages first.
  int _compareLinks(
    PatientCaregiverLink a,
    PatientCaregiverLink b,
    Map<int, ChatMessage> latestMessages,
  ) {
    final first = latestMessages[a.linkId]?.createdAt;
    final second = latestMessages[b.linkId]?.createdAt;
    if (first != null && second != null) {
      final order = second.compareTo(first);
      if (order != 0) return order;
    } else if (first != null) {
      return -1;
    } else if (second != null) {
      return 1;
    }
    return a.linkId!.compareTo(b.linkId!);
  }

  // 함수이름: dispose
  // 함수역할: 늦게 도착한 응답을 무시하고 소유한 HTTP Control만 닫는다.
  // 매개변수: 없음. 반환값: 없음.
  @override
  void dispose() {
    _disposed = true;
    if (_ownsLinkControl) _linkControl.dispose();
    if (_ownsChatControl) _chatControl.dispose();
    super.dispose();
  }
}
