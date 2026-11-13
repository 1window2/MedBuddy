// File Name: linked_chat_entry_ui_boundary.dart
// Role: Validates an account relationship before opening a conversation from a notification.

// 알림의 연결 ID만으로 채팅을 열 때 현재 사용자의 역할과 상대 이름을 먼저 확인한다.
import 'package:flutter/material.dart';

import '../controls/manage_chat_list_control.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/authenticated_api_client.dart';
import '../widgets/medbuddy_page_header.dart';
import 'link_patient_caregiver_ui_boundary.dart';
import 'linked_chat_ui_boundary.dart';
import '../widgets/keep_words_text.dart';

// Class Name: LinkedChatEntryUI
// Role: Notification-to-conversation entry with role resolution.
// Responsibilities: Verifies the current account's active link before entering chat; separates lookup failure from an ended link and offers link management instead of guessing a role.
// Attributes: apiClient: optional caller-owned authenticated client shared by link lookup and chat; absent clients are created by their respective controllers.
class LinkedChatEntryUI extends StatefulWidget {
  // Function Name: LinkedChatEntryUI
  // Description: Binds a notification link to the current account and optionally supplied chat-list/API dependencies.
  // Parameters: key (Key?): widget identity; linkId (int): relationship; currentUserHash (String): account; userSetting (UserSetting): preferences; control (ManageChatList?): caller-owned lookup; latestMessageRequest (Listenable?): scroll signal; apiClient (AuthenticatedApiClient?): caller-owned client.
  // Returns: New LinkedChatEntryUI.
  const LinkedChatEntryUI({
    super.key,
    required this.linkId,
    required this.currentUserHash,
    required this.userSetting,
    this.control,
    this.latestMessageRequest,
    this.apiClient,
  });

  final int linkId;
  final String currentUserHash;
  final UserSetting userSetting;
  final ManageChatList? control;
  final Listenable? latestMessageRequest;
  final AuthenticatedApiClient? apiClient;

  // 함수이름: createState
  // 함수역할: 현재 계정의 연동 조회와 채팅 진입 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _LinkedChatEntryUIState.
  @override
  State<LinkedChatEntryUI> createState() => _LinkedChatEntryUIState();
}

// Class Name: _LinkedChatEntryUIState
// Role: Resolves a notification link without guessing the participant role.
// Responsibilities: Separates failed lookup from a successfully verified ended relationship.
// Attributes: _control (ManageChatList): link lookup; _link (PatientCaregiverLink?): verified link; _loading/_linkEnded (bool): lookup states.
class _LinkedChatEntryUIState extends State<LinkedChatEntryUI> {
  late final ManageChatList _control;
  PatientCaregiverLink? _link;
  bool _loading = true;
  // 조회는 성공했지만 이 연동이 목록에 없을 때 true. 재시도 대신 연동 종료를 안내한다.
  bool _linkEnded = false;

  // Function Name: initState
  // Description: Uses an injected link controller or creates one for the current authenticated account, then begins lookup.
  // Parameters: None.
  // Returns: No return value; only internally created controllers are later disposed.
  @override
  void initState() {
    super.initState();
    _control =
        widget.control ??
        ManageChatList(
          userHash: widget.currentUserHash,
          client: widget.apiClient,
          isEnglish: widget.userSetting.isEnglish,
        );
    _loadLink();
  }

  // Function Name: _loadLink
  // Description: Refreshes account links and accepts only an active, distinct, nonempty patient/caregiver pair containing this account.
  // Parameters: None.
  // Returns: Future<void>; failed lookup and an absent link produce different UI states, and unmounted views are not updated.
  Future<void> _loadLink() async {
    setState(() => _loading = true);
    await _control.refresh();
    if (!mounted) return;
    PatientCaregiverLink? resolved;
    final lookupSucceeded =
        !_control.hasError && _control.userHash == widget.currentUserHash;
    if (lookupSucceeded) {
      for (final link in _control.links) {
        if (link.linkId == widget.linkId &&
            link.linkStatus &&
            link.patientHash.isNotEmpty &&
            link.caregiverHash.isNotEmpty &&
            link.patientHash != link.caregiverHash &&
            (widget.currentUserHash == link.patientHash ||
                widget.currentUserHash == link.caregiverHash)) {
          resolved = link;
          break;
        }
      }
    }
    setState(() {
      _link = resolved;
      _linkEnded = lookupSucceeded && resolved == null;
      _loading = false;
    });
  }

