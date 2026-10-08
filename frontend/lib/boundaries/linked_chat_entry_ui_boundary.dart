// 알림의 연결 ID만으로 채팅을 열 때 현재 사용자의 역할과 상대 이름을 먼저 확인한다.
import 'package:flutter/material.dart';

import '../controls/manage_chat_list_control.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/authenticated_api_client.dart';
import '../widgets/medbuddy_page_header.dart';
import 'linked_chat_ui_boundary.dart';

// 클래스명: LinkedChatEntryUI
// 역할: 알림에서 받은 연결 ID를 현재 계정의 환자·보호자 역할로 해석한다.
// 주요 책임: 활성 연결 확인 후 채팅을 열며 실패 시 잘못된 역할로 진입하지 않는다.
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
    if (!_control.hasError && _control.userHash == widget.currentUserHash) {
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
      _loading = false;
    });
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
                      child: Column(
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
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
