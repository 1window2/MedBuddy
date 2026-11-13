// 파일명: chat_list_ui_boundary.dart
// 역할: 연동된 환자·보호자별 대화 목록에서 기존 복약 맥락 채팅으로 연결한다.

import 'package:flutter/material.dart';

import '../controls/manage_chat_list_control.dart';
import '../entities/chat_message_entity.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/authenticated_api_client.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/medbuddy_page_header.dart';
import '../widgets/medbuddy_notice.dart';
import 'linked_chat_ui_boundary.dart';
import '../widgets/keep_words_text.dart';

// 클래스명: ChatListUI
// 역할: 대화 상대·최근 메시지와 갱신 상태를 표시하고 선택한 연동의 채팅을 연다.
// 주요 책임: 목록 표시, 새로고침·연동 관리 진입, 기존 채팅 화면 재사용.
// 속성: control: 사용자 범위의 목록 상태, userSetting: 언어·접근성, onManageLinks: 연동 관리 동작,
//       apiClient: 연 채팅이 함께 쓸 세션 인증 클라이언트(없으면 채팅 화면이 직접 만든다).
class ChatListUI extends StatelessWidget {
  final ManageChatList control;
  final UserSetting userSetting;
  final VoidCallback onManageLinks;
  final AuthenticatedApiClient? apiClient;

  // Function Name: ChatListUI
  // Description: Binds chat-list state and display settings without taking ownership of the controller or optional authenticated client.
  // Parameters: key (Key?): identity; control (ManageChatList): list state; userSetting (UserSetting): display settings; onManageLinks: link-management action; apiClient: optional client sharing session-expiry handling.
  // Returns: A configured ChatListUI.
  const ChatListUI({
    super.key,
    required this.control,
    required this.userSetting,
    required this.onManageLinks,
    this.apiClient,
  });

  // Function Name: _isEnglish
  // Description: Reads the selected language from the supplied user settings.
  // Parameters: None.
  // Returns: True when English is selected.
  bool get _isEnglish => userSetting.isEnglish;

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
        body: Column(
          children: [
            MedBuddyPageHeader(
              title: _isEnglish ? 'Chat' : '채팅',
              subtitle: _isEnglish
                  ? 'Message your family.'
                  : '가족과 메시지를 주고받습니다.',
              titleKey: const ValueKey('chatListTitle'),
              prominent: true,
              actions: [
                IconButton(
                  onPressed: _refreshRequested,
                  icon: const Icon(Icons.refresh),
                  tooltip: _isEnglish ? 'Refresh' : '새로고침',
                ),
                IconButton(
                  onPressed: onManageLinks,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  tooltip: _isEnglish ? 'Manage links' : '환자·보호자 연동 관리',
                ),
              ],
            ),
            if (control.isLoading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshRequested,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (control.hasError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: MedBuddyNotice(
                          key: const ValueKey('chatLinkLookupError'),
                          message: _isEnglish
                              ? 'Could not check your connections. Check your internet connection and try again.'
                              : '연동 상태를 확인하지 못했어요. 인터넷 연결을 확인하고 다시 시도해주세요.',
                          action: OutlinedButton.icon(
                            key: const ValueKey('chatLinkLookupRetry'),
                            onPressed: control.isLoading
                                ? null
                                : _refreshRequested,
                            icon: const Icon(Icons.refresh),
                            label: KeepWordsText(
                              _isEnglish ? 'Retry' : '다시 시도',
                            ),
                          ),
                        ),
                      ),
                    if (control.hasResolvedLinks &&
                        control.links.isEmpty &&
                        !control.hasError &&
                        !control.isLoading)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: KeepWordsText(
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
    final unread = control.unreadCount(link.linkId!) ?? 0;
    final isCaregiver = control.isCaregiver(link);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: ValueKey('chatConversationFrame-${link.linkId}'),
        color: MedBuddyColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: MedBuddyRadii.largeCard,
          side: const BorderSide(color: MedBuddyColors.cardBorder),
        ),
        child: ListTile(
          key: ValueKey('chatConversation-${link.linkId}'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 12,
          ),
          horizontalTitleGap: 14,
          minLeadingWidth: 46,
          titleAlignment: ListTileTitleAlignment.center,
          leading: CircleAvatar(
            radius: 23,
            backgroundColor: MedBuddyColors.mint,
            foregroundColor: MedBuddyColors.primaryDark,
            child: Icon(
              isCaregiver
                  ? Icons.person_outline
                  : Icons.health_and_safety_outlined,
              size: 27,
            ),
          ),
          title: KeepWordsText(
            control.peerName(link, isEnglish: _isEnglish),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 17,
              height: 1.25,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: KeepWordsText(
              _preview(link.linkId!, message),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unread > 0)
                Semantics(
                  label: _isEnglish
                      ? '$unread unread messages'
                      : '안 읽은 메시지 $unread개',
                  child: ExcludeSemantics(
                    child: Badge(
                      key: ValueKey('chatUnread-${link.linkId}'),
                      label: Text(unread > 99 ? '99+' : '$unread'),
                    ),
                  ),
                ),
              if (unread > 0) const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: MedBuddyColors.textSubtle),
            ],
          ),
          // 함수이름: 대화 선택 콜백
          // 함수역할: 해당 상대의 복약 맥락 채팅을 연다.
          // 매개변수: 없음. 반환값: 화면 이동 완료.
          onTap: () => _openChat(context, link),
        ),
      ),
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

  // Function Name: _refreshRequested
  // Description: Refreshes links and message previews with visible progress for an explicit user request.
  // Parameters: None.
  // Returns: Future completing after the refresh.
  Future<void> _refreshRequested() =>
      control.refresh(includeMessages: true, showLoading: true);

  // Function Name: _openChat
  // Description: Opens the linked conversation with permission checks and medication attachments, then refreshes its preview on return.
  // Parameters: context (BuildContext): navigation host; link: selected patient-caregiver link.
  // Returns: Future completing when the conversation closes and refresh finishes.
  Future<void> _openChat(
    BuildContext context,
    PatientCaregiverLink link,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        // 채팅 알림이 같은 대화를 다시 쌓지 않도록 알림 경로와 같은 이름을 쓴다.
        settings: RouteSettings(name: linkedChatRouteName(link.linkId!)),
        // 함수이름: 채팅 경로 builder
        // 함수역할: 선택한 연동의 기존 채팅 UI를 구성한다.
        // 매개변수: context: 경로 문맥. 반환값: 복약 맥락 채팅 화면.
        builder: (context) => LinkedChatUI(
          linkId: link.linkId!,
          currentUserHash: control.userHash,
          patientHash: link.patientHash,
          peerName: control.peerName(link, isEnglish: _isEnglish),
          userSetting: userSetting,
          apiClient: apiClient,
        ),
      ),
    );
    await _refresh();
  }
}