  // Function Name: _openLinkManagement
  // Description: Replaces the ended-link entry route with link management so the user can reconnect or inspect other links.
  // Parameters: None.
  // Returns: None.
  void _openLinkManagement() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        // 함수이름: _openLinkManagement.builder 콜백
        // 함수역할: 현재 계정 범위의 연동 관리 화면을 만든다.
        // 매개변수: context: 새 경로의 위젯 트리 위치.
        // 반환값: 연동 관리 화면.
        builder: (context) => LinkPatientCaregiverUI(
          initialUserHash: widget.currentUserHash,
          userSetting: widget.userSetting,
        ),
      ),
    );
  }

  // Function Name: _buildLookupFailed
  // Description: Offers retry when the link query itself failed, without guessing the account role.
  // Parameters: english (bool): language selection.
  // Returns: The lookup-failure message and retry action.
  Widget _buildLookupFailed(bool english) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeepWordsText(
          english
              ? 'Could not verify this conversation.\nCheck your connection and patient-caregiver link, then try again.'
              : '대화 상대를 확인하지 못했어요.\n네트워크와 환자·보호자 연동 상태를 확인한 뒤 다시 시도해 주세요.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loadLink,
          icon: const Icon(Icons.refresh),
          label: KeepWordsText(english ? 'Try again' : '다시 시도'),
        ),
      ],
    );
  }

  // Function Name: _buildEndedLink
  // Description: Explains that a notification refers to an ended link and offers link management or closing.
  // Parameters: english (bool): language selection.
  // Returns: The ended-link message and navigation actions.
  Widget _buildEndedLink(bool english) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeepWordsText(
          english
              ? 'This patient-caregiver link has ended.\nThe conversation is no longer available.'
              : '환자·보호자 연동이 종료되었어요.\n이 대화는 더 이상 이용할 수 없어요.',
          key: const ValueKey('linkedChatEntryEnded'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _openLinkManagement,
          icon: const Icon(Icons.people_alt_outlined),
          label: KeepWordsText(english ? 'Manage links' : '연동 관리 열기'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(english ? 'Close' : '닫기'),
        ),
      ],
    );
  }

  // 함수이름: dispose
  // 함수역할: 화면이 직접 만든 연동 조회기만 해제한다.
  // 매개변수: 없음.
  // 반환값: 없음. 주입한 제어기는 호출자가 소유한다.
  @override
  void dispose() {
    if (widget.control == null) _control.dispose();
    super.dispose();
  }

  // Function Name: build
  // Description: Opens the conversation only with a verified link, otherwise shows progress, retry or ended-link management.
  // Parameters: context (BuildContext): Navigation and layout location.
  // Returns: Verified chat or entry-status Scaffold.
  @override
  Widget build(BuildContext context) {
    final english = widget.userSetting.isEnglish;
    final link = _link;
    if (link != null) {
      return LinkedChatUI(
        latestMessageRequest: widget.latestMessageRequest,
        linkId: widget.linkId,
        currentUserHash: widget.currentUserHash,
        patientHash: link.patientHash,
        peerName: _control.peerName(link, isEnglish: english),
        userSetting: widget.userSetting,
        apiClient: widget.apiClient,
      );
    }
    return Scaffold(
      body: Column(
        children: [
          MedBuddyPageHeader(
            title: english ? 'Chat' : '채팅',
            onBackRequested: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Center(
              child: _loading
                  ? CircularProgressIndicator(
                      semanticsLabel: english
                          ? 'Checking conversation'
                          : '대화 상대 확인 중',
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: _linkEnded
                          ? _buildEndedLink(english)
                          : _buildLookupFailed(english),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
