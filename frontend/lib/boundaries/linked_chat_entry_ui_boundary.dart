// 알림의 연결 ID만으로 채팅을 열 때 현재 사용자의 역할과 상대 이름을 먼저 확인한다.
import 'package:flutter/material.dart';

import '../controls/manage_chat_list_control.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/authenticated_api_client.dart';
import '../widgets/medbuddy_page_header.dart';
import 'link_patient_caregiver_ui_boundary.dart';
import 'linked_chat_ui_boundary.dart';

// 클래스명: LinkedChatEntryUI
// 역할: 알림에서 받은 연결 ID를 현재 계정의 환자·보호자 역할로 해석한다.
// 주요 책임: 활성 연결 확인 후 채팅을 열며 실패 시 잘못된 역할로 진입하지 않는다.
//           조회 성공 후 연동이 없으면 재시도 대신 연동 종료와 연동 관리 이동을 안내한다.
// 속성: apiClient: 연동 확인과 채팅이 함께 쓸 세션 인증 클라이언트. 호출자가 소유하며,
//       없으면 기본 Control과 채팅 화면이 각자 만든다.
class LinkedChatEntryUI extends StatefulWidget {
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

  @override
  State<LinkedChatEntryUI> createState() => _LinkedChatEntryUIState();
}

class _LinkedChatEntryUIState extends State<LinkedChatEntryUI> {
  late final ManageChatList _control;
  PatientCaregiverLink? _link;
  bool _loading = true;
  // 조회는 성공했지만 이 연동이 목록에 없을 때 true. 재시도 대신 연동 종료를 안내한다.
  bool _linkEnded = false;

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

  // 목록과 같은 참여자 검증·별칭 규칙을 사용하고 실패 시 역할을 추측하지 않는다.
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

  // 함수이름: _openLinkManagement
  // 함수역할: 종료된 연동 안내 화면을 연동 관리 화면으로 바꿔 다시 연동하거나 다른 연동을 확인하게 한다.
  // 매개변수: 없음.
  // 반환값: 없음. 현재 경로를 연동 관리 화면으로 교체한다.
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

  // 함수이름: _buildLookupFailed
  // 함수역할: 연동 목록 조회 자체가 실패했을 때 역할을 추측하지 않고 다시 시도를 제공한다.
  // 매개변수: english: 영어 표시 여부.
  // 반환값: 실패 안내 문구와 다시 시도 버튼.
  Widget _buildLookupFailed(bool english) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          english
              ? 'Could not verify this conversation.\nCheck your connection and patient-caregiver link, then try again.'
              : '대화 상대를 확인하지 못했어요.\n네트워크와 환자·보호자 연동 상태를 확인한 뒤 다시 시도해 주세요.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loadLink,
          icon: const Icon(Icons.refresh),
          label: Text(english ? 'Try again' : '다시 시도'),
        ),
      ],
    );
  }

  // 함수이름: _buildEndedLink
  // 함수역할: 알림·알림함에서 연 채팅의 연동이 이미 해제됐음을 알리고 연동 관리 또는 닫기를 제공한다.
  // 매개변수: english: 영어 표시 여부.
  // 반환값: 종료 안내 문구와 이동 버튼.
  Widget _buildEndedLink(bool english) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
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
          label: Text(english ? 'Manage links' : '연동 관리 열기'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(english ? 'Close' : '닫기'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    if (widget.control == null) _control.dispose();
    super.dispose();
  }

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
