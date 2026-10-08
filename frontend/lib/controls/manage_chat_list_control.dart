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

// 클래스명: ManageChatList
// 역할: 대화 목록의 조회 상태를 사용자 단위로 보관하고 기존 연동·채팅 Control에 요청을 위임한다.
// 주요 책임: 활성 참여자 검증, 별칭 복원, 최근 메시지 조회와 요청 중복·종료 후 응답 방지.
// 속성: userHash: 소유 계정, links: 활성 연동, latestMessages: 연동별 미리보기,
//       isEnglish: 별칭이 없는 환자의 기본 표시 이름에 쓸 언어.
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
  bool isLoading = false;
  bool hasError = false;

  // 함수이름: ManageChatList
  // 함수역할: 계정 범위와 조회 의존성을 고정한다. 주입받은 Control은 호출자가 해제한다.
  // 매개변수: userHash: 계정 해시, linkControl/chatControl/localState: 테스트 또는 기존 조회 의존성,
  //           client: 기본 Control이 함께 쓸 HTTP 클라이언트(호출자가 닫는다. 없으면 Control마다 새로 만든다),
  //           isEnglish: 기본 표시 이름의 언어(기본값 한국어).
  // 반환값: 사용자별 대화 목록 Control.
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

  // 조회 실패·미조회는 0으로 단정하지 않고 null로 구분한다.
  int? unreadCount(int linkId) => _unreadCounts[linkId];

  // 함수이름: previewFailed
  // 함수역할: 특정 대화의 미리보기 조회 실패 여부를 구분한다.
  // 매개변수: linkId: 연동 ID. 반환값: 조회 실패 여부.
  bool previewFailed(int linkId) => _previewErrors.contains(linkId);

  // 함수이름: isCaregiver
  // 함수역할: 현재 사용자가 해당 연동의 보호자인지 확인한다.
  // 매개변수: link: 조회한 연동. 반환값: 보호자이면 true.
  bool isCaregiver(PatientCaregiverLink link) => link.caregiverHash == userHash;

  // 함수이름: peerName
  // 함수역할: 보호자에게는 서버의 최신 환자 별칭을 우선하고, 환자에게는 보호자 이름을 제공한다.
  // 매개변수: link, isEnglish: 연동과 표시 언어. 반환값: 대화 상대 표시 이름.
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
      return '${isEnglish ? 'Patient' : '환자'} ${link.patientHash}';
    }
    final caregiverAlias = link.caregiverAlias?.trim();
    if (caregiverAlias != null && caregiverAlias.isNotEmpty) {
      return caregiverAlias;
    }
    return '${isEnglish ? 'Caregiver' : '보호자'} ${link.caregiverHash}';
  }

  // 함수이름: refresh
  // 함수역할: 중복 요청을 합치고 갱신 중 발생한 연동 변경을 한 번 더 조회한다.
  // 매개변수: includeMessages: 화면이 보일 때 최근 메시지도 읽을지 여부,
  //           showLoading: 사용자가 직접 요청한 갱신처럼 진행 표시를 켤지 여부(첫 조회는 항상 켠다).
  // 반환값: 대기 중인 갱신까지 완료되는 Future.
  Future<void> refresh({
    bool includeMessages = false,
    bool showLoading = false,
  }) {
    if (_disposed) return Future.value();
    _includeMessages |= includeMessages;
    // 주기 조회는 진행 표시 없이 조용히 실행해 15초마다 화면이 흔들리지 않게 한다.
    if ((showLoading || !_requested) && !isLoading) {
      isLoading = true;
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

  // 함수이름: _refreshLoop
  // 함수역할: 목록·별칭·미리보기를 모두 읽고 정렬한 뒤 한 번에 반영하며 오류 시 마지막 목록을 유지한다.
  //           표시 내용이 실제로 바뀌었거나 진행 표시를 끌 때만 알린다.
  // 매개변수: 없음. 반환값: 모든 예약 조회가 끝나면 완료.
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
          _labels = labels;
          _latestMessages = latestMessages;
          _unreadCounts = unreadCounts;
          _previewErrors = previewErrors;
          hasError = false;
        } catch (_) {
          if (_disposed) return;
          hasError = true;
        }
      } while (_refreshAgain && !_disposed);
    } finally {
      _pending = null;
      final wasLoading = isLoading;
      isLoading = false;
      if (!_disposed) {
        final signature = _stateSignature();
        if (wasLoading || signature != _publishedSignature) {
          _publishedSignature = signature;
          notifyListeners();
        }
      }
    }
  }

  // 함수이름: _stateSignature
  // 함수역할: 화면에 보이는 목록 순서·이름·미리보기·미확인 개수·오류 상태를 비교할 값으로 만든다.
  // 매개변수: 없음. 반환값: 표시 내용이 같으면 같은 문자열.
  String _stateSignature() => jsonEncode([
    hasError,
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

  // 함수이름: _loadPreview
  // 함수역할: 읽음 처리 없이 최근 메시지와 미확인 개수를 가져오고 실패한 표시값은 제거한다.
  // 매개변수: link: 활성 연동, latestMessages/unreadCounts/previewErrors: 이번 조회에서 채울 결과.
  // 반환값: 해당 미리보기 조회 완료.
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

  // 함수이름: _compareLinks
  // 함수역할: 최근 대화 순서로 정렬하고 메시지가 없으면 연동 ID로 순서를 고정한다.
  // 매개변수: a, b: 비교할 활성 연동, latestMessages: 정렬 기준 미리보기. 반환값: 정렬 순서.
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
