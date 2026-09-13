// 파일명: chat_list_ui_boundary.dart
// 역할: 연동된 환자·보호자별 대화 목록에서 기존 복약 맥락 채팅으로 연결한다.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controls/manage_chat_list_control.dart';
import '../entities/chat_message_entity.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import 'linked_chat_ui_boundary.dart';

// 클래스명: ChatListUI
// 역할: 대화 상대·최근 메시지와 갱신 상태를 표시하고 선택한 연동의 채팅을 연다.
// 주요 책임: 목록 표시, 새로고침·연동 관리 진입, 기존 채팅 화면 재사용.
// 속성: control: 사용자 범위의 목록 상태, userSetting: 언어·접근성, onManageLinks: 연동 관리 동작.
class ChatListUI extends StatelessWidget {
  final ManageChatList control;
  final UserSetting userSetting;
  final VoidCallback onManageLinks;

  // 함수이름: ChatListUI
  // 함수역할: 목록 Control과 표시 설정을 주입받는다. Control 소유권은 상위 화면에 있다.
  // 매개변수: key, control, userSetting, onManageLinks: 위젯 식별자, 상태, 설정, 연동 관리 명령.
  // 반환값: 채팅 목록 UI.
  const ChatListUI({
    super.key,
    required this.control,
    required this.userSetting,
    required this.onManageLinks,
  });

  // 함수이름: _isEnglish
  // 함수역할: 현재 설정에서 영어 표시 여부를 읽는다.
  // 매개변수: 없음. 반환값: 영어 여부.
  bool get _isEnglish => userSetting.language.toLowerCase().startsWith('en');

  // 함수이름: build
  // 함수역할: 앱 공통 제목 크기·굵기를 적용하고 큰 글씨에서도 제목과 도구가 잘리지 않게 목록을 표시한다.
  // 매개변수: context: 표시 문맥. 반환값: 하단 탐색 막대 안에서 사용할 대화 목록.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: control,
      // 함수이름: 대화 목록 builder
      // 함수역할: 조회 상태 변경을 현재 목록에 반영한다.
      // 매개변수: context, child: 표시 문맥과 미사용 하위 위젯. 반환값: 채팅 목록 화면.
      builder: (context, child) => Scaffold(
        backgroundColor: MedBuddyColors.pageBackground,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: MedBuddyColors.pageBackground,
          foregroundColor: MedBuddyColors.primaryDark,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleSpacing: MedBuddySpacing.pageHorizontal,
          // 내 정보와 같은 제목 스타일을 사용하고 확대된 한 줄 높이에 여백을 더한다.
          toolbarHeight: math.max(
            72,
            MediaQuery.textScalerOf(context).scale(28) * 1.2 + 32,
          ),
          title: Text(
            _isEnglish ? 'Chat' : '채팅',
            key: const ValueKey('chatListTitle'),
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 28,
              height: 1.2,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          actions: [
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: _isEnglish ? 'Refresh' : '새로고침',
            ),
            IconButton(
              onPressed: onManageLinks,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: _isEnglish ? 'Manage connections' : '환자·보호자 연동 관리',
            ),
          ],
        ),
        body: Column(
          children: [
            if (control.isLoading) const LinearProgressIndicator(minHeight: 2),
            if (control.hasError)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _isEnglish
                      ? 'Could not refresh connections. Please try again.'
                      : '연동 목록을 새로 불러오지 못했어요. 다시 시도해주세요.',
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (control.links.isEmpty && !control.isLoading)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _isEnglish ? 'No connected chats' : '연동된 대화가 없어요',
                        ),
                      ),
                    for (final link in control.links)
                      _buildConversation(context, link),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 함수이름: _buildConversation
  // 함수역할: 환자 별칭·보호자 식별자와 최근 메시지를 하나의 대화 행으로 표시한다.
  // 매개변수: context, link: 표시 문맥과 활성 연동. 반환값: 대화 선택 행.
  Widget _buildConversation(BuildContext context, PatientCaregiverLink link) {
    final message = control.latestMessage(link.linkId!);
    final isCaregiver = control.isCaregiver(link);
    return Column(
      children: [
        ListTile(
          key: ValueKey('chatConversation-${link.linkId}'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
          leading: CircleAvatar(
            backgroundColor: MedBuddyColors.mint,
            foregroundColor: MedBuddyColors.primaryDark,
            child: Icon(
              isCaregiver
                  ? Icons.person_outline
                  : Icons.health_and_safety_outlined,
            ),
          ),
          title: Text(
            control.peerName(link, isEnglish: _isEnglish),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _preview(link.linkId!, message),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: MedBuddyColors.textSubtle,
          ),
          // 함수이름: 대화 선택 콜백
          // 함수역할: 해당 상대의 복약 맥락 채팅을 연다.
          // 매개변수: 없음. 반환값: 화면 이동 완료.
          onTap: () => _openChat(context, link),
        ),
        const Divider(height: 1, indent: 76, endIndent: 20),
      ],
    );
  }

  // 함수이름: _preview
  // 함수역할: 미리보기 실패·삭제·빈 대화를 구분하고 삭제된 본문은 표시하지 않는다.
  // 매개변수: linkId, message: 연동 ID와 최근 메시지. 반환값: 표시할 미리보기.
  String _preview(int linkId, ChatMessage? message) {
    if (control.previewFailed(linkId)) {
      return _isEnglish ? 'Preview unavailable' : '미리보기를 불러오지 못했어요';
    }
    if (message == null) return _isEnglish ? 'No messages yet' : '아직 대화가 없어요';
    if (message.deletedForEveryone) {
      return _isEnglish ? 'Message deleted' : '삭제된 메시지입니다';
    }
    return message.body.isNotEmpty
        ? message.body
        : (_isEnglish ? 'Medication information' : '복약 정보');
  }

  // 함수이름: _refresh
  // 함수역할: 상대 목록과 최근 메시지를 읽음 상태 변경 없이 갱신한다.
  // 매개변수: 없음. 반환값: 갱신 완료.
  Future<void> _refresh() => control.refresh(includeMessages: true);

  // 함수이름: _openChat
  // 함수역할: 기존 권한 검증·복약 첨부·실시간 대화 화면을 열고 돌아오면 미리보기를 갱신한다.
  // 매개변수: context, link: 표시 문맥과 선택한 연동. 반환값: 대화 종료와 목록 갱신 완료.
  Future<void> _openChat(
    BuildContext context,
    PatientCaregiverLink link,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        // 함수이름: 채팅 경로 builder
        // 함수역할: 선택한 연동의 기존 채팅 UI를 구성한다.
        // 매개변수: context: 경로 문맥. 반환값: 복약 맥락 채팅 화면.
        builder: (context) => LinkedChatUI(
          linkId: link.linkId!,
          currentUserHash: control.userHash,
          patientHash: link.patientHash,
          peerName: control.peerName(link, isEnglish: _isEnglish),
          userSetting: userSetting,
        ),
      ),
    );
    await _refresh();
  }
}
