// 파일명: linked_chat_ui_boundary.dart
// 역할: 연동 사용자 채팅과 약품·일정·약국 정보 공유를 제공한다.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'check_schedule_ui_boundary.dart';
import 'check_medication_detail_ui_boundary.dart';
import 'check_nearby_pharmacy_ui_boundary.dart';
import 'medication_history_ui_boundary.dart';
import 'medication_search_ui_boundary.dart';
import '../controls/check_medication_detail_control.dart';
import '../entities/medication_detail_entity.dart';
import '../widgets/chat_medication_reference_tile.dart';
import '../controls/manage_linked_chat_control.dart';
import '../services/notification_service.dart';
import '../entities/chat_message_entity.dart';
import '../entities/chat_message_draft_entity.dart';
import '../entities/medication_image_url_entity.dart';
import '../entities/medication_history_entity.dart';
import '../entities/nearby_care_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/medication_slot_label.dart';
import '../entities/user_setting_entity.dart';
import '../services/authenticated_api_client.dart';
import '../services/linked_chat_realtime_service.dart';
import '../services/pharmacy_external_action_service.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_view_model.dart';
import '../viewmodels/linked_chat_history_view_model.dart';
import '../viewmodels/linked_chat_composer_view_model.dart';
import '../viewmodels/linked_chat_dose_recorder.dart';
import '../widgets/dose_sync_status.dart';
import '../widgets/medbuddy_page_header.dart';
import '../widgets/medication_history_charts.dart';
import '../widgets/chat_date_divider.dart';
import '../widgets/chat_place_map_preview.dart';
import '../widgets/keep_words_text.dart';

// Function Name: linkedChatRouteName
// Description: Uses one route name for the same linked conversation regardless of notification, list or link-management entry.
// Parameters: linkId (int): conversation link ID.
// Returns: The stable conversation route name.
String linkedChatRouteName(int linkId) => '/linked-chat/$linkId';

// Class Name: LinkedChatRouteObserver
// Role: Open linked-conversation route tracking.
// Responsibilities: Lets notification navigation reuse an existing conversation instead of stacking a duplicate, including routes opened from lists or link management.
// Attributes: _open (Map<String, int>): open route count by name.
class LinkedChatRouteObserver extends NavigatorObserver {
  final Map<String, int> _open = {};

  // Function Name: isOpen
  // Description: Checks whether the linked conversation is already on the route stack.
  // Parameters: linkId (int): conversation link ID.
  // Returns: True when at least one matching route is open.
  bool isOpen(int linkId) => (_open[linkedChatRouteName(linkId)] ?? 0) > 0;

  // Function Name: _track
  // Description: Adjusts the tracked open count when a linked-chat route enters or leaves the stack.
  // Parameters: route: changed route; change (int): +1 on entry or -1 on removal.
  // Returns: None.
  void _track(Route<dynamic>? route, int change) {
    final name = route?.settings.name;
    if (name == null || !name.startsWith('/linked-chat/')) return;
    final count = (_open[name] ?? 0) + change;
    if (count > 0) {
      _open[name] = count;
    } else {
      _open.remove(name);
    }
  }

  // Function Name: didPush
  // Description: Registers a pushed route in the per-link open-route count.
  // Parameters: route (Route<dynamic>): pushed route; previousRoute (Route<dynamic>?): prior route, unused.
  // Returns: No return value.
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _track(route, 1);

  // Function Name: didPop
  // Description: Removes a popped route from the per-link open-route count.
  // Parameters: route (Route<dynamic>): popped route; previousRoute (Route<dynamic>?): revealed route, unused.
  // Returns: No return value.
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _track(route, -1);

  // Function Name: didRemove
  // Description: Removes a deleted route from the per-link open-route count.
  // Parameters: route (Route<dynamic>): removed route; previousRoute (Route<dynamic>?): prior route, unused.
  // Returns: No return value.
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _track(route, -1);

  // Function Name: didReplace
  // Description: Replaces the tracked route contribution so notification routing sees the current open conversation.
  // Parameters: newRoute/oldRoute (Route<dynamic>?): replacement and replaced routes.
  // Returns: No return value; null or unrelated routes are ignored by tracking.
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _track(oldRoute, -1);
    _track(newRoute, 1);
  }
}

// 클래스명: LinkedChatUI
// 역할: 연동 사용자 메시지와 복약 관련 첨부를 담당한다.
// 주요 책임:
// - 연동 사용자 메시지와 복약 관련 첨부의 State가 사용할 화면 설정과 외부 의존성을 보관한다.
// 속성:
// - linkId (int): 대화·별칭·연결 작업의 연동 식별자.
// - currentUserHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
// - patientHash (String): 연동된 환자의 계정 해시.
// - peerName (String): 대화 상대를 표시할 이름.
class LinkedChatUI extends StatelessWidget {
  final int linkId;
  final String currentUserHash;
  final String patientHash;
  final String peerName;
  final UserSetting userSetting;
  final List<ChatMedicationContext> initialMedicationContexts;
  final ManageLinkedChat? control;
  final LinkedChatRealtimeService? realtimeService;
  final AuthenticatedApiClient? apiClient;
  final Widget Function(bool hospitals)? careSelectorBuilder;
  final Widget Function(NearbyCarePlace place, bool hospitals)?
  careDetailsBuilder;
  final Listenable? latestMessageRequest;

  // 함수이름: LinkedChatUI
  // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - linkId (int): 대화·별칭·연결 작업의 연동 식별자.
  // - currentUserHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
  // - patientHash (String): 연동된 환자의 계정 해시.
  // - peerName (String): 대화 상대를 표시할 이름.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - initialMedicationContexts (List<ChatMedicationContext>): 채팅에 첨부하거나 선택할 초기 복약 맥락 목록.
  // - control (ManageLinkedChat?): 화면의 조회·변경 요청을 처리할 컨트롤러.
  // - realtimeService (LinkedChatRealtimeService?): 연동 채팅의 이벤트·연결 상태 스트림 제공자.
  // - apiClient (AuthenticatedApiClient?): 인증 세션을 사용하는 API 요청 클라이언트.
  // - careSelectorBuilder (Widget Function(bool hospitals)?): 병원 여부를 받아 공유할 시설 선택 화면을 만드는 함수. 생략하면 기본 검색 화면을 사용한다.
  // - careDetailsBuilder (Widget Function(NearbyCarePlace place, bool hospitals)?): 공유 장소와 병원 여부로 최신 상세 조회 화면을 만드는 함수. 생략하면 기본 검색 화면으로 다시 조회한다.
  // - latestMessageRequest (Listenable?): 같은 대화의 최신 메시지 이동 요청 신호. 초기화된 채팅이 보일 때 이력을 보충하고 목록 끝으로 이동한다.
  // 반환값: 입력 설정이 반영된 LinkedChatUI 인스턴스.
  const LinkedChatUI({
    super.key,
    required this.linkId,
    required this.currentUserHash,
    required this.patientHash,
    this.peerName = '가족',
    this.userSetting = const UserSetting(),
    this.initialMedicationContexts = const [],
    this.control,
    this.realtimeService,
    this.apiClient,
    this.careSelectorBuilder,
    this.careDetailsBuilder,
    this.latestMessageRequest,
  });

  // Function Name: build
  // Description: Preserves same-conversation drafts and disposes scoped state after an account/link change.
  // Parameters: context: Build context. Returns: An identity-keyed conversation session.
  @override
  Widget build(BuildContext context) => _LinkedChatSessionUI(
    key: ValueKey((currentUserHash, linkId, patientHash)),
    configuration: this,
  );
}

// Class Name: _LinkedChatSessionUI
// Role: Gives account/link-scoped asynchronous work an explicit widget lifetime.
// Responsibilities: Own presentation/composer state for one immutable conversation identity.
// Attributes: configuration: Current presentation inputs and optional borrowed adapters.
class _LinkedChatSessionUI extends StatefulWidget {
  final LinkedChatUI configuration;

  // Function Name: _LinkedChatSessionUI
  // Description: Stores screen inputs behind a conversation identity key.
  // Parameters: key: Scope identity; configuration: Screen inputs. Returns: A scoped widget.
  const _LinkedChatSessionUI({super.key, required this.configuration});

  // Function Name: createState
  // Description: Creates presentation/composer state for this account/link lifetime.
  // Parameters: None. Returns: A new session state.
  @override
  State<_LinkedChatSessionUI> createState() => _LinkedChatUIState();
}

// 클래스명: _LinkedChatUIState
// 역할: 계정·연동 세션의 작성창·선택·이동·화면 표시 상태.
// 주요 책임: 기록·재시도·읽음 처리의 동시성은 독립 기록 소유자에게 위임하고 표시 포트를 화면에 반영하며 기록을 먼저 종료한 뒤 이 세션 소유 어댑터만 정리한다.
// 속성: _scrollController: 화면 위치; _history: 기록·전송 구독·읽음/재시도 수명; _control/_apiClient/_realtimeService: 외부 제공 또는 직접 소유 인증 어댑터.
class _LinkedChatUIState extends State<_LinkedChatSessionUI>
    with WidgetsBindingObserver {
  // Function Name: _configuration
  // Description: Reads current presentation inputs for this immutable account/link session.
  // Parameters: None. Returns: Public screen configuration.
  LinkedChatUI get _configuration => widget.configuration;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final PharmacyExternalActionService _pharmacyActionService =
      PharmacyExternalActionService();

  late final AuthenticatedApiClient _apiClient;
  late final ManageLinkedChat _control;
  late final LinkedChatRealtimeService _realtimeService;
  late final bool _ownsApiClient;
  late final bool _ownsControl;
  late final bool _ownsRealtimeService;

  Timer? _medicationContextGuideTimer;
  List<ChatMedicationContext> _medicationContexts = const [];
  List<ChatScheduleContext> _scheduleContexts = const [];
  // 기능 메뉴가 아직 받지 못한 목록을 "없음"으로 안내하지 않도록 조회 상태를 따로 둔다.
  _ChatContextLoad _scheduleLoad = _ChatContextLoad.loading;
  List<ChatMedicationContext> _selectedMedicationContexts = const [];
  List<ChatMedicationReference> _selectedMedicationReferences = const [];
  String? _selectedMedicationScheduleDate;
  String? _sendErrorMessage;
  bool _checkedLinkAfterSendFailure = false;
  bool _isRecordingTaken = false;
  bool _isSelectingMessages = false;
  bool _isChatActionsOpen = false;
  final _chatActionsRevision = ValueNotifier<int>(0);
  bool _isDeletingMessages = false;
  final Set<int> _selectedMessageIds = {};
  ({
    NearbyCareSelection selection,
    bool hospitals,
    List<ChatMedicationContext> medications,
    String clientMessageId,
  })?
  _pendingCareShare;
  int? _loadingMedicationId;
  int _requestGeneration = 0;
  bool _chatInitialized = false;
  bool _wasChatVisible = false;
  bool _showMedicationContextGuide = true;

  late final LinkedChatHistoryViewModel _history;

  late final LinkedChatComposerViewModel _composer;

  late final LinkedChatDoseRecorder _doseRecorder;

  // Function Name: _isSending
  // Description: Prevents UI actions from racing either an outgoing message or a dose record.
  // Parameters: None. Returns: Whether one of the two independent operations is busy.
  bool get _isSending => _composer.isSending || _isRecordingTaken;

  // Function Name: _messages
  // Description: Reads independently owned history presentation state.
  // Parameters: None. Returns: Immutable visible messages.
  List<ChatMessage> get _messages => _history.messages;

  // Function Name: _isLoading
  // Description: Reads independently owned history presentation state.
  // Parameters: None. Returns: Whether initial/retry history is loading.
  bool get _isLoading => _history.isLoading;

  // Function Name: _connectionState
  // Description: Reads independently owned history presentation state.
  // Parameters: None. Returns: Current realtime connection state.
  LinkedChatConnectionState get _connectionState => _history.connectionState;

  // Function Name: _firstUnreadMessageId
  // Description: Reads independently owned history presentation state.
  // Parameters: None. Returns: Stable first-unread separator for this visit.
  int? get _firstUnreadMessageId => _history.firstUnreadMessageId;

  // Function Name: _hasOlderMessages
  // Description: Reads independently owned history presentation state.
  // Parameters: None. Returns: Whether an older page can be requested.
  bool get _hasOlderMessages => _history.hasOlderMessages;

  // Function Name: _loadingOlderMessages
  // Description: Reads independently owned history presentation state.
  // Parameters: None. Returns: Whether backward pagination is in flight.
  bool get _loadingOlderMessages => _history.loadingOlderMessages;

  // Function Name: _olderMessagesFailed
  // Description: Reads independently owned history presentation state.
  // Parameters: None. Returns: Whether the last older page failed.
  bool get _olderMessagesFailed => _history.olderMessagesFailed;

  // Function Name: _errorMessage
  // Description: Localizes technical history failure at the presentation boundary.
  // Parameters: None. Returns: Initial-history failure text, or null.
  String? get _errorMessage =>
      _history.historyFailed ? _text.historyLoadFailed : null;

  // 함수이름: _isAtLatest
  // 함수역할: 스크롤이 연결되지 않았거나 최신 메시지에서 지정 여유 거리 안에 있는지 확인한다.
  // 매개변수: 없음.
  // 반환값: 최신 위치로 간주하면 true.
  bool get _isAtLatest =>
      _scrollController.hasClients &&
      _scrollController.position.extentBefore <= 8;

  // 함수이름: _isChatVisible
  // 함수역할: 앱이 전면에 있고 다른 화면이 채팅을 가리지 않는지 확인한다.
  // 매개변수: 없음. 반환값: 읽음 처리와 자동 스크롤을 허용할지 여부.
  bool get _isChatVisible {
    final state = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        (state == null || state == AppLifecycleState.resumed) &&
        ModalRoute.of(context)?.isCurrent == true;
  }

  // Function Name: _text
  // Description: Creates chat and medication/place-sharing copy for the current language.
  // Parameters: None.
  // Returns: The current _LinkedChatText provider.
  _LinkedChatText get _text =>
      _LinkedChatText(_configuration.userSetting.language);

  // Function Name: _isPatient
  // Description: Checks that the nonempty linked patient hash matches the current account.
  // Parameters: None.
  // Returns: True when this participant is the patient.
  bool get _isPatient =>
      _configuration.patientHash.isNotEmpty &&
      _configuration.currentUserHash == _configuration.patientHash;

  // 함수이름: _requestableScheduleContexts
  // 함수역할: 환자에게는 요청 도구를 숨기고 서버가 확인 요청을 허용한 시간대만 제공한다.
  // 매개변수: 없음. 반환값: 보호자가 요청할 수 있는 시간대 목록.
  List<ChatScheduleContext> get _requestableScheduleContexts {
    if (_isPatient) return const [];
    return _scheduleContexts
        .where(
          // 함수이름: 요청 가능 시간대 필터
          // 함수역할: 서버 응답의 요청 가능 여부를 표시 조건으로 사용한다.
          // 매개변수: schedule: 시간대 맥락. 반환값: 요청 도구에 표시할지 여부.
          (schedule) => schedule.canRequestCheck,
        )
        .toList(growable: false);
  }

  // Function Name: _peerName
  // Description: Localizes only the default family-member name in English, preserving a custom peer name.
  // Parameters: None.
  // Returns: The peer's display name.
  String get _peerName {
    if (_text.isEnglish && _configuration.peerName == '가족') {
      return _text.family;
    }
    return _configuration.peerName;
  }

  // 함수이름: initState
  // 함수역할: 초기 약품 맥락·API·실시간 구독을 준비하고 안내 타이머와 첫 채팅 조회를 시작한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    _configuration.latestMessageRequest?.addListener(_onLatestMessageRequested);
    _medicationContexts = _configuration.initialMedicationContexts;
    WidgetsBinding.instance.addObserver(this);
    _ownsApiClient = _configuration.apiClient == null;
    _apiClient = _configuration.apiClient ?? AuthenticatedApiClient();
    _ownsControl = _configuration.control == null;
    _control =
        _configuration.control ??
        ManageLinkedChat(
          userHash: _configuration.currentUserHash,
          client: _apiClient,
        );
    _ownsRealtimeService = _configuration.realtimeService == null;
    _realtimeService =
        _configuration.realtimeService ??
        LinkedChatRealtimeService(
          linkId: _configuration.linkId,
          userHash: _configuration.currentUserHash,
          authenticationClient: _apiClient,
        );
    _composer = LinkedChatComposerViewModel(
      linkId: _configuration.linkId,
      control: _control,
    )..addListener(_composerChanged);
    _doseRecorder = LinkedChatDoseRecorder(
      linkId: _configuration.linkId,
      currentUserHash: _configuration.currentUserHash,
      control: _control,
      createRequestId: _composer.createClientMessageId,
    );
    _history = LinkedChatHistoryViewModel(
      linkId: _configuration.linkId,
      userHash: _configuration.currentUserHash,
      control: _control,
      realtime: _realtimeService,
      isVisible: () => _isChatVisible,
      isAtLatest: () => _isAtLatest,
      onScrollRequested: (force) => _scrollToLatest(force: force),
      onScheduleChanged: () => unawaited(_refreshScheduleContexts()),
      onRead: (id) => NotificationService.instance.clearReadChatAlert(
        owner: _configuration.currentUserHash,
        linkId: _configuration.linkId,
        throughMessageId: id,
      ),
      onDeleted: (ids) {
        if (mounted) setState(() => _selectedMessageIds.removeAll(ids));
      },
    )..addListener(_historyChanged);
    // 함수이름: initState.Timer callback
    // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에서 캡처된 작업 `setState(() => _showMedicationContextGuide = false)`을 실행한다.
    // 매개변수:
    // - 없음.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    _medicationContextGuideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        // 함수이름: initState.setState callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_showMedicationContextGuide = false`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() => _showMedicationContextGuide = false);
      }
    });
    // 함수이름: initState.addPostFrameCallback callback
    // 함수역할: 메시지·약품·시간대 맥락과 실시간 연결을 함께 초기화한 뒤 12초 보완 조회를 시작한다.
    // 매개변수:
    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeChat());
    });
  }

  // Function Name: _composerChanged
  // Description: Localizes outgoing failure and rebuilds busy state without owning retry/concurrency logic. After a failed send it asks the history owner to look at the link once, which is how a link removed by the other participant is recognised without waiting for the stream to close.
  // Parameters: None. Returns: None; context/dose errors remain presentation-owned.
  void _composerChanged() {
    if (!mounted) return;
    setState(() {
      if (_composer.isSending) {
        _sendErrorMessage = null;
      } else if (_composer.medicationReferencesExpired) {
        // 다시 보내도 같은 이유로 거절되므로 만료된 검색약을 빼고 다시 검색하게 한다.
        _selectedMedicationReferences = const [];
        _sendErrorMessage = _text.medicationReferencesExpired;
      } else if (_composer.sendFailed) {
        _sendErrorMessage = _text.sendFailed;
      }
    });
    // 연동이 해제되어 실패한 전송이면 기록 조회가 그 사실을 알아내 입력창을 안내로 바꾼다.
    if (_composer.isSending) {
      _checkedLinkAfterSendFailure = false;
    } else if (_composer.sendFailed &&
        !_checkedLinkAfterSendFailure &&
        !_history.linkUnavailable) {
      // 실패 한 번에 한 번만 확인한다. 작성 상태 알림마다 조회를 반복하지 않는다.
      _checkedLinkAfterSendFailure = true;
      unawaited(_refreshMessages(showLoading: false));
    }
  }

  // 함수이름: _historyChanged
  // 함수역할: 살아 있는 화면에 갱신된 이력을 반영하고 열린 기능 메뉴에도 연동 종료 등 새 사용 가능 상태를 통지한다.
  // 매개변수: 없음.
  // 반환값: 없음. 작성 중인 초안은 변경하지 않는다.
  void _historyChanged() {
    if (!mounted) return;
    setState(() {});
    _notifyChatActions();
  }

  // 함수이름: _onLatestMessageRequested
  // 함수역할: 알림에서 같은 대화를 요청하면 다음 프레임에 최신 이력을 보충하고 보이는 채팅만 끝으로 이동한다.
  // 매개변수: 없음.
  // 반환값: 없음. 초안·선택은 유지하고 초기화 전·숨겨진 화면은 무시한다.
  void _onLatestMessageRequested() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_isChatVisible || !_chatInitialized) return;
      await _refreshMessages(showLoading: false, catchUp: true);
      if (_isChatVisible) _scrollToLatest();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // Function Name: didUpdateWidget
  // Description: Replaces the latest-message notification subscription when the session widget receives a different signal.
  // Parameters: oldWidget (_LinkedChatSessionUI): previous signal owner.
  // Returns: No return value; the old signal cannot keep triggering this chat.
  @override
  void didUpdateWidget(covariant _LinkedChatSessionUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configuration.latestMessageRequest !=
        _configuration.latestMessageRequest) {
      oldWidget.configuration.latestMessageRequest?.removeListener(
        _onLatestMessageRequested,
      );
      _configuration.latestMessageRequest?.addListener(
        _onLatestMessageRequested,
      );
    }
  }

  // 함수이름: didChangeDependencies
  // 함수역할: 약 선택·상세 화면에서 돌아온 뒤 보이게 된 채팅의 읽음 상태를 갱신한다.
  // 매개변수: 없음. 반환값: 없음.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = _isChatVisible;
    if (visible && !_wasChatVisible && _chatInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isChatVisible) {
          unawaited(_refreshMessages(showLoading: false, catchUp: true));
        }
      });
    }
    _wasChatVisible = visible;
    if (_isChatVisible && _messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_markLatestIncomingRead());
      });
    }
  }

  // Function Name: dispose
  // Description: Invalidates pending context work, detaches listeners and disposes history/composer/presentation resources before closing only owned authenticated adapters.
  // Parameters: None.
  // Returns: None.
  @override
  void dispose() {
    _configuration.latestMessageRequest?.removeListener(
      _onLatestMessageRequested,
    );
    WidgetsBinding.instance.removeObserver(this);
    _requestGeneration += 1;
    _medicationContextGuideTimer?.cancel();
    _chatActionsRevision.dispose();
    _history.removeListener(_historyChanged);
    _history.dispose();
    _composer.removeListener(_composerChanged);
    _composer.dispose();
    if (_ownsRealtimeService) {
      unawaited(_realtimeService.dispose());
    }
    if (_ownsControl) {
      _control.dispose();
    }
    if (_ownsApiClient) {
      _apiClient.close();
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Function Name: didChangeAppLifecycleState
  // Description: Passes foreground state to the history owner so it controls transport and refresh lifetime.
  // Parameters: state (AppLifecycleState): current app lifecycle state.
  // Returns: None.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _history.setForeground(state == AppLifecycleState.resumed);
  }

  // Function Name: _initializeChat
  // Description: While mounted, marks chat initialized and concurrently initializes history plus medication and schedule contexts.
  // Parameters: None.
  // Returns: Future completing after all three initialization requests.
  Future<void> _initializeChat() async {
    if (!mounted) return;
    _chatInitialized = true;
    await Future.wait([
      _history.initialize(),
      _refreshMedicationContexts(),
      _refreshScheduleContexts(),
    ]);
  }

  // Function Name: _refreshMedicationContexts
  // Description: Loads active medication context for the linked patient and rejects results from an obsolete request generation.
  // Parameters: None.
  // Returns: Future completing after context loading and eligible screen updates.
  Future<void> _refreshMedicationContexts() async {
    final generation = _requestGeneration;
    try {
      final medications = await _control.requestMedicationContexts(
        linkId: _configuration.linkId,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      // 함수이름: _refreshMedicationContexts.setState callback
      // 함수역할: 약 정보를 갱신하되 사용자가 고른 시간대를 전체 시간대로 넓히지 않는다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _medicationContexts = medications;
        final selectedSlots = {
          for (final item in _selectedMedicationContexts)
            item.medicationId: item.scheduleSlotKeys,
        };
        _selectedMedicationContexts = medications
            // 함수이름: _refreshMedicationContexts.where callback
            // 함수역할: 선택된 약의 최신 표시 정보에 원래 선택 시간대를 결합한다.
            // 매개변수:
            // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
            // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
            .where((item) => selectedSlots.containsKey(item.medicationId))
            .map(
              (item) =>
                  item.withScheduleSlots(selectedSlots[item.medicationId]!),
            )
            .toList(growable: false);
      });
      _notifyChatActions();
    } catch (_) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      // 함수이름: _refreshMedicationContexts.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_sendErrorMessage = _text.medicationLoadFailed`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        if (_medicationContexts.isEmpty) {
          final cached = _isPatient
              ? _doseRecorder.cachedMedicationContexts(
                  context.read<MedBuddyViewModel?>(),
                )
              : null;
          if (cached != null) {
            _medicationContexts = cached;
          } else {
            _sendErrorMessage = _text.medicationLoadFailed;
          }
        }
      });
      _notifyChatActions();
    }
  }

  // Function Name: _refreshScheduleContexts
  // Description: Refreshes today's shareable/requestable dose-slot contexts without accepting obsolete session results.
  // Parameters: None.
  // Returns: Future completing after schedule-context loading.
  Future<void> _refreshScheduleContexts() async {
    final generation = _requestGeneration;
    try {
      final contexts = await _control.requestScheduleContexts(
        linkId: _configuration.linkId,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      // 함수이름: _refreshScheduleContexts.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_scheduleContexts = contexts`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _scheduleContexts = contexts;
        _scheduleLoad = _ChatContextLoad.loaded;
      });
      _notifyChatActions();
    } catch (_) {
      // 채팅 자체는 계속 사용할 수 있으므로 시간대 카드 실패는 화면에 알리지 않는다.
      // 이미 받은 목록이 없을 때만 기능 메뉴에 실패를 이유로 표시한다.
      if (!mounted ||
          generation != _requestGeneration ||
          _scheduleLoad == _ChatContextLoad.loaded) {
        return;
      }
      setState(() => _scheduleLoad = _ChatContextLoad.failed);
      _notifyChatActions();
    }
  }

  // Function Name: _refreshMessages
  // Description: Requests history refresh without owning transport/concurrency state.
  // Parameters: showLoading: Retry UI; catchUp: Retain a reconnect/resume follow-up.
  // Returns: Completion of independently owned refresh.
  Future<void> _refreshMessages({
    required bool showLoading,
    bool catchUp = false,
  }) => _history.refresh(showLoading: showLoading, catchUp: catchUp);

  // Function Name: _loadOlderMessages
  // Description: Requests one serialized older page from the history owner.
  // Parameters: None. Returns: Completion of backward pagination.
  Future<void> _loadOlderMessages() => _history.loadOlderMessages();

  // Function Name: _markLatestIncomingRead
  // Description: Acknowledges only a currently visible latest viewport through the history owner.
  // Parameters: None. Returns: Completion of a coalesced acknowledgement.
  Future<void> _markLatestIncomingRead() => _history.markLatestIncomingRead();

  // 함수이름: _sendMessage
  // 함수역할: 작성한 본문과 선택 약품을 전송하고 성공 시 작성창·선택 해제를 요청한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    await _submitMessage(
      body: body,
      medications: _selectedMedicationContexts,
      medicationReferences: _selectedMedicationReferences,
      clearComposer: true,
      clearMedicationSelection: true,
    );
  }

  // 함수이름: _submitMessage
  // 함수역할: 유효한 연동에서 빈 내용·진행 중 작업을 차단하고 메시지를 전송한다. 수락된 결과만 이력에 넣으며 실패 시 초안을 유지한다.
  // 매개변수: body (String): 본문; medications (List<ChatMedicationContext>): 저장 약; medicationReferences (List<ChatMedicationReference>): 검색 약; messageKind (ChatMessageKind): 유형; slotKey/pharmacyId/hospitalId/hospitalScheduleDate/requestId (String?): 첨부·재시도 정보; clearComposer/clearMedicationSelection (bool): 성공 시 초기화.
  // 반환값: Future<ChatMessage?>: 수락 메시지 또는 실패·차단 시 null; 화면 종료 뒤에는 화면 상태를 변경하지 않는다.
  Future<ChatMessage?> _submitMessage({
    required String body,
    List<ChatMedicationContext> medications = const [],
    List<ChatMedicationReference> medicationReferences = const [],
    ChatMessageKind messageKind = ChatMessageKind.text,
    String? slotKey,
    String? pharmacyId,
    String? hospitalId,
    String? hospitalScheduleDate,
    String? requestId,
    bool clearComposer = false,
    bool clearMedicationSelection = false,
  }) async {
    if (!mounted ||
        _history.linkUnavailable ||
        _isSending ||
        _isDeletingMessages ||
        _isSelectingMessages ||
        body.trim().isEmpty) {
      return null;
    }
    FocusScope.of(context).unfocus();
    final message = await _composer.send(
      ChatMessageDraft(
        body: body,
        medicationReferences: medicationReferences,
        medicationIds: medications
            .map((item) => item.medicationId)
            .toList(growable: false),
        messageKind: messageKind,
        slotKey: slotKey,
        pharmacyId: pharmacyId,
        hospitalId: hospitalId,
        hospitalScheduleDate: hospitalScheduleDate,
      ),
      requestId: requestId,
    );
    if (!mounted || message == null) return message;
    if (clearComposer) _messageController.clear();
    _clearPendingRequest();
    setState(() {
      if (clearMedicationSelection) _selectedMedicationContexts = const [];
      if (medicationReferences.isNotEmpty) {
        _selectedMedicationReferences = const [];
      }
      _sendErrorMessage = null;
    });
    _history.addMessage(message);
    _scrollToLatest();
    return message;
  }

  // Function Name: _clearPendingRequest
  // Description: Clears transport retry identity and presentation-owned care retry metadata after edits/success.
  // Parameters: None. Returns: None; it does not modify dose-record retry identities.
  void _clearPendingRequest() {
    _composer.resetRetry();
    _pendingCareShare = null;
  }

  // 함수이름: _sendQuickReply
  // 함수역할: 선택 약품과 빠른 답장을 보내고 병원·약국 탐색은 메시지 버튼에서 선택하게 한다.
  // 매개변수:
  // - reply (_ChatQuickReply): 전송할 빠른 답장 종류.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _sendQuickReply(_ChatQuickReply reply) async {
    final medications = _selectedMedicationContexts;
    if (medications.isEmpty ||
        _isSending ||
        _selectedMedicationReferences.isNotEmpty) {
      return;
    }
    if (_isPatient && reply == _ChatQuickReply.taken) {
      await _recordSelectedMedicationTaken(medications);
      return;
    }
    final messageKind = _isPatient
        ? switch (reply) {
            _ChatQuickReply.shortage => ChatMessageKind.medicationShortage,
            _ChatQuickReply.discomfort => ChatMessageKind.medicationDiscomfort,
            _ => ChatMessageKind.text,
          }
        : ChatMessageKind.text;
    final medicationNames = medications
        // 함수이름: _sendQuickReply.map callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 변환값을 `item.medicationName` 규칙으로 계산한다.
        // 매개변수:
        // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
        // 반환값: 컬렉션 연산에 전달할 변환값.
        .map((item) => item.medicationName)
        .join(', ');
    final body = _text.quickReplyBody(
      reply,
      medicationNames,
      isPatient: _isPatient,
      peerName: _peerName,
    );
    await _submitMessage(
      body: body,
      medications: medications,
      messageKind: messageKind,
      clearMedicationSelection: true,
    );
  }

  // 함수이름: _recordSelectedMedicationTaken
  // 함수역할: 선택한 날짜·약·시간대를 먼저 검증하고 복용 보고를 순차 기록한다. 성공한 시간대만 선택에서 제거해 부분 실패 재시도를 남긴다.
  // 매개변수: selectedMedications (List<ChatMedicationContext>): 선택 화면에서 확정한 약·시간대.
  // 반환값: Future<void>; 오류는 안내하며 화면 종료 후에도 확인한 나머지 기록은 계속하고 화면 갱신만 생략한다.
  Future<void> _recordSelectedMedicationTaken(
    List<ChatMedicationContext> selectedMedications,
  ) async {
    if (_isSending ||
        _isSelectingMessages ||
        _isDeletingMessages ||
        _selectedMedicationReferences.isNotEmpty) {
      return;
    }
    final viewModel = context.read<MedBuddyViewModel?>();
    final selectedDate = _selectedMedicationScheduleDate;
    setState(() {
      _isRecordingTaken = true;
      _sendErrorMessage = null;
    });
    try {
      final contexts = await _doseRecorder.loadScheduleContexts(viewModel);
      // Validate all selections before writing; never substitute another dose/day.
      final plan = LinkedChatDoseRecorder.plan(
        selectedMedications,
        selectedDate,
        contexts,
      );
      if (plan.status != ChatDosePlanStatus.ready) {
        if (mounted) {
          setState(
            () => _sendErrorMessage = switch (plan.status) {
              ChatDosePlanStatus.scheduleChanged =>
                _text.selectionScheduleChanged,
              ChatDosePlanStatus.asNeededSelected =>
                _text.asNeededNotRecordable,
              _ => _text.noConfirmableSchedule,
            },
          );
        }
        return;
      }
      for (final request in plan.requests) {
        final message = await _doseRecorder.record(
          request,
          viewModel: viewModel,
        );
        // 화면을 벗어나도 사용자가 확인한 나머지 시간대는 끝까지 기록하고 화면 갱신만 생략한다.
        if (!mounted) continue;
        if (message != null) _history.addMessage(message);
        setState(() {
          _selectedMedicationContexts = [
            for (final medication in _selectedMedicationContexts)
              if (!request.medicationIds.contains(medication.medicationId))
                medication
              else if (medication.scheduleSlotKeys.any(
                (s) => s != request.slotKey,
              ))
                medication.withScheduleSlots(
                  medication.scheduleSlotKeys
                      .where((s) => s != request.slotKey)
                      .toList(),
                ),
          ];
          if (_selectedMedicationContexts.isEmpty) {
            _selectedMedicationScheduleDate = null;
          }
          _sendErrorMessage = null;
        });
      }
      if (!mounted) return;
      _scrollToLatest();
      await _refreshScheduleContexts();
    } catch (_) {
      if (mounted) setState(() => _sendErrorMessage = _text.takenSaveFailed);
    } finally {
      if (mounted) {
        setState(() {
          _isRecordingTaken = false;
        });
      }
    }
  }

  // 함수이름: _showChatActions
  // 함수역할: 연동이 유효하고 다른 작업이 없을 때 기능 메뉴를 열며, 메뉴 종료 후에도 연동 상태를 다시 확인한다.
  // 매개변수: 없음.
  // 반환값: 선택 기능 완료 Future<void>; 취소·연동 종료·화면 종료 시 실행하지 않는다.
  Future<void> _showChatActions() async {
    if (_history.linkUnavailable ||
        _isSending ||
        _isSelectingMessages ||
        _isDeletingMessages ||
        _isChatActionsOpen) {
      return;
    }
    _isChatActionsOpen = true;
    final _ChatAction? action;
    try {
      action = await showModalBottomSheet<_ChatAction>(
        context: context,
        showDragHandle: true,
        // 시트를 연 뒤 약·시간대 정보가 도착해도 선택지를 바로 갱신한다.
        builder: (sheetContext) => ValueListenableBuilder<int>(
          valueListenable: _chatActionsRevision,
          builder: (context, _, _) => _ChatActionSheet(
            items: _chatActionItems(),
            onSelected: (action) => Navigator.pop(sheetContext, action),
          ),
        ),
      );
    } finally {
      _isChatActionsOpen = false;
    }
    if (!mounted || _history.linkUnavailable || action == null) return;
    switch (action) {
      case _ChatAction.medication:
        await _showMedicationSelector();
      case _ChatAction.medicationHistory:
        await _shareMedicationHistory();
      case _ChatAction.scheduleRequest:
        await _showScheduleSelector();
      case _ChatAction.nearbyHospital:
      case _ChatAction.nearbyPharmacy:
        await _showPharmacySelector(
          medications: List<ChatMedicationContext>.of(
            _selectedMedicationContexts,
          ),
          hospitals: action == _ChatAction.nearbyHospital,
        );
    }
  }

  // 함수이름: _chatActionItems
  // 함수역할: 각 채팅 기능의 사용 불가 이유를 계산하고 연동 종료 시 모든 공유·검색 동작을 막는다.
  // 매개변수: 없음.
  // 반환값: 기능·아이콘·문구·선택 불가 사유를 담은 _ChatActionItem 목록.
  List<_ChatActionItem> _chatActionItems() => [
    (
      action: _ChatAction.medication,
      icon: Icons.medication_outlined,
      label: _text.selectMedication,
      // 등록 약을 조회하지 못해도 별도 약품 검색으로 첨부할 수 있다.
      reason: _history.linkUnavailable ? _text.linkUnavailableStatus : null,
    ),
    (
      action: _ChatAction.medicationHistory,
      icon: Icons.history_rounded,
      label: _text.isEnglish ? 'Share medication history' : '복약 기록 공유',
      reason: _canOpenMedicationHistory
          ? null
          : _history.linkUnavailable
          ? _text.linkUnavailableStatus
          : _text.historyShareUnavailable,
    ),
    if (!_isPatient)
      (
        action: _ChatAction.scheduleRequest,
        icon: Icons.schedule_rounded,
        label: _text.scheduleSelectorTitle,
        reason: _history.linkUnavailable
            ? _text.linkUnavailableStatus
            : switch (_scheduleLoad) {
                _ChatContextLoad.loading => _text.scheduleLoading,
                _ChatContextLoad.failed => _text.scheduleLoadFailed,
                _ChatContextLoad.loaded =>
                  _requestableScheduleContexts.isEmpty
                      ? _text.noRequestableSchedule
                      : null,
              },
      ),
    (
      action: _ChatAction.nearbyHospital,
      icon: Icons.local_hospital_outlined,
      label: _text.findNearbyHospital,
      reason: _history.linkUnavailable ? _text.linkUnavailableStatus : null,
    ),
    (
      action: _ChatAction.nearbyPharmacy,
      icon: Icons.storefront_outlined,
      label: _text.findNearbyPharmacy,
      reason: _history.linkUnavailable ? _text.linkUnavailableStatus : null,
    ),
  ];

  // Function Name: _notifyChatActions
  // Description: Notifies an open action menu that medication or dose-slot availability has changed.
  // Parameters: None.
  // Returns: None.
  void _notifyChatActions() => _chatActionsRevision.value += 1;

  // 함수이름: _showPharmacySelector
  // 함수역할: 장소 선택과 수신자 확인을 거친 뒤 공유하며 각 비동기 단계 뒤 화면·연동 유효성을 재확인한다.
  // 매개변수: medications (List<ChatMedicationContext>): 함께 보낼 약; hospitals (bool): 병원 검색 여부.
  // 반환값: Future<void>; 취소·연동 종료·화면 종료 시 전송하지 않는다.
  Future<void> _showPharmacySelector({
    List<ChatMedicationContext> medications = const [],
    bool hospitals = false,
  }) async {
    if (_isSending || _history.linkUnavailable) {
      return;
    }
    final selection = await Navigator.of(context).push<NearbyCareSelection>(
      MaterialPageRoute(
        // 함수이름: _showPharmacySelector.builder callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
        // 매개변수:
        // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        builder: (_) =>
            _configuration.careSelectorBuilder?.call(hospitals) ??
            CheckNearbyPharmacyUI.selection(
              userSetting: _configuration.userSetting.copyWith(
                userHash: _configuration.currentUserHash,
              ),
              hospitals: hospitals,
            ),
      ),
    );
    if (selection == null || !mounted || _history.linkUnavailable) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(_text.shareCareTitle),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_text.shareRecipient(_peerName)),
            const SizedBox(height: 12),
            Text(
              selection.place.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(selection.place.address),
            if (hospitals && selection.scheduleDate != null)
              Text(_text.careDate(selection.scheduleDate!)),
            if (selection.place.todayOpenTime != null &&
                selection.place.todayCloseTime != null)
              Text(
                '${selection.place.todayOpenTime} - ${selection.place.todayCloseTime}',
              ),
            if (medications.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(medications.map((item) => item.medicationName).join(', ')),
            ],
            if (hospitals) ...[
              const SizedBox(height: 8),
              Text(_text.hospitalHoursNotice),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_text.cancel),
          ),
          FilledButton.icon(
            key: const ValueKey('confirmCareShare'),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.send_outlined),
            label: Text(_text.sendMessage),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _history.linkUnavailable) return;
    await _sendCareSelection(
      selection,
      hospitals: hospitals,
      medications: medications,
    );
  }

  // 함수이름: _sendCareSelection
  // 함수역할: 현재 연동에서 장소를 공유하고 실패 시 장소별 재시도 ID와 첨부를 보존한다. 종료된 화면·연동 또는 진행 중 작업에서는 시작하지 않는다.
  // 매개변수: selection (NearbyCareSelection): 확정 장소; hospitals (bool): 병원 여부; medications (List<ChatMedicationContext>): 첨부 약; requestId (String?): 동일 공유 재시도 ID.
  // 반환값: 전송 처리 완료 Future<void>; 성공하면 약 선택을 비운다.
  Future<void> _sendCareSelection(
    NearbyCareSelection selection, {
    required bool hospitals,
    required List<ChatMedicationContext> medications,
    String? requestId,
  }) async {
    if (!mounted ||
        _history.linkUnavailable ||
        _isSending ||
        _isSelectingMessages ||
        _isDeletingMessages) {
      return;
    }
    final messageKind = hospitals
        ? ChatMessageKind.hospitalShare
        : selection.phoneVerified
        ? ChatMessageKind.pharmacyPhoneVerified
        : ChatMessageKind.pharmacyShare;
    final sent = await _submitMessage(
      requestId: requestId,
      body: hospitals
          ? _text.hospitalShareBody(selection.place.name)
          : selection.phoneVerified
          ? _text.pharmacyPhoneVerifiedBody(selection.place.name)
          : _text.pharmacyShareBody(selection.place.name),
      medications: medications,
      messageKind: messageKind,
      pharmacyId: hospitals ? null : selection.place.placeId,
      hospitalId: hospitals ? selection.place.placeId : null,
      hospitalScheduleDate: hospitals
          ? (selection.scheduleDate ?? DateTime.now())
                .toIso8601String()
                .split('T')
                .first
          : null,
      clearMedicationSelection: true,
    );
    if (sent == null && mounted) {
      setState(
        () => _pendingCareShare = (
          selection: selection,
          hospitals: hospitals,
          medications: List.of(medications),
          clientMessageId: _composer.pendingRequestId!,
        ),
      );
    } else if (mounted) {
      // 함수이름: _showPharmacySelector.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_selectedMedicationContexts = const []`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _selectedMedicationContexts = const []);
    }
  }

  // 함수이름: _showScheduleSelector
  // 함수역할: 요청 가능한 보호자에게만 시간대 선택창을 열고 복약 확인 요청 메시지를 보낸다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showScheduleSelector() async {
    final requestableContexts = _requestableScheduleContexts;
    if (requestableContexts.isEmpty || _isSending) return;
    final selected = await showModalBottomSheet<ChatScheduleContext>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // 함수이름: _showScheduleSelector.builder callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context) =>
          _ScheduleContextSelector(contexts: requestableContexts, text: _text),
    );
    if (selected == null || !mounted) {
      return;
    }
    if (!selected.canRequestCheck) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_text.onlyCaregiverCanRequest)));
      return;
    }
    final sent = await _submitMessage(
      body: _text.slotCheckRequestBody(selected.slotKey),
      messageKind: ChatMessageKind.slotCheckRequest,
      slotKey: selected.slotKey,
    );
    if (sent != null) {
      await _refreshScheduleContexts();
    }
  }

  // 함수이름: _callPharmacy
  // 함수역할: 공유 약국의 전화번호로 전화 앱을 열고 실패를 안내한다.
  // 매개변수:
  // - pharmacy (ChatPharmacyContext): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _callPharmacy(ChatPlaceContext pharmacy) async {
    final succeeded = await _pharmacyActionService.requestPhoneCall(
      pharmacy.telephone,
    );
    if (!succeeded && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_text.phoneUnavailable)));
    }
  }

  // 함수이름: _openPharmacyDirections
  // 함수역할: 공유 약국의 이름·주소·좌표로 길찾기를 요청하고 실패를 안내한다.
  // 매개변수:
  // - pharmacy (ChatPharmacyContext): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _openPharmacyDirections(ChatPlaceContext pharmacy) async {
    final succeeded = await _pharmacyActionService.requestDirections(
      name: pharmacy.name,
      address: pharmacy.address,
      latitude: pharmacy.latitude,
      longitude: pharmacy.longitude,
    );
    if (!succeeded && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_text.directionsUnavailable)));
    }
  }

  // Function Name: _showMedicationSelector
  // Description: Shows the patient's active medications with thumbnails for choosing conversation context.
  // Parameters: None.
  // Returns: Future completing when medication selection closes.
  Future<void> _showMedicationSelector() async {
    if (_isSending || _history.linkUnavailable) {
      return;
    }
    var references = List<ChatMedicationReference>.of(
      _selectedMedicationReferences,
    );
    var searching = false;
    final selectionDate = _doseRecorder.selectionDay(
      context.read<MedBuddyViewModel?>(),
      _scheduleContexts,
    );
    final medicationsById = {
      for (final medication in _medicationContexts)
        medication.medicationId: medication,
    };
    final selectionSchedules = _medicationContexts
        .map(
          // 함수이름: _showMedicationSelector.map callback
          // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 변환값을 `MedicationSchedule(medicationID: medication.medicationId.toString(), medicationName: medication.medicationName, dosage: me...` 규칙으로 계산한다.
          // 매개변수:
          // - medication (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
          // 반환값: 컬렉션 연산에 전달할 변환값.
          (medication) => MedicationSchedule(
            medicationID: medication.medicationId.toString(),
            medicationName: medication.medicationName,
            dosage: medication.dosagePerTime,
            scheduleSlotKeys: medication.scheduleSlotKeys,
            dosingMode: medication.dosingMode,
            imageUrl: medication.imageUrl,
          ),
        )
        .toList(growable: false);
    final selectedSchedules = await Navigator.push<List<MedicationSchedule>>(
      context,
      MaterialPageRoute(
        // 함수이름: _showMedicationSelector.builder callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
        // 매개변수:
        // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        builder: (selectionContext) => StatefulBuilder(
          builder: (context, updateSelection) => CheckScheduleUI.selection(
            schedules: selectionSchedules,
            language: _configuration.userSetting.language,
            additionalSelectionCount: references.length,
            maxSelectionCount: maxChatMedicationAttachments,
            selectionHeader: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    key: const Key('chat-search-medication'),
                    icon: const Icon(Icons.search),
                    label: Text(
                      _text.isEnglish ? 'Search medications' : '약 검색',
                    ),
                    onPressed: searching
                        ? null
                        : () async {
                            updateSelection(() => searching = true);
                            final lookup = CheckMedicationDetail(
                              client: _apiClient,
                              readSearchMode: () => _configuration
                                  .userSetting
                                  .medicationSearchMode,
                            );
                            try {
                              final detail =
                                  await Navigator.push<MedicationDetail>(
                                    selectionContext,
                                    MaterialPageRoute(
                                      builder: (_) => MedicationSearchUI(
                                        userSetting: _configuration.userSetting,
                                        selectionMode: true,
                                        lookupControl: lookup,
                                      ),
                                    ),
                                  );
                              if (!mounted ||
                                  !selectionContext.mounted ||
                                  _history.linkUnavailable ||
                                  detail == null) {
                                return;
                              }
                              final reference =
                                  ChatMedicationReference.fromDetail(detail);
                              updateSelection(() {
                                references = [
                                  ...references.where(
                                    (item) => item.itemSeq != reference.itemSeq,
                                  ),
                                  reference,
                                ];
                              });
                            } on FormatException {
                              if (selectionContext.mounted) {
                                ScaffoldMessenger.of(
                                  selectionContext,
                                ).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _text.isEnglish
                                          ? 'This medication cannot be attached.'
                                          : '이 약의 첨부 정보를 확인하지 못했어요.',
                                    ),
                                  ),
                                );
                              }
                            } finally {
                              lookup.dispose();
                              if (selectionContext.mounted) {
                                updateSelection(() => searching = false);
                              }
                            }
                          },
                  ),
                  for (final reference in references)
                    ChatMedicationReferenceTile(
                      reference: reference,
                      isEnglish: _text.isEnglish,
                      onRemove: () =>
                          updateSelection(() => references.remove(reference)),
                    ),
                ],
              ),
            ),
            selectedMedicationSlots: {
              for (final item in _selectedMedicationContexts)
                item.medicationId.toString(): item.isAsNeeded
                    ? {'as_needed'}
                    : item.scheduleSlotKeys.toSet(),
            },
          ),
        ),
      ),
    );
    if (selectedSchedules == null || !mounted) {
      return;
    }
    final selected = selectedSchedules
        // 함수이름: _showMedicationSelector.map callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 변환값을 `medicationsById[int.tryParse(item.medicationID)]` 규칙으로 계산한다.
        // 매개변수:
        // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
        // 반환값: 컬렉션 연산에 전달할 변환값.
        .map(
          (item) => medicationsById[int.tryParse(item.medicationID)]
              ?.withScheduleSlots(item.scheduleSlotKeys),
        )
        .whereType<ChatMedicationContext>()
        .toList(growable: false);
    // 첨부 개수 한도는 선택 화면이 확인 버튼을 막아 지킨다.
    if (_history.linkUnavailable) return;
    // 함수이름: _showMedicationSelector.setState callback
    // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_selectedMedicationContexts = selected; _sendErrorMessage = null`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _selectedMedicationContexts = selected;
      _selectedMedicationReferences = references;
      _selectedMedicationScheduleDate = selected.isEmpty ? null : selectionDate;
      _sendErrorMessage = null;
      _clearPendingRequest();
    });
  }

  // 함수이름: _suggestedMessage
  // 함수역할: 선택 약 이름을 묶어 환자·보호자 역할에 맞는 추천 메시지를 구성한다.
  // 매개변수:
  // - medications (List<ChatMedicationContext>): 조회·선택·정렬·표시에 사용할 약품 목록.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _suggestedMessage(List<ChatMedicationContext> medications) {
    final medicationNames = medications
        // 함수이름: _suggestedMessage.map callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 변환값을 `item.medicationName` 규칙으로 계산한다.
        // 매개변수:
        // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
        // 반환값: 컬렉션 연산에 전달할 변환값.
        .map((item) => item.medicationName)
        .join(', ');
    if (_isPatient) {
      return _text.patientSuggestedMessage(medicationNames);
    }
    return _text.caregiverSuggestedMessage(_peerName, medicationNames);
  }

  // 함수이름: _canOpenMedicationHistory
  // 함수역할: 연동·계정 범위가 유효하고 조회·삭제·메시지 선택 중이 아닌지 확인한다.
  // 매개변수: 없음.
  // 반환값: 복약 이력 진입을 허용하면 true.
  bool get _canOpenMedicationHistory =>
      !_history.linkUnavailable &&
      !_isLoading &&
      !_isSelectingMessages &&
      !_isDeletingMessages &&
      _configuration.currentUserHash.isNotEmpty &&
      _configuration.patientHash.isNotEmpty;

  // 함수이름: _shareMedicationHistory
  // 함수역할: 현재 대화의 환자와 수신자를 고정한 이력 공유 확인을 열고 실제 공유 완료 후에만 대화를 갱신한다.
  // 매개변수: 없음.
  // 반환값: 공유 화면 종료와 필요한 최신 이력 보충이 끝나면 완료되는 Future<void>.
  Future<void> _shareMedicationHistory() async {
    if (!_canOpenMedicationHistory || _isSending) return;
    var shared = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MedicationHistoryUI(
          patientHash: _configuration.patientHash,
          currentUserHash: _configuration.currentUserHash,
          readOnly: true,
          isEnglish: _text.isEnglish,
          initiallyShowExport: true,
          chatLinkId: _configuration.linkId,
          onChatShared: () => shared = true,
        ),
      ),
    );
    if (!mounted || !shared) return;
    await _refreshMessages(showLoading: false, catchUp: true);
    if (mounted) _scrollToLatest(force: true);
  }

  // Function Name: _openableCard
  // Description: Rechecks the live conversation entry before opening a shared card; stale, hidden or deleted messages cannot be opened.
  // Parameters: message (ChatMessage): previously displayed message.
  // Returns: Current visible ChatMessage or null when the route/link/message is unavailable.
  ChatMessage? _openableCard(ChatMessage message) {
    if (!_isChatVisible || !_canOpenMedicationHistory) return null;
    final current = _messages
        .where((item) => item.messageId == message.messageId)
        .firstOrNull;
    return current == null || current.hiddenForMe || current.deletedForEveryone
        ? null
        : current;
  }

  // Function Name: _openSharedHistory
  // Description: Opens the latest records for a shared date range as read-only patient history.
  // Parameters: range (MedicationHistoryRange): shared dates to query.
  // Returns: Future<void> completed when history closes; the history API verifies current access.
  Future<void> _openSharedHistory(MedicationHistoryRange range) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MedicationHistoryUI(
            patientHash: _configuration.patientHash,
            readOnly: true,
            isEnglish: _configuration.userSetting.isEnglish,
            sharedRange: range,
          ),
        ),
      );

  // Function Name: _openMedicationHistory
  // Description: Resolves the current nondeleted history card before opening its date range.
  // Parameters: message (ChatMessage): tapped card.
  // Returns: Future<void>; missing or unavailable history attachments are ignored.
  Future<void> _openMedicationHistory(ChatMessage message) async {
    final history = _openableCard(message)?.historyContext;
    if (history == null) return;
    await _openSharedHistory(
      MedicationHistoryRange(history.startDate, history.endDate),
    );
  }

  // 함수이름: _openSharedPlace
  // 함수역할: 현재 대화의 살아 있는 장소 카드만 열고 공유 스냅샷은 장소 찾기용으로 전달해 상세를 다시 조회한다.
  // 매개변수: message (ChatMessage): 누른 장소 카드.
  // 반환값: 상세 화면 종료 Future<void>; 삭제·연동 종료·숨겨진 화면이면 무시한다.
  Future<void> _openSharedPlace(ChatMessage message) async {
    if (!mounted ||
        !_isChatVisible ||
        _history.linkUnavailable ||
        _isSelectingMessages ||
        _isDeletingMessages) {
      return;
    }
    final current = _messages
        .where((item) => item.messageId == message.messageId)
        .firstOrNull;
    if (current == null || current.hiddenForMe || current.deletedForEveryone) {
      return;
    }
    final place = current.hospitalContext ?? current.pharmacyContext;
    if (place == null) return;
    final hospital = place is ChatHospitalContext ? place : null;
    // 공유 정보는 장소를 찾는 용도로만 전달하고 상세는 수신 기기에서 다시 조회한다.
    final initialPlace = NearbyCarePlace(
      placeId:
          hospital?.hospitalId ?? (place as ChatPharmacyContext).pharmacyId,
      name: place.name,
      address: place.address,
      telephone: place.telephone,
      latitude: place.latitude,
      longitude: place.longitude,
      distanceKm: 0,
      todayOpenTime: null,
      todayCloseTime: null,
      isOpenNow: null,
      is24Hours: false,
      departments: hospital?.departments ?? const [],
      sourceUpdatedAt: place.sourceUpdatedAt,
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            _configuration.careDetailsBuilder?.call(
              initialPlace,
              hospital != null,
            ) ??
            CheckNearbyPharmacyUI(
              userSetting: _configuration.userSetting,
              hospitals: hospital != null,
              initialPlace: initialPlace,
            ),
      ),
    );
  }

  // Function Name: _openPatientSchedule
  // Description: Revalidates the schedule card and date; a patient today-check request opens the matching schedule slot, otherwise opens read-only history for that day.
  // Parameters: message (ChatMessage): tapped schedule card.
  // Returns: Future<void>; unavailable cards and dates outside retention are ignored.
  Future<void> _openPatientSchedule(ChatMessage message) async {
    final current = _openableCard(message);
    final schedule = current?.scheduleContext;
    final day = schedule == null ? null : _readableScheduleDay(schedule);
    if (current == null || schedule == null || day == null) return;
    if (_isPatient &&
        current.messageKind == ChatMessageKind.slotCheckRequest &&
        day == MedicationHistoryDates.today(DateTime.now())) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CheckScheduleUI(initialSlotKey: schedule.slotKey),
        ),
      );
      return;
    }
    await _openSharedHistory(MedicationHistoryRange(day, day));
  }

  // 함수이름: _openMedicationDetail
  // 함수역할: 채팅이 보이고 연동이 유효할 때 약품 상세를 조회한다. 조회 후에도 같은 조건을 확인해 이동 또는 실패 안내를 제한한다.
  // 매개변수: medication (ChatMedicationContext): 상세를 조회할 첨부 약.
  // 반환값: 조회와 상세 화면 종료 Future<void>; 중복 조회·화면 이탈·연동 종료는 이동하지 않는다.
  Future<void> _openMedicationDetail(ChatMedicationContext medication) async {
    if (!_isChatVisible ||
        _history.linkUnavailable ||
        _loadingMedicationId != null) {
      return;
    }
    // 함수이름: _openMedicationDetail.setState callback
    // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_loadingMedicationId = medication.medicationId; _sendErrorMessage = null`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _loadingMedicationId = medication.medicationId;
      _sendErrorMessage = null;
    });
    try {
      final detail = await _control.requestMedicationDetail(
        linkId: _configuration.linkId,
        medicationId: medication.medicationId,
      );
      if (!mounted) {
        return;
      }
      // 함수이름: _openMedicationDetail.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_loadingMedicationId = null`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _loadingMedicationId = null);
      if (!_isChatVisible || _history.linkUnavailable) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          // 함수이름: _openMedicationDetail.builder callback
          // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
          // 매개변수:
          // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
          // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
          builder: (_) => CheckMedicationDetailUI(
            medicationDetail: detail,
            userSetting: _configuration.userSetting,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      // 함수이름: _openMedicationDetail.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_loadingMedicationId = null`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _loadingMedicationId = null);
      if (!_isChatVisible || _history.linkUnavailable) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_text.medicationDetailLoadFailed)));
    }
  }

  // Function Name: _applyMessageDeletion
  // Description: Applies server-confirmed deletion evidence through the scoped history owner.
  // Parameters: ids: Message identifiers; scope: Authorized deletion scope.
  // Returns: None; selection cleanup is a separate presentation callback.
  void _applyMessageDeletion(List<int> ids, ChatDeletionScope scope) {
    if (mounted) _history.applyDeletion(ids, scope);
  }

  bool _messageActionsOpen = false;

  // 함수이름: _showMessageActions
  // 함수역할: 메시지 복사·선택 메뉴를 한 번 열고 결과 처리 전에 삭제와 연동 상태를 다시 확인한다.
  // 매개변수: id (int): 대상 메시지 ID.
  // 반환값: Future<void>; 선택 모드에서는 선택만 토글하고 복사 오류는 안내한다.
  Future<void> _showMessageActions(int id) async {
    if (_isSending || _isDeletingMessages || _messageActionsOpen) return;
    if (_isSelectingMessages) {
      _toggleMessageSelection(id);
      return;
    }
    final message = _messages.where((item) => item.messageId == id).firstOrNull;
    if (message == null || message.hiddenForMe || _history.linkUnavailable) {
      return;
    }
    _messageActionsOpen = true;
    try {
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!message.deletedForEveryone && message.body.isNotEmpty)
                ListTile(
                  key: const Key('chat-copy-message'),
                  leading: const Icon(Icons.copy_outlined),
                  title: Text(
                    _text.copyMessage,
                    style: MedBuddyTextStyles.menuTitle,
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'copy'),
                ),
              ListTile(
                key: const Key('chat-select-message'),
                leading: const Icon(Icons.checklist_outlined),
                title: Text(
                  _text.selectMessage,
                  style: MedBuddyTextStyles.menuTitle,
                ),
                onTap: () => Navigator.pop(sheetContext, 'select'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || _history.linkUnavailable || _isDeletingMessages) return;
      // 메뉴가 열린 사이에 삭제된 본문을 클립보드로 복사하지 않는다.
      final current = _messages
          .where((item) => item.messageId == id)
          .firstOrNull;
      if (current == null || current.hiddenForMe) return;
      if (action == 'select') {
        _toggleMessageSelection(id);
      } else if (action == 'copy' &&
          !current.deletedForEveryone &&
          current.body.isNotEmpty) {
        try {
          await Clipboard.setData(ClipboardData(text: current.body));
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(_text.messageCopied)));
          }
        } on PlatformException {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(_text.copyFailed)));
          }
        }
      }
    } finally {
      _messageActionsOpen = false;
    }
  }

  // 함수이름: _toggleMessageSelection
  // 함수역할: 전송·삭제 중에는 선택을 막고 메시지 선택을 최대 50개까지 전환한다.
  // 매개변수:
  // - id (int): 선택·삭제 대상으로 사용할 메시지 식별자.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _toggleMessageSelection(int id) {
    if (_isSending || _isDeletingMessages) return;
    // 함수이름: _toggleMessageSelection.setState callback
    // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_isSelectingMessages = true`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _isSelectingMessages = true;
      if (!_selectedMessageIds.remove(id) &&
          _selectedMessageIds.length < ManageLinkedChat.maxDeleteMessageCount) {
        _selectedMessageIds.add(id);
      }
    });
  }

  // Function Name: _confirmMessageDeletion
  // Description: Checks whether selected messages can be deleted for everyone, confirms the personal/shared scope and keeps selection on failure.
  // Parameters: None.
  // Returns: Future completing after confirmation and any deletion request.
  Future<void> _confirmMessageDeletion() async {
    if (_isDeletingMessages || _selectedMessageIds.isEmpty) return;
    final ids = _selectedMessageIds.toList(growable: false);
    final selected = _messages
        // 함수이름: _confirmMessageDeletion.where callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 대해 `ids.contains(message.messageId)` 조건으로 컬렉션 항목을 판별한다.
        // 매개변수:
        // - message (콜백 계약에서 추론): 현재 작업 결과·오류·상태에 대한 표시 문구.
        // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
        .where((message) => ids.contains(message.messageId))
        .toList();
    final canDeleteForEveryone =
        selected.isNotEmpty &&
        selected.every(
          // 함수이름: _confirmMessageDeletion.every callback
          // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 대해 `message.canDeleteForEveryone(_configuration.currentUserHash, DateTime.now())` 조건으로 컬렉션 항목을 판별한다.
          // 매개변수:
          // - message (콜백 계약에서 추론): 현재 작업 결과·오류·상태에 대한 표시 문구.
          // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
          (message) => message.canDeleteForEveryone(
            _configuration.currentUserHash,
            DateTime.now(),
          ),
        );
    var scope = ChatDeletionScope.me;
    final confirmed = await showDialog<bool>(
      context: context,
      // 함수이름: _confirmMessageDeletion.builder callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - dialogContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (dialogContext) => StatefulBuilder(
        // 함수이름: _confirmMessageDeletion.builder callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 ValueKey을 적용해 현재 배치를 구성한다.
        // 매개변수:
        // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
        // - setDialogState (StateSetter): 현재 대화상자의 지역 상태를 갱신하는 함수.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(_text.deleteMessages),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_text.deleteWarning),
              RadioGroup<ChatDeletionScope>(
                groupValue: scope,
                // 함수이름: _confirmMessageDeletion.setDialogState callback
                // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `scope = value!`로 갱신한다.
                // 매개변수:
                // - 없음.
                // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                // 함수이름: _confirmMessageDeletion.onChanged callback
                // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에서 캡처된 작업 `setDialogState(() => scope = value!)`을 실행한다.
                // 매개변수:
                // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onChanged: (value) => setDialogState(() => scope = value!),
                child: Column(
                  children: [
                    RadioListTile<ChatDeletionScope>(
                      contentPadding: EdgeInsets.zero,
                      value: ChatDeletionScope.me,
                      title: Text(_text.deleteForMe),
                    ),
                    if (canDeleteForEveryone)
                      RadioListTile<ChatDeletionScope>(
                        contentPadding: EdgeInsets.zero,
                        value: ChatDeletionScope.everyone,
                        title: Text(_text.deleteForEveryone),
                      ),
                  ],
                ),
              ),
              if (!canDeleteForEveryone) Text(_text.privateDeletionOnly),
            ],
          ),
          actions: [
            TextButton(
              // 함수이름: _confirmMessageDeletion.onPressed callback
              // 함수역할: `Navigator.pop(dialogContext, false)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
              // 매개변수:
              // - 없음.
              // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_text.cancel),
            ),
            TextButton(
              key: const ValueKey('confirmChatDeletion'),
              // 함수이름: _confirmMessageDeletion.onPressed callback
              // 함수역할: `Navigator.pop(dialogContext, true)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
              // 매개변수:
              // - 없음.
              // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_text.deleteMessages),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    // 함수이름: _confirmMessageDeletion.setState callback
    // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_isDeletingMessages = true`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _isDeletingMessages = true);
    try {
      await _control.deleteMessages(
        linkId: _configuration.linkId,
        messageIds: ids,
        scope: scope,
      );
      if (!mounted) return;
      _applyMessageDeletion(ids, scope);
      // 함수이름: _confirmMessageDeletion.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_isSelectingMessages = false`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _selectedMessageIds.clear();
        _isSelectingMessages = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text.deleteFailed), persist: false),
      );
    } finally {
      // 함수이름: _confirmMessageDeletion.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_isDeletingMessages = false`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      if (mounted) setState(() => _isDeletingMessages = false);
    }
  }

  // 함수이름: _scrollToLatest
  // 함수역할: 처음 진입하거나 직접 전송하면 하단으로 이동하고, 수신·조회 갱신에서는 이전 대화를 읽던 위치를 유지한다.
  // 매개변수:
  // - force (bool): 현재 스크롤 위치와 관계없이 최신 메시지로 이동할지 여부.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _scrollToLatest({bool force = true}) {
    if (!force &&
        (!_isChatVisible ||
            (_scrollController.hasClients &&
                _scrollController.position.extentBefore > 80))) {
      return;
    }
    // 함수이름: _scrollToLatest.addPostFrameCallback callback
    // 함수역할: 역방향 목록의 최신 위치로 이동한 뒤 보이는 대화를 읽음 처리한다.
    // 매개변수:
    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      unawaited(
        _scrollController
            .animateTo(
              0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            )
            .then((_) => _markLatestIncomingRead()),
      );
    });
  }

  // Function Name: build
  // Description: Displays linked messages, medication attachments, connection state and composer or selection actions for the current session.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            MedBuddyPageHeader(
              onBackRequested: _isSelectingMessages
                  ? null
                  : () => Navigator.maybePop(context),
              leading: _isSelectingMessages
                  ? IconButton(
                      tooltip: _text.cancel,
                      icon: const Icon(Icons.close),
                      onPressed: _isDeletingMessages
                          ? null
                          // 함수이름: build.setState callback
                          // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_isSelectingMessages = false`로 갱신한다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                          // 함수이름: build.onPressed callback
                          // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에서 캡처된 작업 `setState(() {_isSelectingMessages = false; _selectedMessageIds.clear();})`을 실행한다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                          : () => setState(() {
                              _isSelectingMessages = false;
                              _selectedMessageIds.clear();
                            }),
                    )
                  : null,
              actions: [
                IconButton(
                  key: const ValueKey('deleteChatMessages'),
                  tooltip: _text.deleteMessages,
                  onPressed:
                      _isLoading ||
                          _isSending ||
                          _isDeletingMessages ||
                          (_isSelectingMessages
                              ? _selectedMessageIds.isEmpty
                              : _messages.isEmpty)
                      ? null
                      // 함수이름: build.onPressed callback
                      // 함수역할: 선택 메시지의 전체 삭제 가능 여부를 확인하고 확정한 개인·공유 범위로 삭제하며 실패 시 선택을 유지한다.
                      // 매개변수:
                      // - 없음.
                      // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                      : () {
                          if (_isSelectingMessages) {
                            unawaited(_confirmMessageDeletion());
                          } else {
                            // 함수이름: build.setState callback
                            // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_isSelectingMessages = true`로 갱신한다.
                            // 매개변수:
                            // - 없음.
                            // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                            setState(() => _isSelectingMessages = true);
                          }
                        },
                  icon: _isDeletingMessages
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                ),
              ],
              title: _isSelectingMessages
                  ? _text.selectedCount(_selectedMessageIds.length)
                  : _peerName,
              subtitle: _connectionLabel,
              // 작은 화면·키보드 표시 중에는 이름을 한 줄로 줄여 메시지 영역을 확보한다.
              titleMaxLines:
                  MediaQuery.sizeOf(context).height -
                          MediaQuery.viewInsetsOf(context).bottom <
                      700
                  ? 1
                  : 2,
              subtitleMaxLines: 1,
            ),
            if (_showMedicationContextGuide)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                color: MedBuddyColors.successSurface,
                child: Text(
                  _text.medicationContextGuide,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  children: [
                    Expanded(child: _buildMessageArea()),
                    if (_history.linkUnavailable)
                      _buildLinkUnavailableNotice()
                    else if (!_isSelectingMessages)
                      // Keep messages visible when large text or the keyboard
                      // makes the selected doses and retry message taller.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * 0.7,
                        ),
                        child: SingleChildScrollView(child: _buildComposer()),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 함수이름: _buildMessageArea
  // 함수역할: 채팅 로딩·오류·빈 상태 또는 삭제 선택·첨부 동작이 연결된 메시지 목록을 표시한다.
  // 매개변수:
  // - 없음.
  // 반환값: 연동 사용자 메시지와 복약 관련 첨부에 쓰는 위젯 트리.
  Widget _buildMessageArea() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: MedBuddyColors.primary),
      );
    }
    if (_errorMessage != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.chat_bubble_outline,
                color: MedBuddyColors.textMuted,
                size: 42,
              ),
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MedBuddyColors.textMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                // 함수이름: _buildMessageArea.onPressed callback
                // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에서 캡처된 작업 `_refreshMessages(showLoading: true)`을 실행한다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onPressed: () => _refreshMessages(showLoading: true),
                icon: const Icon(Icons.refresh),
                label: Text(_text.retry),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _text.emptyConversation,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      );
    }
    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        unawaited(_markLatestIncomingRead());
        return false;
      },
      child: ListView.builder(
        key: const Key('chat-message-list'),
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
        itemCount: _messages.length + (_hasOlderMessages ? 1 : 0),
        // 함수이름: _buildMessageArea.itemBuilder callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 EdgeInsets.all을 적용해 현재 배치를 구성한다.
        // 매개변수:
        // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
        // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        itemBuilder: (context, reverseIndex) {
          if (reverseIndex == _messages.length) {
            return Center(
              child: TextButton(
                key: const Key('chat-load-older'),
                onPressed: _loadingOlderMessages ? null : _loadOlderMessages,
                child: Text(
                  _loadingOlderMessages
                      ? (_text.isEnglish ? 'Loading...' : '불러오는 중...')
                      : _olderMessagesFailed
                      ? _text.retry
                      : (_text.isEnglish ? 'Earlier messages' : '이전 대화 보기'),
                ),
              ),
            );
          }
          final index = _messages.length - 1 - reverseIndex;
          final date = _messages[index].createdAt.toLocal();
          final startsDay =
              index == 0 ||
              !DateUtils.isSameDay(
                date,
                _messages[index - 1].createdAt.toLocal(),
              );
          return Column(
            key: ValueKey('chat-message-${_messages[index].messageId}'),
            children: [
              if (startsDay)
                ChatDateDivider(
                  key: ValueKey(
                    'chat-date-${date.year}-${date.month}-${date.day}',
                  ),
                  date: date,
                  isEnglish: _text.isEnglish,
                ),
              if (_messages[index].messageId == _firstUnreadMessageId)
                Padding(
                  key: const Key('chat-unread-divider'),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const SizedBox(width: double.infinity, child: Divider()),
                      FractionallySizedBox(
                        widthFactor: 0.7,
                        child: Center(
                          child: ColoredBox(
                            color: MedBuddyColors.pageBackground,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                _text.isEnglish ? 'Read up to here' : '여기까지 읽음',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: MedBuddyColors.textSubtle,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              GestureDetector(
                // 선택 중에는 말풍선과 그 옆 빈 자리를 눌러도 선택되게 줄 전체가 터치를 받는다.
                behavior: _isSelectingMessages ? HitTestBehavior.opaque : null,
                // 함수이름: _buildMessageArea.onTap callback
                // 함수역할: 메시지 선택 중에 줄을 누르면 그 메시지의 선택을 전환한다. 선택 중이 아니면 누르기를 가로채지 않는다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onTap: _isSelectingMessages
                    ? () => _toggleMessageSelection(_messages[index].messageId)
                    : null,
                // 함수이름: _buildMessageArea.onLongPress callback
                // 함수역할: 전송·삭제 중에는 선택을 막고 메시지 선택을 최대 50개까지 전환한다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onLongPress: () =>
                    _showMessageActions(_messages[index].messageId),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isSelectingMessages)
                      Checkbox(
                        key: ValueKey(
                          'selectChatMessage-${_messages[index].messageId}',
                        ),
                        semanticLabel: _text.selectMessage,
                        value: _selectedMessageIds.contains(
                          _messages[index].messageId,
                        ),
                        onChanged: _isDeletingMessages
                            ? null
                            // 함수이름: _buildMessageArea.onChanged callback
                            // 함수역할: 전송·삭제 중에는 선택을 막고 메시지 선택을 최대 50개까지 전환한다.
                            // 매개변수:
                            // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                            : (_) => _toggleMessageSelection(
                                _messages[index].messageId,
                              ),
                      ),
                    Expanded(
                      child: IgnorePointer(
                        ignoring: _isSelectingMessages,
                        child: _MessageBubble(
                          message: _messages[index],
                          isMine:
                              _messages[index].senderHash ==
                              _configuration.currentUserHash,
                          text: _text,
                          userSetting: _configuration.userSetting,
                          loadingMedicationId: _loadingMedicationId,
                          onMedicationPressed: _openMedicationDetail,
                          onHistoryPressed: _canOpenMedicationHistory
                              ? _openMedicationHistory
                              : null,
                          onSchedulePressed: _canOpenMedicationHistory
                              ? _openPatientSchedule
                              : null,
                          onPharmacyCallRequested: _callPharmacy,
                          onPharmacyDirectionsRequested:
                              _openPharmacyDirections,
                          onPlaceDetailsRequested: _openSharedPlace,
                          // 함수이름: _buildMessageArea.onFindPharmacyRequested callback
                          // 함수역할: 약국 선택 결과를 전화 확인 여부에 맞는 메시지 종류로 공유한다.
                          // 매개변수:
                          // - medication (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
                          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                          onFindPharmacyRequested: (medications) {
                            unawaited(
                              _showPharmacySelector(medications: medications),
                            );
                          },
                          onFindHospitalRequested: (medications) => unawaited(
                            _showPharmacySelector(
                              medications: medications,
                              hospitals: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Function Name: _buildLinkUnavailableNotice
  // Description: Replaces the composer when the link ended or access was lost, explaining why retrying cannot send messages.
  // Parameters: None.
  // Returns: The link-unavailable notice.
  Widget _buildLinkUnavailableNotice() {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.link_off, color: MedBuddyColors.danger),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _text.linkUnavailable,
                  key: const Key('chat-link-unavailable'),
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 함수이름: _buildComposer
  // 함수역할: 선택 약품·빠른 답장·전송 오류·500자 입력과 전송 버튼을 배치한다.
  // 매개변수:
  // - 없음.
  // 반환값: 연동 사용자 메시지와 복약 관련 첨부에 쓰는 위젯 트리.
  Widget _buildComposer() {
    final textScaler = MediaQuery.textScalerOf(context);
    // Reserve one name line and two slot/dose lines, including accessibility scaling.
    final selectedMedicationCardHeight = max(
      66.0,
      textScaler.scale(14) * 1.4 + textScaler.scale(12) * 1.4 * 2 + 24,
    );
    return Material(
      color: Colors.white,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (context.read<MedBuddyViewModel?>()?.doseSync case final sync?)
              DoseSyncStatus(service: sync, isEnglish: _text.isEnglish),
            if (_selectedMedicationContexts.isNotEmpty) ...[
              SizedBox(
                height: selectedMedicationCardHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedMedicationContexts.length,
                  // 함수이름: _buildComposer.separatorBuilder callback
                  // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 인접 항목 사이에 지정한 간격 또는 구분선을 배치한다.
                  // 매개변수:
                  // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                  // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                  // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  // 함수이름: _buildComposer.itemBuilder callback
                  // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
                  // 매개변수:
                  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
                  // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
                  // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                  itemBuilder: (context, index) {
                    final medication = _selectedMedicationContexts[index];
                    return SizedBox(
                      width: min(MediaQuery.sizeOf(context).width - 40, 340),
                      child: _SelectedMedicationContext(
                        medication: medication,
                        text: _text,
                        isLoading:
                            _loadingMedicationId == medication.medicationId,
                        onOpenRequested: _loadingMedicationId == null
                            // 함수이름: _buildComposer.onOpenRequested callback
                            // 함수역할: 중복 조회를 막고 연동 범위의 약 상세를 조회한 뒤 상세 화면을 열거나 오류를 안내한다.
                            // 매개변수:
                            // - 없음.
                            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                            ? () => _openMedicationDetail(medication)
                            : null,
                        onRemoveRequested: _isSending
                            ? null
                            // 함수이름: _buildComposer.setState callback
                            // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_selectedMedicationContexts = _selectedMedicationContexts.where((item) => item.medicationId != me...`로 갱신한다.
                            // 매개변수:
                            // - 없음.
                            // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                            // 함수이름: _buildComposer.onRemoveRequested callback
                            // 함수역할: 재전송에 사용하던 메시지 ID·본문·첨부·종류·시간대·약국 정보를 초기화한다.
                            // 매개변수:
                            // - 없음.
                            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                            : () => setState(() {
                                _selectedMedicationContexts =
                                    _selectedMedicationContexts
                                        .where(
                                          // 함수이름: _buildComposer.where callback
                                          // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 대해 `item.medicationId != medication.medicationId` 조건으로 컬렉션 항목을 판별한다.
                                          // 매개변수:
                                          // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
                                          // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
                                          (item) =>
                                              item.medicationId !=
                                              medication.medicationId,
                                        )
                                        .toList(growable: false);
                                _clearPendingRequest();
                              }),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (_selectedMedicationReferences.isEmpty)
                _QuickReplyBar(
                  text: _text,
                  isPatient: _isPatient,
                  enabled: !_isSending,
                  onSelected: _sendQuickReply,
                ),
              const SizedBox(height: 8),
            ],
            if (_selectedMedicationReferences.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final reference in _selectedMedicationReferences)
                        ChatMedicationReferenceTile(
                          reference: reference,
                          isEnglish: _text.isEnglish,
                          onRemove: _isSending
                              ? null
                              : () => setState(() {
                                  _selectedMedicationReferences =
                                      _selectedMedicationReferences
                                          .where(
                                            (item) =>
                                                item.itemSeq !=
                                                reference.itemSeq,
                                          )
                                          .toList();
                                  _clearPendingRequest();
                                }),
                        ),
                    ],
                  ),
                ),
              ),
            if (_sendErrorMessage != null) ...[
              if (_pendingCareShare != null)
                TextButton.icon(
                  key: const ValueKey('retryCareShare'),
                  onPressed: _isSending
                      ? null
                      : () {
                          final pending = _pendingCareShare!;
                          unawaited(
                            _sendCareSelection(
                              pending.selection,
                              hospitals: pending.hospitals,
                              medications: pending.medications,
                              requestId: pending.clientMessageId,
                            ),
                          );
                        },
                  icon: const Icon(Icons.refresh),
                  label: Text(_text.retry),
                ),
              Semantics(
                liveRegion: true,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _sendErrorMessage!,
                      style: const TextStyle(
                        color: MedBuddyColors.danger,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            // 입력 중에는 이 행만 갱신해 메시지 목록과 읽음 위치를 유지한다.
            StatefulBuilder(
              builder: (context, setState) => Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton.outlined(
                    key: const ValueKey('chatActions'),
                    tooltip: _text.isEnglish ? 'More actions' : '기능 더보기',
                    onPressed: _isLoading || _isSending
                        ? null
                        : _showChatActions,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    icon: const Icon(Icons.add),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: !_isSending,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        letterSpacing: 0,
                      ),
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 500,
                      textInputAction: TextInputAction.newline,
                      // 함수이름: _buildComposer.setState callback
                      // 함수역할: 캡처된 값을 변경하지 않는다. 호출자가 화면 갱신을 요청하거나 해당 상호작용을 비활성화한다.
                      // 매개변수:
                      // - 없음.
                      // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                      // 함수이름: _buildComposer.onChanged callback
                      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에서 캡처된 작업 `setState(() {})`을 실행한다.
                      // 매개변수:
                      // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                      // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: _selectedMedicationContexts.isEmpty
                            ? null
                            : _text.exampleMessage(
                                _suggestedMessage(_selectedMedicationContexts),
                              ),
                        counterText: '',
                        filled: true,
                        fillColor: MedBuddyColors.surfaceSubtle,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: MedBuddyRadii.largeCard,
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const ValueKey('chatSendButton'),
                    tooltip: _text.sendMessage,
                    onPressed:
                        !_isSending && _messageController.text.trim().isNotEmpty
                        ? _sendMessage
                        : null,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    icon: _isSending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Function Name: _connectionLabel
  // Description: Localizes live, connecting, reconnecting or disconnected transport state, prioritizing ended-link status.
  // Parameters: None.
  // Returns: The current connection/link label.
  String get _connectionLabel {
    if (_history.linkUnavailable) return _text.linkUnavailableStatus;
    return switch (_connectionState) {
      LinkedChatConnectionState.connected => _text.connected,
      LinkedChatConnectionState.connecting => _text.connecting,
      LinkedChatConnectionState.reconnecting => _text.reconnecting,
      LinkedChatConnectionState.disconnected => _text.disconnected,
    };
  }
}

// 클래스명: _ChatQuickReply
// 역할: 복약 관련 빠른 답장 종류.
// 주요 책임: 복용 완료·지금 어려움·약 부족·불편감의 메시지 흐름을 구별한다.
// 속성: taken/cannotNow/shortage/discomfort: 답장 유형.
enum _ChatQuickReply { taken, cannotNow, shortage, discomfort }

// 클래스명: _ChatAction
// 역할: 채팅 기능 메뉴의 동작 종류.
// 주요 책임: 약 첨부·일정 확인 요청·병원·약국·기록 공유를 구분하며 열거 순서를 화면 키에 사용한다.
// 속성: medication/scheduleRequest/nearbyHospital/nearbyPharmacy/medicationHistory: 기능 값.
enum _ChatAction {
  medication,
  scheduleRequest,
  nearbyHospital,
  nearbyPharmacy,
  medicationHistory,
}

// Class Name: _ChatContextLoad
// Role: Load state for medication or schedule context attached to chat.
// Responsibilities: Distinguishes in-flight, successful and failed context retrieval for action availability.
// Attributes: loading/loaded/failed: context states.
enum _ChatContextLoad { loading, loaded, failed }

typedef _ChatActionItem = ({
  _ChatAction action,
  IconData icon,
  String label,
  String? reason,
});

// Class Name: _ChatActionSheet
// Role: Vertical chat-action chooser.
// Responsibilities: Keeps labels readable at large text scales and explains disabled actions beneath their labels.
// Attributes: items (List<_ChatActionItem>): ordered choices; onSelected: chosen chat command.
class _ChatActionSheet extends StatelessWidget {
  final List<_ChatActionItem> items;
  final ValueChanged<_ChatAction> onSelected;

  // Function Name: _ChatActionSheet
  // Description: Stores ordered chat actions and their selection callback.
  // Parameters: items (List<_ChatActionItem>): choices; onSelected (ValueChanged<_ChatAction>): chosen command.
  // Returns: A _ChatActionSheet.
  const _ChatActionSheet({required this.items, required this.onSelected});

  // Function Name: build
  // Description: Places each chat action on its own row with its icon, label and any disabled reason.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items)
            ListTile(
              key: ValueKey('chat-action-${item.action.index}'),
              enabled: item.reason == null,
              // 색과 글씨를 ListTile에 맡겨 막힌 선택지가 흐리게 보이게 한다.
              iconColor: MedBuddyColors.primary,
              titleTextStyle: MedBuddyTextStyles.menuTitle,
              leading: Icon(item.icon),
              title: KeepWordsText(item.label),
              subtitle: item.reason == null
                  ? null
                  : KeepWordsText(item.reason!),
              onTap: () => onSelected(item.action),
            ),
        ],
      ),
    ),
  );
}

// 클래스명: _QuickReplyBar
// 역할: 복약 확인·복용 완료 등 빠른 답장 선택지를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 복약 확인·복용 완료 등 빠른 답장 선택지 위젯을 구성한다.
// 속성:
// - isPatient (bool): 현재 사용자가 연동 환자 역할인지 여부.
// - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
// - onSelected (ValueChanged<_ChatQuickReply>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
class _QuickReplyBar extends StatelessWidget {
  final _LinkedChatText text;
  final bool isPatient;
  final bool enabled;
  final ValueChanged<_ChatQuickReply> onSelected;

  // 함수이름: _QuickReplyBar
  // 함수역할: 복약 확인·복용 완료 등 빠른 답장 선택지에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - isPatient (bool): 현재 사용자가 연동 환자 역할인지 여부.
  // - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
  // - onSelected (ValueChanged<_ChatQuickReply>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // 반환값: 입력 설정이 반영된 _QuickReplyBar 인스턴스.
  const _QuickReplyBar({
    required this.text,
    required this.isPatient,
    required this.enabled,
    required this.onSelected,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 복약 확인·복용 완료 등 빠른 답장 선택지 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 복약 확인·복용 완료 등 빠른 답장 선택지에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _ChatQuickReply.values.length,
        // 함수이름: build.separatorBuilder callback
        // 함수역할: 복약 확인·복용 완료 등 빠른 답장 선택지의 인접 항목 사이에 지정한 간격 또는 구분선을 배치한다.
        // 매개변수:
        // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
        // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        // 함수이름: build.itemBuilder callback
        // 함수역할: 복약 확인·복용 완료 등 빠른 답장 선택지에 EdgeInsets.symmetric을 적용해 현재 배치를 구성한다.
        // 매개변수:
        // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
        // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        itemBuilder: (context, index) {
          final reply = _ChatQuickReply.values[index];
          return ActionChip(
            tooltip: text.quickReplyLabel(reply, isPatient: isPatient),
            avatar: Icon(text.quickReplyIcon(reply), size: 17),
            label: Text(text.quickReplyLabel(reply, isPatient: isPatient)),
            // 함수이름: build.onPressed callback
            // 함수역할: 복약 확인·복용 완료 등 빠른 답장 선택지에서 캡처된 작업 `onSelected(reply)`을 실행한다.
            // 매개변수:
            // - 없음.
            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
            onPressed: enabled ? () => onSelected(reply) : null,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}

// 클래스명: _ScheduleContextSelector
// 역할: 채팅에 연결할 복약 일정 요약 선택을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 채팅에 연결할 복약 일정 요약 선택 위젯을 구성한다.
// 속성:
// - contexts (List<ChatScheduleContext>): 채팅에 첨부하거나 선택할 초기 복약 맥락 목록.
// 역할: 여러 시간대 중 기록할 항목을 누르면 별도 확인 없이 선택을 반환한다.

// Class Name: _ScheduleContextSelector
// Role: Dose-slot context chooser for chat.
// Responsibilities: Returns the tapped schedule context directly without a second confirmation.
// Attributes: contexts (List<ChatScheduleContext>): selectable slot summaries; text: localized copy.
class _ScheduleContextSelector extends StatelessWidget {
  final List<ChatScheduleContext> contexts;
  final _LinkedChatText text;

  // 함수이름: _ScheduleContextSelector
  // 함수역할: 채팅에 연결할 복약 일정 요약 선택에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - contexts (List<ChatScheduleContext>): 채팅에 첨부하거나 선택할 초기 복약 맥락 목록.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _ScheduleContextSelector 인스턴스.
  const _ScheduleContextSelector({required this.contexts, required this.text});

  // Function Name: build
  // Description: Displays dose-slot summaries and returns the tapped context to the caller.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text.scheduleSelectorTitle,
                style: const TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text.scheduleSelectorCaregiverDescription,
                style: const TextStyle(
                  color: MedBuddyColors.textMuted,
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: contexts.length,
                  // 함수이름: build.separatorBuilder callback
                  // 함수역할: 채팅에 연결할 복약 일정 요약 선택의 인접 항목 사이에 지정한 간격 또는 구분선을 배치한다.
                  // 매개변수:
                  // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                  // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                  // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  // 함수이름: build.itemBuilder callback
                  // 함수역할: 채팅에 연결할 복약 일정 요약 선택에 EdgeInsets.all, Icon을 적용해 현재 배치를 구성한다.
                  // 매개변수:
                  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
                  // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
                  // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                  itemBuilder: (context, index) {
                    final schedule = contexts[index];
                    return InkWell(
                      borderRadius: MedBuddyRadii.small,
                      // 함수이름: build.onTap callback
                      // 함수역할: `Navigator.pop(context, schedule)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                      // 매개변수:
                      // - 없음.
                      // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                      onTap: () => Navigator.pop(context, schedule),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: MedBuddyColors.surfaceSubtle,
                          borderRadius: MedBuddyRadii.small,
                          border: Border.all(color: MedBuddyColors.outline),
                        ),
                        child: _ScheduleSummaryContent(
                          schedule: schedule,
                          text: text,
                          foreground: MedBuddyColors.textStrong,
                          trailing: const Icon(Icons.chevron_right_rounded),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 클래스명: _MessageScheduleContext
// 역할: 메시지에 첨부된 일정 요약을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 메시지에 첨부된 일정 요약 위젯을 구성한다.
// 속성:
// - schedule (ChatScheduleContext): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _MessageScheduleContext extends StatelessWidget {
  final ChatScheduleContext schedule;
  final _LinkedChatText text;
  final VoidCallback? onPressed;

  // 함수이름: _MessageScheduleContext
  // 함수역할: 메시지에 첨부된 일정 요약에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - schedule (ChatScheduleContext): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _MessageScheduleContext 인스턴스.
  const _MessageScheduleContext({
    required this.schedule,
    required this.text,
    this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 메시지에 첨부된 일정 요약 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 메시지에 첨부된 일정 요약에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    const foreground = MedBuddyColors.textStrong;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: MedBuddyRadii.control,
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: MedBuddyColors.chatContentSurface,
            border: Border.all(color: MedBuddyColors.chatContentBorder),
            borderRadius: MedBuddyRadii.control,
          ),
          child: _ScheduleSummaryContent(
            schedule: schedule,
            text: text,
            foreground: foreground,
            trailing: onPressed == null
                ? null
                : Icon(Icons.arrow_right_rounded, color: foreground),
          ),
        ),
      ),
    );
  }
}

// Class Name: _ScheduleSummaryContent
// Role: Dose-slot medication-count and completion summary.
// Responsibilities: Combines slot identity, medication count and completion state with optional trailing content.
// Attributes: schedule (ChatScheduleContext): summary; foreground (Color): content color; trailing (Widget?): optional end content; text: labels.
class _ScheduleSummaryContent extends StatelessWidget {
  final ChatScheduleContext schedule;
  final _LinkedChatText text;
  final Color foreground;
  final Widget? trailing;

  // 함수이름: _ScheduleSummaryContent
  // 함수역할: 약품 수·완료 상태와 시간대별 복약 요약에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - schedule (ChatScheduleContext): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - foreground (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
  // - trailing (Widget?): 행 끝에 배치할 보조 콘텐츠.
  // 반환값: 입력 설정이 반영된 _ScheduleSummaryContent 인스턴스.
  const _ScheduleSummaryContent({
    required this.schedule,
    required this.text,
    required this.foreground,
    this.trailing,
  });

  // Function Name: build
  // Description: Shows the dose-slot summary, medication count and completion state with optional trailing content.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    final total = schedule.totalCount;
    final progress = total <= 0
        ? 0.0
        : (schedule.completedCount / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(text.slotIcon(schedule.slotKey), color: foreground, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${text.slotLabel(schedule.slotKey)} ${schedule.alarmTime}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            Text(
              '${schedule.completedCount}/$total',
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            color: foreground,
            backgroundColor: foreground.withValues(alpha: 0.2),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          schedule.medications
              // 함수이름: build.map callback
              // 함수역할: 약품 수·완료 상태와 시간대별 복약 요약의 변환값을 `item.medicationName` 규칙으로 계산한다.
              // 매개변수:
              // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
              // 반환값: 컬렉션 연산에 전달할 변환값.
              .map((item) => item.medicationName)
              .take(3)
              .join(', '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foreground.withValues(alpha: 0.86),
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

// 클래스명: _MedicationShortageContext
// 역할: 약 부족 알림과 약국 찾기 동작을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약 부족 알림과 약국 찾기 동작 위젯을 구성한다.
// 속성:
// - message (ChatMessage): 본문·발신자·시각·읽음 상태·첨부를 담은 메시지.
// - onFindPharmacyRequested (VoidCallback): 주변 약국 검색을 여는 콜백.
class _MedicationShortageContext extends StatelessWidget {
  final ChatMessage message;
  final _LinkedChatText text;
  final VoidCallback onFindPharmacyRequested;
  final VoidCallback onFindHospitalRequested;

  // 함수이름: _MedicationShortageContext
  // 함수역할: 약 부족 알림과 병원·약국 찾기 동작에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - message (ChatMessage): 본문·발신자·시각·읽음 상태·첨부를 담은 메시지.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - onFindPharmacyRequested (VoidCallback): 주변 약국 검색을 여는 콜백.
  // - onFindHospitalRequested (VoidCallback): 부족한 약의 첨부 맥락을 유지하며 주변 병원 선택을 여는 콜백.
  // 반환값: 입력 설정이 반영된 _MedicationShortageContext 인스턴스.
  const _MedicationShortageContext({
    required this.message,
    required this.text,
    required this.onFindPharmacyRequested,
    required this.onFindHospitalRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약 부족 알림과 약국 찾기 동작 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약 부족 알림과 약국 찾기 동작에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    const foreground = MedBuddyColors.textStrong;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.remainingCourse(message.remainingDays, message.courseEndDate),
          style: TextStyle(
            color: foreground,
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onFindHospitalRequested,
              icon: const Icon(Icons.local_hospital_outlined, size: 18),
              label: Text(text.findNearbyHospital),
              style: OutlinedButton.styleFrom(
                foregroundColor: foreground,
                side: BorderSide(color: foreground.withValues(alpha: 0.72)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onFindPharmacyRequested,
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: Text(text.findNearbyPharmacy),
              style: OutlinedButton.styleFrom(
                foregroundColor: foreground,
                side: BorderSide(color: foreground.withValues(alpha: 0.72)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Class Name: _MedicationSafetyGuidance
// Role: Medication conversation safety guidance.
// Responsibilities: Displays the localized safety reminder alongside medication-related chat content.
// Attributes: text (_LinkedChatText): safety guidance copy.
class _MedicationSafetyGuidance extends StatelessWidget {
  final _LinkedChatText text;

  // Function Name: _MedicationSafetyGuidance
  // Description: Supplies the safety reminder's localized copy.
  // Parameters: text (_LinkedChatText): chat safety labels.
  // Returns: A _MedicationSafetyGuidance.
  const _MedicationSafetyGuidance({required this.text});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 복약 대화의 안전 안내 문구 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 복약 대화의 안전 안내 문구에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    const foreground = MedBuddyColors.reminderAccent;
    return Container(
      key: const ValueKey('chatDiscomfortSafetyGuidance'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MedBuddyColors.warningSurface,
        borderRadius: MedBuddyRadii.small,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.health_and_safety_outlined, color: foreground, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.discomfortSafetyGuidance,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _MessagePharmacyContext
// 역할: 메시지에 공유된 약국과 전화 확인 상태를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 메시지에 공유된 약국과 전화 확인 상태 위젯을 구성한다.
// 속성:
// - pharmacy (ChatPharmacyContext): 표시하거나 전화·길찾기·공유할 약국.
// - phoneVerified (bool): 사용자가 전화로 운영 여부를 확인했는지 여부.
// - onCallRequested (VoidCallback): 해당 약국으로 전화 연결을 요청할 콜백.
class _MessagePharmacyContext extends StatelessWidget {
  final ChatPlaceContext pharmacy;
  final bool phoneVerified;
  final _LinkedChatText text;
  final VoidCallback onCallRequested;
  final VoidCallback onDirectionsRequested;
  final VoidCallback onDetailsRequested;

  // 함수이름: _MessagePharmacyContext
  // 함수역할: 메시지에 공유된 병원·약국과 전화 확인 상태에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - pharmacy (ChatPlaceContext): 전화·길찾기·상세 조회에 사용할 공유 병원 또는 약국.
  // - phoneVerified (bool): 사용자가 전화로 운영 여부를 확인했는지 여부.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - onCallRequested (VoidCallback): 공유 병원·약국으로 전화 연결을 요청할 콜백.
  // - onDirectionsRequested (VoidCallback): 공유 병원·약국의 길찾기를 요청할 콜백.
  // - onDetailsRequested (VoidCallback): 공유 장소의 최신 상세 정보를 다시 조회할 화면을 여는 콜백.
  // 반환값: 입력 설정이 반영된 _MessagePharmacyContext 인스턴스.
  const _MessagePharmacyContext({
    required this.pharmacy,
    required this.phoneVerified,
    required this.text,
    required this.onCallRequested,
    required this.onDirectionsRequested,
    required this.onDetailsRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 메시지에 공유된 약국과 전화 확인 상태 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 메시지에 공유된 약국과 전화 확인 상태에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    const foreground = MedBuddyColors.textStrong;
    final hospital = pharmacy is ChatHospitalContext
        ? pharmacy as ChatHospitalContext
        : null;
    final operatingStatus = text.placeOperatingStatus(pharmacy);
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: const Key('chat-place-summary-panel'),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: MedBuddyColors.chatContentSurface,
              borderRadius: MedBuddyRadii.small,
              border: Border.all(color: MedBuddyColors.chatContentBorder),
            ),
            child: Column(
              children: [
                OutlinedButton(
                  key: const Key('chat-place-details'),
                  onPressed: onDetailsRequested,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: foreground,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hospital == null
                            ? Icons.storefront_outlined
                            : Icons.local_hospital_outlined,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pharmacy.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, size: 22),
                    ],
                  ),
                ),
                ChatPlaceMapPreview(
                  key: ValueKey(
                    'chat-place-preview-${pharmacy.latitude}-${pharmacy.longitude}',
                  ),
                  latitude: pharmacy.latitude,
                  longitude: pharmacy.longitude,
                  isEnglish: text.isEnglish,
                  onOpen: onDetailsRequested,
                ),
              ],
            ),
          ),
          // 진료과·진료일·운영 시간·주소는 어르신이 그대로 읽고 찾아가는 정보이므로 메시지 본문과 같은 크기로 둔다.
          ...[
            const SizedBox(height: 5),
            Text(
              operatingStatus,
              semanticsLabel: '${text.sharedStatus}: $operatingStatus',
              style: TextStyle(
                color: foreground.withValues(alpha: 0.84),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
          if (pharmacy.address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              pharmacy.address,
              style: TextStyle(
                color: foreground.withValues(alpha: 0.78),
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
          if (phoneVerified) ...[
            const SizedBox(height: 6),
            Text(
              text.phoneVerified,
              style: TextStyle(
                color: foreground,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: pharmacy.telephone.isEmpty
                      ? null
                      : onCallRequested,
                  icon: const Icon(Icons.call_outlined, size: 17),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(text.call, maxLines: 1),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: foreground,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    side: BorderSide(color: foreground.withValues(alpha: 0.72)),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDirectionsRequested,
                  icon: const Icon(Icons.directions_outlined, size: 17),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(text.directions, maxLines: 1),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: foreground,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    side: BorderSide(color: foreground.withValues(alpha: 0.72)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// 클래스명: _SelectedMedicationContext
// 역할: 전송 전에 선택한 약 목록과 첨부 해제를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 전송 전에 선택한 약 목록과 첨부 해제 위젯을 구성한다.
// 속성:
// - medication (ChatMedicationContext): 표시·변환·저장·비교할 약품 데이터.
// - isLoading (bool): 진행 중 표시를 보여줄지 여부.
// - onOpenRequested (VoidCallback?): 대상 설정·상세 화면을 여는 콜백.
// - onRemoveRequested (VoidCallback?): 사진 또는 첨부 선택을 제거할 콜백.
class _SelectedMedicationContext extends StatelessWidget {
  final ChatMedicationContext medication;
  final _LinkedChatText text;
  final bool isLoading;
  final VoidCallback? onOpenRequested;
  final VoidCallback? onRemoveRequested;

  // 함수이름: _SelectedMedicationContext
  // 함수역할: 전송 전에 선택한 약 목록과 첨부 해제에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medication (ChatMedicationContext): 표시·변환·저장·비교할 약품 데이터.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - isLoading (bool): 진행 중 표시를 보여줄지 여부.
  // - onOpenRequested (VoidCallback?): 대상 설정·상세 화면을 여는 콜백.
  // - onRemoveRequested (VoidCallback?): 사진 또는 첨부 선택을 제거할 콜백.
  // 반환값: 입력 설정이 반영된 _SelectedMedicationContext 인스턴스.
  const _SelectedMedicationContext({
    required this.medication,
    required this.text,
    required this.isLoading,
    required this.onOpenRequested,
    required this.onRemoveRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 전송 전에 선택한 약 목록과 첨부 해제 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 전송 전에 선택한 약 목록과 첨부 해제에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: MedBuddyColors.chatContentSurface,
        borderRadius: MedBuddyRadii.control,
        border: Border.all(color: MedBuddyColors.chatContentBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: MedBuddyRadii.control,
              onTap: onOpenRequested,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    _MedicationThumbnail(
                      imageUrl: medication.imageUrl,
                      size: 42,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medication.medicationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MedBuddyColors.textStrong,
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                          if (medication.isAsNeeded ||
                              medication.dosagePerTime.isNotEmpty ||
                              medication.scheduleSlotKeys.isNotEmpty)
                            Text(
                              [
                                if (medication.isAsNeeded)
                                  text.isEnglish ? 'As needed' : '필요시 복용',
                                if (medication.scheduleSlotKeys.isNotEmpty)
                                  medication.scheduleSlotKeys
                                      .map(text.slotLabel)
                                      .join('·'),
                                if (medication.dosagePerTime.isNotEmpty)
                                  text.dose(medication.dosagePerTime),
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MedBuddyColors.textMuted,
                                fontSize: 12,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (isLoading)
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: MedBuddyColors.textMuted,
                      ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: text.clearSelectedMedication,
            onPressed: onRemoveRequested,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _MessageMedicationContext
// 역할: 메시지에 첨부된 약품 상세 진입을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 메시지에 첨부된 약품 상세 진입 위젯을 구성한다.
// 속성:
// - medication (ChatMedicationContext): 표시·변환·저장·비교할 약품 데이터.
// - isLoading (bool): 진행 중 표시를 보여줄지 여부.
// - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _MessageMedicationContext extends StatelessWidget {
  final ChatMedicationContext medication;
  final bool isLoading;
  final _LinkedChatText text;
  final VoidCallback? onPressed;

  // 함수이름: _MessageMedicationContext
  // 함수역할: 메시지에 첨부된 약품 상세 진입에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medication (ChatMedicationContext): 표시·변환·저장·비교할 약품 데이터.
  // - isLoading (bool): 진행 중 표시를 보여줄지 여부.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _MessageMedicationContext 인스턴스.
  const _MessageMedicationContext({
    required this.medication,
    required this.isLoading,
    required this.text,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 메시지에 첨부된 약품 상세 진입 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 메시지에 첨부된 약품 상세 진입에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    const foreground = MedBuddyColors.textStrong;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: MedBuddyRadii.control,
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: MedBuddyColors.chatContentSurface,
            border: Border.all(color: MedBuddyColors.chatContentBorder),
            borderRadius: MedBuddyRadii.control,
          ),
          child: Row(
            children: [
              _MedicationThumbnail(imageUrl: medication.imageUrl, size: 46),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medication.medicationName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    if (medication.dosagePerTime.isNotEmpty)
                      Text(
                        text.dose(medication.dosagePerTime),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground.withValues(alpha: 0.78),
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (isLoading)
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else
                Icon(Icons.chevron_right_rounded, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

// Class Name: _MedicationThumbnail
// Role: Medication thumbnail with unavailable-image fallback.
// Responsibilities: Validates the image URL and replaces missing or failed images without disrupting the row.
// Attributes: imageUrl (String): remote photo; size (double): thumbnail dimensions.
class _MedicationThumbnail extends StatelessWidget {
  final String imageUrl;
  final double size;

  // 함수이름: _MedicationThumbnail
  // 함수역할: 약품 사진과 사진 부재·불러오기 실패 대체 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - imageUrl (String): 검증 후 사용할 약품 이미지 네트워크 URL.
  // - size (double): 위젯 또는 캔버스의 표시 크기.
  // 반환값: 입력 설정이 반영된 _MedicationThumbnail 인스턴스.
  const _MedicationThumbnail({required this.imageUrl, required this.size});

  // Function Name: build
  // Description: Displays a validated medication image at the requested size, falling back for an absent URL or load failure.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: MedBuddyRadii.control,
      ),
      child: Icon(
        Icons.medication_outlined,
        color: MedBuddyColors.textMuted,
        size: size * 0.52,
      ),
    );
    // 다른 약 사진 화면과 같이 허용된 HTTPS 출처의 주소만 불러온다.
    final safeImageUrl = safeMedicationImageUrl(imageUrl);
    if (safeImageUrl.isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: MedBuddyRadii.control,
      child: Image.network(
        safeImageUrl,
        width: size,
        height: size,
        fit: BoxFit.contain,
        // 원본 해상도 대신 표시 크기에 맞춰 디코딩해 목록의 이미지 메모리를 줄인다.
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        // 함수이름: build.errorBuilder callback
        // 함수역할: 이미지를 해석하거나 불러올 수 없으면 사진 없음 대체 표시를 구성한다.
        // 매개변수:
        // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
        // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
        // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

// 클래스명: _ChatContentHeading
// 역할: 공유 카드의 유형 제목과 아이콘을 표시한다.
// 주요 책임: 공통 제목 크기를 유지하고 긴 제목은 남은 폭 안에서 줄바꿈한다.
// 속성: title (String): 제목; icon (IconData): 유형; color (Color): 표시색.
class _ChatContentHeading extends StatelessWidget {
  // 함수이름: _ChatContentHeading
  // 함수역할: 공유 유형 제목·아이콘·색상을 받는다.
  // 매개변수: title (String): 제목; icon (IconData): 아이콘; color (Color): 색.
  // 반환값: 새 _ChatContentHeading.
  const _ChatContentHeading({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  // 함수이름: build
  // 함수역할: 아이콘 옆에 가용 폭을 사용하는 유형 제목을 배치한다.
  // 매개변수: context (BuildContext): 글자 배율 위치.
  // 반환값: 공유 유형 제목 Row.
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 17,
            height: 1.25,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    ],
  );
}

// Function Name: _readableScheduleDay
// Description: Parses a schedule date and limits access to retained days through Korean today.
// Parameters: schedule (ChatScheduleContext): shared schedule with date text.
// Returns: Normalized day, or null for malformed, expired or future dates.
DateTime? _readableScheduleDay(ChatScheduleContext schedule) {
  final parsed = DateTime.tryParse(schedule.scheduleDate);
  if (parsed == null) return null;
  final day = MedicationHistoryDates.day(parsed);
  final today = MedicationHistoryDates.today(DateTime.now());
  return day.isBefore(MedicationHistoryDates.earliest(today)) ||
          day.isAfter(today)
      ? null
      : day;
}

// 클래스명: _MessageMedicationHistoryContext
// 역할: 공유 당시 집계와 최신 이력 진입을 표시하는 읽기 전용 카드.
// 주요 책임: 보관 기간이 지난 공유는 진입을 비활성화하고 안내한다.
// 속성: history (ChatMedicationHistoryContext): 공유 집계; text (_LinkedChatText): 문구; onPressed (VoidCallback?): 최신 조회.
class _MessageMedicationHistoryContext extends StatelessWidget {
  final ChatMedicationHistoryContext history;
  final _LinkedChatText text;
  final VoidCallback? onPressed;

  // 함수이름: _MessageMedicationHistoryContext
  // 함수역할: 공유 집계·표시 문구와 선택적 최신 조회 동작을 연결한다.
  // 매개변수: history (ChatMedicationHistoryContext): 집계; text (_LinkedChatText): 문구; onPressed (VoidCallback?): 진입.
  // 반환값: 새 _MessageMedicationHistoryContext.
  const _MessageMedicationHistoryContext({
    required this.history,
    required this.text,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 공유 기간·집계·기준 시점을 표시하고 90일 보관 한계 밖의 기간은 최신 기록 버튼을 막는다.
  // 매개변수: context (BuildContext): 카드 표시 위치.
  // 반환값: 읽기 전용 이력 공유 카드.
  @override
  Widget build(BuildContext context) {
    const foreground = MedBuddyColors.textStrong;
    const secondary = MedBuddyColors.textMuted;
    final range = MedicationHistoryRange(history.startDate, history.endDate);
    // 기록은 최근 90일만 열 수 있으므로 그보다 오래된 공유는 실패할 화면 대신 안내를 보인다.
    final today = MedicationHistoryDates.today(DateTime.now());
    final expired = range.start.isBefore(
      MedicationHistoryDates.earliest(today),
    );
    final open = expired ? null : onPressed;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('chat-medication-history-card'),
        onTap: open,
        borderRadius: MedBuddyRadii.control,
        child: DefaultTextStyle(
          style: TextStyle(
            color: foreground,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.35,
            letterSpacing: 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ChatContentHeading(
                title: text.medicationHistory,
                icon: Icons.history_rounded,
                color: foreground,
              ),
              const SizedBox(height: 8),
              Container(
                key: const Key('chat-history-summary-panel'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MedBuddyColors.chatContentSurface,
                  border: Border.all(color: MedBuddyColors.chatContentBorder),
                  borderRadius: MedBuddyRadii.control,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            range.label,
                            style: MedBuddyTextStyles.menuBody.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (open != null)
                          const Icon(
                            Icons.arrow_right_rounded,
                            color: MedBuddyColors.textMuted,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    MedicationHistoryChartsSummary.counts(
                      counts: MedicationHistoryChartCounts(
                        taken:
                            history.scheduledTakenCount ?? history.takenCount,
                        skipped:
                            history.scheduledSkippedCount ??
                            history.skippedCount,
                        unrecorded:
                            history.scheduledUnrecordedCount ??
                            history.unrecordedCount,
                        asNeeded: history.asNeededTakenCount ?? 0,
                      ),
                      isEnglish: text.isEnglish,
                      showAsNeeded: history.hasScheduledCounts,
                    ),
                  ],
                ),
              ),
              if (expired) ...[
                const SizedBox(height: 4),
                Text(
                  text.historyExpired,
                  key: const Key('chat-history-expired'),
                  style: TextStyle(color: secondary, fontSize: 13),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('chat-view-latest-history'),
                  onPressed: open,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: foreground,
                    disabledForegroundColor: secondary,
                    side: BorderSide(color: secondary),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(text.viewLatestRecords),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 클래스명: _MessageBubble
// 역할: 발신자 구분·메시지 시각·텍스트·첨부 본문을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 발신자 구분·메시지 시각·텍스트·첨부 본문 위젯을 구성한다.
// 속성:
// - message (ChatMessage): 본문·발신자·시각·읽음 상태·첨부를 담은 메시지.
// - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
// - loadingMedicationId (int?): 현재 개별 복약 상태를 갱신하는 약품 ID.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final int? loadingMedicationId;
  final _LinkedChatText text;
  final UserSetting userSetting;
  final ValueChanged<ChatMedicationContext> onMedicationPressed;
  final ValueChanged<ChatMessage>? onHistoryPressed;
  final ValueChanged<ChatMessage>? onSchedulePressed;
  final ValueChanged<ChatPlaceContext> onPharmacyCallRequested;
  final ValueChanged<ChatPlaceContext> onPharmacyDirectionsRequested;
  final ValueChanged<ChatMessage> onPlaceDetailsRequested;
  final ValueChanged<List<ChatMedicationContext>> onFindPharmacyRequested;
  final ValueChanged<List<ChatMedicationContext>> onFindHospitalRequested;

  // 함수이름: _MessageBubble
  // 함수역할: 발신자 구분·메시지 시각·텍스트·첨부 본문에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - message (ChatMessage): 본문·발신자·시각·읽음 상태·첨부를 담은 메시지.
  // - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
  // - loadingMedicationId (int?): 현재 개별 복약 상태를 갱신하는 약품 ID.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - onMedicationPressed (ValueChanged<ChatMedicationContext>): 대상 약품의 상세 정보 또는 복용 가이드를 여는 콜백.
  // - onSchedulePressed (ValueChanged<ChatMessage>?): 원본 메시지의 일정 맥락으로 복약 화면을 여는 콜백. 권한이 없으면 null이다.
  // - onPharmacyCallRequested (ValueChanged<ChatPlaceContext>): 공유 병원·약국으로 전화 연결을 요청할 콜백.
  // - onPharmacyDirectionsRequested (ValueChanged<ChatPlaceContext>): 공유 병원·약국의 길찾기를 요청할 콜백.
  // - onFindPharmacyRequested (ValueChanged<List<ChatMedicationContext>>): 첨부 약품 목록을 유지하며 주변 약국 선택을 여는 콜백.
  // - onHistoryPressed (ValueChanged<ChatMessage>?): 이력 공유 메시지의 기간별 복약 기록을 여는 콜백. 권한이 없으면 null이다.
  // - onPlaceDetailsRequested (ValueChanged<ChatMessage>): 공유 시설의 종류와 원래 메시지를 전달해 최신 상세 화면을 여는 콜백.
  // - onFindHospitalRequested (ValueChanged<List<ChatMedicationContext>>): 부족한 약의 첨부 목록을 유지한 채 병원 선택을 여는 콜백.
  // 반환값: 입력 설정이 반영된 _MessageBubble 인스턴스.
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.loadingMedicationId,
    required this.text,
    required this.userSetting,
    required this.onMedicationPressed,
    required this.onHistoryPressed,
    required this.onSchedulePressed,
    required this.onPharmacyCallRequested,
    required this.onPharmacyDirectionsRequested,
    required this.onPlaceDetailsRequested,
    required this.onFindPharmacyRequested,
    required this.onFindHospitalRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 발신자 구분·메시지 시각·텍스트·첨부 본문 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 발신자 구분·메시지 시각·텍스트·첨부 본문에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final localTime = message.createdAt.toLocal();
    final timeLabel = userSetting.formatTime(localTime.hour, localTime.minute);
    final heading = text.sharedContentHeading(message);
    final bubble = Container(
      key: ValueKey('chat-bubble-${message.messageId}'),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.76,
      ),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        color: isMine ? MedBuddyColors.chatOutgoing : Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(
          color: isMine ? MedBuddyColors.successBorder : MedBuddyColors.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.deletedForEveryone || message.hiddenForMe)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: MedBuddyColors.textMuted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text.deletedMessage,
                    style: TextStyle(
                      color: MedBuddyColors.textMuted,
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            )
          else ...[
            if (heading != null) ...[
              _ChatContentHeading(
                title: heading.$1,
                icon: heading.$2,
                color: MedBuddyColors.textStrong,
              ),
              const SizedBox(height: 8),
            ],
            if (message.historyContext != null) ...[
              _MessageMedicationHistoryContext(
                history: message.historyContext!,
                text: text,
                onPressed: onHistoryPressed == null
                    ? null
                    : () => onHistoryPressed!(message),
              ),
              const SizedBox(height: 8),
            ],
            for (final medication in message.attachedMedicationContexts) ...[
              _MessageMedicationContext(
                medication: medication,
                isLoading: medication.medicationId == loadingMedicationId,
                text: text,
                onPressed: loadingMedicationId != null
                    ? null
                    // 함수이름: build.onPressed callback
                    // 함수역할: 발신자 구분·메시지 시각·텍스트·첨부 본문에서 캡처된 작업 `onMedicationPressed(medication)`을 실행한다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    : () => onMedicationPressed(medication),
              ),
              const SizedBox(height: 8),
            ],
            for (final reference in message.medicationReferences)
              ChatMedicationReferenceTile(
                reference: reference,
                isEnglish: text.isEnglish,
              ),
            if (message.scheduleContext != null) ...[
              _MessageScheduleContext(
                schedule: message.scheduleContext!,
                text: text,
                onPressed:
                    onSchedulePressed == null ||
                        _readableScheduleDay(message.scheduleContext!) == null
                    ? null
                    // 함수이름: build.onPressed callback
                    // 함수역할: 발신자 구분·메시지 시각·텍스트·첨부 본문의 캡처된 상태에서 `onSchedulePressed!(message.scheduleContext!)` 값을 제공한다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: `onSchedulePressed!(message.scheduleContext!)`의 값.
                    : () => onSchedulePressed!(message),
              ),
              const SizedBox(height: 8),
            ],
            if (message.pharmacyContext != null) ...[
              _MessagePharmacyContext(
                pharmacy: message.pharmacyContext!,
                phoneVerified:
                    message.messageKind ==
                    ChatMessageKind.pharmacyPhoneVerified,
                text: text,
                // 함수이름: build.onCallRequested callback
                // 함수역할: 발신자 구분·메시지 시각·텍스트·첨부 본문에서 캡처된 작업 `onPharmacyCallRequested(message.pharmacyContext!)`을 실행한다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onCallRequested: () =>
                    onPharmacyCallRequested(message.pharmacyContext!),
                // 함수이름: build.onDirectionsRequested callback
                // 함수역할: 발신자 구분·메시지 시각·텍스트·첨부 본문에서 캡처된 작업 `onPharmacyDirectionsRequested(message.pharmacyContext!)`을 실행한다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onDirectionsRequested: () =>
                    onPharmacyDirectionsRequested(message.pharmacyContext!),
                onDetailsRequested: () => onPlaceDetailsRequested(message),
              ),
              const SizedBox(height: 8),
            ],
            if (message.hospitalContext != null) ...[
              _MessagePharmacyContext(
                pharmacy: message.hospitalContext!,
                phoneVerified: false,
                text: text,
                onCallRequested: () =>
                    onPharmacyCallRequested(message.hospitalContext!),
                onDirectionsRequested: () =>
                    onPharmacyDirectionsRequested(message.hospitalContext!),
                onDetailsRequested: () => onPlaceDetailsRequested(message),
              ),
              const SizedBox(height: 8),
            ],
            if (message.messageKind == ChatMessageKind.medicationShortage &&
                message.attachedMedicationContexts.isNotEmpty) ...[
              _MedicationShortageContext(
                message: message,
                text: text,
                // 함수이름: build.onFindPharmacyRequested callback
                // 함수역할: 메시지에 첨부된 약 목록을 유지하며 약국 검색을 연다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onFindPharmacyRequested: () =>
                    onFindPharmacyRequested(message.attachedMedicationContexts),
                onFindHospitalRequested: () =>
                    onFindHospitalRequested(message.attachedMedicationContexts),
              ),
              const SizedBox(height: 8),
            ],
            KeepWordsText(
              message.body,
              style: TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            if (message.showSafetyGuidance) ...[
              const SizedBox(height: 8),
              _MedicationSafetyGuidance(text: text),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    onFindHospitalRequested(message.attachedMedicationContexts),
                icon: const Icon(Icons.local_hospital_outlined, size: 18),
                label: Text(text.findNearbyHospital),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MedBuddyColors.primary,
                  side: BorderSide(color: MedBuddyColors.primary),
                ),
              ),
            ],
          ],
          const SizedBox(height: 4),
          Text(
            timeLabel,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              // 보낸 시각도 읽을 수 있게 13pt 이상으로 둔다.
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMine)
            SizedBox(
              width: 22,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18, right: 6),
                child: message.readAt == null
                    ? Text(
                        '1',
                        key: ValueKey(
                          'chat-unread-receipt-${message.messageId}',
                        ),
                        semanticsLabel: text.isEnglish
                            ? 'Not read by recipient'
                            : '상대가 아직 읽지 않음',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: MedBuddyColors.primaryDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
            ),
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

// Class Name: _LinkedChatText
// Role: Localized linked-chat and attachment copy.
// Responsibilities: Formats conversation status and medication, schedule and nearby-place sharing messages.
// Attributes: language (String): selected language code.
class _LinkedChatText {
  final String language;

  // 함수이름: _LinkedChatText
  // 함수역할: 연동 사용자 채팅과 약품·일정·약국 정보 공유에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _LinkedChatText 인스턴스.
  const _LinkedChatText(this.language);

  // Function Name: isEnglish
  // Description: Normalizes the language code and checks its English prefix.
  // Parameters: None.
  // Returns: True when the normalized code begins with en.
  bool get isEnglish => isEnglishLanguage(language);

  // 함수이름: sharedContentHeading
  // 함수역할: 일반 대화는 제목 없이 두고 공유 동작·첨부 종류에 맞는 제목과 아이콘을 선택한다.
  // 매개변수: message (ChatMessage): 표시할 메시지.
  // 반환값: (String, IconData) 또는 별도 이력 카드·일반 대화이면 null.
  (String, IconData)? sharedContentHeading(ChatMessage message) {
    if (message.historyContext != null) return null;
    final action = switch (message.messageKind) {
      ChatMessageKind.slotCheckRequest => (
        isEnglish ? 'Medication check request' : '복약 확인 요청',
        Icons.fact_check_outlined,
      ),
      ChatMessageKind.slotCompletion => (
        isEnglish ? 'Medication taken' : '복용 완료 알림',
        Icons.done_all,
      ),
      ChatMessageKind.medicationShortage => (
        isEnglish ? 'Medication running low' : '약 부족 알림',
        Icons.medication_outlined,
      ),
      ChatMessageKind.medicationDiscomfort => (
        isEnglish ? 'Medication discomfort' : '복용 불편 알림',
        Icons.health_and_safety_outlined,
      ),
      _ => null,
    };
    if (action != null) return action;
    if (message.hospitalContext != null) {
      return (
        isEnglish ? 'Hospital information' : '병원 정보',
        Icons.local_hospital_outlined,
      );
    }
    if (message.pharmacyContext != null) {
      return (
        isEnglish ? 'Pharmacy information' : '약국 정보',
        Icons.storefront_outlined,
      );
    }
    if (message.scheduleContext != null) {
      return (
        isEnglish ? 'Medication schedule' : '복약 일정',
        Icons.calendar_month_outlined,
      );
    }
    if (message.attachedMedicationContexts.isNotEmpty) {
      return (
        isEnglish ? 'Medication information' : '약 정보',
        Icons.medication_outlined,
      );
    }
    return null;
  }

  // 함수이름: medicationHistory
  // 함수역할: 공유 복약 기록 구역의 제목을 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 복약 기록 제목.
  String get medicationHistory => isEnglish ? 'Medication history' : '복약 기록';
  // Function Name: asNeededNotRecordable
  // Description: Selects the notice directing as-needed recording to the schedule in the current language.
  // Parameters: None.
  // Returns: Localized display text.
  String get asNeededNotRecordable => isEnglish
      ? 'Record as-needed doses from the schedule, then try again without them.'
      : '필요시 약은 일정의 필요시 복용에서 기록하고, 선택에서 뺀 뒤 다시 시도해 주세요.';
  // 함수이름: copyMessage
  // 함수역할: 메시지 복사 명령를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get copyMessage => isEnglish ? 'Copy' : '복사';
  // 함수이름: messageCopied
  // 함수역할: 메시지 복사 성공 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get messageCopied => isEnglish ? 'Message copied.' : '메시지를 복사했어요.';
  // 함수이름: copyFailed
  // 함수역할: 메시지 복사 실패 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get copyFailed =>
      isEnglish ? 'Could not copy the message.' : '메시지를 복사하지 못했어요.';
  // 함수이름: sharedStatus
  // 함수역할: 공유 당시 운영 상태 라벨를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get sharedStatus => isEnglish ? 'Status when sent' : '보낸 시점 운영 상태';

  // Function Name: placeOperatingStatus
  // Description: Formats the operating snapshot at sending time in Korean wall time, distinguishing past closing from upcoming opening/closing.
  // Parameters: place (ChatPlaceContext): shared place and optional snapshot.
  // Returns: Localized status; unknown/missing times do not imply current operation.
  String placeOperatingStatus(ChatPlaceContext place) {
    final snapshot = place.operatingSnapshot;
    final status = switch (snapshot?.status) {
      'open' => isEnglish ? 'Open' : '영업 중',
      'closing_soon' => isEnglish ? 'Closing soon' : '곧 영업 종료',
      'before_open' => isEnglish ? 'Not open yet' : '영업 전',
      'closed' => isEnglish ? 'Closed' : '영업 종료',
      _ => isEnglish ? 'Hours unconfirmed' : '운영 확인 필요',
    };
    if (snapshot == null || snapshot.status == 'unknown') return status;
    final closing = snapshot.status != 'before_open';
    final next = closing ? snapshot.closesAt : snapshot.opensAt;
    if (next == null) return status;
    // 국내 의료기관의 영업시각은 수신 기기의 시간대가 달라도 한국 시간으로 표시한다.
    final local = MedicationHistoryDates.wallTime(next);
    final asOf = MedicationHistoryDates.wallTime(snapshot.asOf);
    final sameDay =
        local.year == asOf.year &&
        local.month == asOf.month &&
        local.day == asOf.day;
    final clock = MedicationHistoryDates.clock(next);
    final time = sameDay ? clock : '${local.month}/${local.day} $clock';
    // 영업 종료 상태의 종료 시각은 이미 지난 시각이다.
    if (snapshot.status == 'closed') {
      return isEnglish ? '$status at $time' : '$time $status';
    }
    return isEnglish
        ? '$status · ${closing ? 'Closes' : 'Opens'} $time'
        : '$status · $time ${closing ? '종료' : '시작'}';
  }

  // 함수이름: viewLatestRecords
  // 함수역할: 공유 시점의 기록 대신 최신 기록을 조회하는 동작의 문구를 제공한다.
  // 매개변수: 없음.
  // 반환값: 언어에 맞는 최신 기록 보기 문구.
  String get viewLatestRecords =>
      isEnglish ? 'View latest records' : '최신 기록 보기';
  // Function Name: historyExpired
  // Description: Selects the expired-history access notice in the current language.
  // Parameters: None.
  // Returns: Localized display text.
  String get historyExpired => isEnglish
      ? 'Records older than 90 days can no longer be opened.'
      : '90일이 지난 기록은 더 이상 열 수 없어요.';

  // 함수이름: findNearbyHospital
  // 함수역할: 주변 병원 검색 명령를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get findNearbyHospital => isEnglish ? 'Find hospitals' : '병원 찾기';
  // 함수이름: shareCareTitle
  // 함수역할: 장소 공유 확인 제목를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get shareCareTitle => isEnglish ? 'Share place' : '장소 공유';
  // 함수이름: shareRecipient
  // 함수역할: 장소 공유 확인창의 수신자 이름을 표시한다.
  // 매개변수: name (String): 상대 이름.
  // 반환값: 현재 언어의 수신자 라벨.
  String shareRecipient(String name) =>
      isEnglish ? 'Send to: $name' : '받는 사람: $name';
  // 함수이름: careDate
  // 함수역할: 선택한 병원 조회 날짜를 언어별 날짜 형식으로 표시한다.
  // 매개변수: date (DateTime): 진료 조회 날짜.
  // 반환값: 진료 날짜 안내.
  String careDate(DateTime date) => isEnglish
      ? 'Consultation date: ${date.toIso8601String().split('T').first}'
      : '진료 날짜: ${date.year}년 ${date.month}월 ${date.day}일';
  // 함수이름: hospitalShareBody
  // 함수역할: 확정한 병원 이름을 장소 공유 본문에 넣는다.
  // 매개변수: name (String): 병원 이름.
  // 반환값: 현재 언어의 병원 공유 본문.
  String hospitalShareBody(String name) =>
      isEnglish ? 'I am sharing $name.' : '$name 병원 정보를 공유해요.';
  // 함수이름: hospitalHoursNotice
  // 함수역할: 방문 전 전화 확인과 예약 미확정 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get hospitalHoursNotice => isEnglish
      ? 'Hours may change. Call before visiting. This is not a reservation.'
      : '진료시간은 변경될 수 있어요. 방문 전 전화로 확인해주세요. 예약이 확정된 것은 아니에요.';

  // 함수이름: family
  // 함수역할: 현재 언어와 입력값에 맞춰 "Family" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get family => isEnglish ? 'Family' : '가족';
  // 함수이름: deleteMessages
  // 함수역할: 현재 언어와 입력값에 맞춰 "메시지 삭제" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deleteMessages => isEnglish ? 'Delete messages' : '메시지 삭제';
  // 함수이름: cancel
  // 함수역할: 현재 언어와 입력값에 맞춰 "Cancel" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get cancel => isEnglish ? 'Cancel' : '취소';

  // 함수이름: selectionScheduleChanged
  // 함수역할: 선택 이후 일정이 변경된 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get selectionScheduleChanged => isEnglish
      ? 'The selected schedule has changed. Please select the medication again.'
      : '선택한 복약 일정이 변경되었습니다. 약을 다시 선택해주세요.';
  // 함수이름: noConfirmableSchedule
  // 함수역할: 복용 완료로 기록할 시간대가 없는 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get noConfirmableSchedule => isEnglish
      ? 'No current schedule was found for the selected medication.'
      : '선택한 약의 오늘 일정을 찾지 못했습니다. 약 목록을 다시 확인해주세요.';
  // 함수이름: takenSaveFailed
  // 함수역할: 복용 기록 저장 실패 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 문구.
  String get takenSaveFailed => isEnglish
      ? 'Could not confirm the record. Check your connection and try again.'
      : '복용 기록의 저장을 확인하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해주세요.';
  // 함수이름: selectMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "메시지 선택" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get selectMessage => isEnglish ? 'Select message' : '메시지 선택';
  // 함수이름: selectedCount
  // 함수역할: 현재 언어와 입력값에 맞춰 "$count개 선택" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String selectedCount(int count) =>
      isEnglish ? '$count selected' : '$count개 선택';
  // 함수이름: deleteForMe
  // 함수역할: 현재 언어와 입력값에 맞춰 "나에게서만 삭제" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deleteForMe => isEnglish ? 'Delete for me' : '나에게서만 삭제';
  // 함수이름: deleteForEveryone
  // 함수역할: 현재 언어와 입력값에 맞춰 "모두에게서 삭제" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deleteForEveryone =>
      isEnglish ? 'Delete for everyone' : '모두에게서 삭제';
  // 함수이름: deletedMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "삭제된 메시지입니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deletedMessage =>
      isEnglish ? 'This message was deleted.' : '삭제된 메시지입니다.';
  // 함수이름: deleteWarning
  // 함수역할: 현재 언어와 입력값에 맞춰 "삭제한 메시지는 복구할 수 없어요. 나에게서만 삭제하면 상대방 기록은 유지돼요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deleteWarning => isEnglish
      ? 'This cannot be undone. Delete for me keeps the other person\'s copy. '
            'Delete for everyone removes the content for both people, but cannot recall previews already delivered.'
      : '삭제한 메시지는 복구할 수 없어요. 나에게서만 삭제하면 상대방 기록은 유지돼요. '
            '모두에게서 삭제해도 이미 전달된 알림 미리보기는 회수할 수 없어요.';
  // 함수이름: privateDeletionOnly
  // 함수역할: 현재 언어와 입력값에 맞춰 "내가 보낸 지 24시간이 지나지 않은 메시지만 모두에게서 삭제할 수 있어요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get privateDeletionOnly => isEnglish
      ? 'Only your own messages sent less than 24 hours ago can be deleted for everyone.'
      : '내가 보낸 지 24시간이 지나지 않은 메시지만 모두에게서 삭제할 수 있어요.';
  // 함수이름: deleteFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "삭제하지 못했어요. 연결 상태와 전송 후 24시간 제한을 확인한 뒤 다시 시도해 주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deleteFailed => isEnglish
      ? 'Could not delete messages. Check your connection and the 24-hour limit, then try again.'
      : '삭제하지 못했어요. 연결 상태와 전송 후 24시간 제한을 확인한 뒤 다시 시도해 주세요.';
  // 함수이름: medicationLoadFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 중인 약 정보를 불러오지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationLoadFailed => isEnglish
      ? 'Could not load active medication information.'
      : '복용 중인 약 정보를 불러오지 못했습니다.';
  // 함수이름: medicationDetailLoadFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 상세정보를 불러오지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationDetailLoadFailed => isEnglish
      ? 'Could not load the medication details.'
      : '약 상세정보를 불러오지 못했습니다.';
  // 함수이름: historyLoadFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "대화 내용을 불러오지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get historyLoadFailed =>
      isEnglish ? 'Could not load the conversation.' : '대화 내용을 불러오지 못했습니다.';
  // Function Name: medicationReferencesExpired
  // Description: Explains that attached medication-search references expired on the server and must be searched again.
  // Parameters: None.
  // Returns: The localized expired-reference recovery message.
  String get medicationReferencesExpired => isEnglish
      ? 'The searched medication has expired. Search for it again and attach it.'
      : '검색한 약 정보가 만료되었습니다. 약을 다시 검색해 첨부해 주세요.';
  // Function Name: historyShareUnavailable
  // Description: Explains why record sharing is unavailable during history loading or message selection.
  // Parameters: None.
  // Returns: The localized sharing-unavailable message.
  String get historyShareUnavailable => isEnglish
      ? 'Medication history cannot be shared right now.'
      : '지금은 복약 기록을 공유할 수 없습니다.';
  // 함수이름: sendFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "메시지를 보내지 못했습니다. 다시 눌러주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get sendFailed => isEnglish
      ? 'Could not send the message. Tap send again.'
      : '메시지를 보내지 못했습니다. 다시 눌러주세요.';
  // 함수이름: dose
  // 함수역할: 현재 언어와 입력값에 맞춰 "1회 $value" 문구를 제공한다.
  // 매개변수:
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String dose(String value) => isEnglish ? 'Dose: $value' : '1회 $value';
  // 함수이름: patientSuggestedMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "$medicationName 복용을 완료했어요." 문구를 제공한다.
  // 매개변수:
  // - medicationName (String): 사용자에게 표시할 약품 또는 계정 이름.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String patientSuggestedMessage(String medicationName) => isEnglish
      ? 'I finished taking $medicationName.'
      : '$medicationName 복용을 완료했어요.';
  // 함수이름: caregiverSuggestedMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "$peerName님, $medicationName 아직 안 드셨나요?" 문구를 제공한다.
  // 매개변수:
  // - peerName (String): 대화 상대를 표시할 이름.
  // - medicationName (String): 사용자에게 표시할 약품 또는 계정 이름.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String caregiverSuggestedMessage(String peerName, String medicationName) =>
      isEnglish
      ? '$peerName, have you taken $medicationName yet?'
      : '$peerName님, $medicationName 아직 안 드셨나요?';
  // 함수이름: exampleMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "예: $value" 문구를 제공한다.
  // 매개변수:
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String exampleMessage(String value) =>
      isEnglish ? 'Example: $value' : '예: $value';
  // 함수이름: medicationContextGuide
  // 함수역할: 현재 언어와 입력값에 맞춰 "대화할 약을 선택하면 사진과 복용량이 메시지에 함께 표시됩니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationContextGuide => isEnglish
      ? 'Choose a medication to include its photo and dose with the message.'
      : '대화할 약을 선택하면 사진과 복용량이 메시지에 함께 표시됩니다.';
  // 함수이름: retry
  // 함수역할: 현재 언어와 입력값에 맞춰 "다시 시도" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get retry => isEnglish ? 'Try again' : '다시 시도';
  // 함수이름: emptyConversation
  // 함수역할: 현재 언어와 입력값에 맞춰 "아직 대화가 없습니다.\n메시지를 보내 대화를 시작해보세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get emptyConversation => isEnglish
      ? 'No messages yet.\nSend a message to start the conversation.'
      : '아직 대화가 없습니다.\n메시지를 보내 대화를 시작해보세요.';
  // 함수이름: selectMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "대화할 약 선택" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get selectMedication => isEnglish ? 'Choose medication' : '대화할 약 선택';
  // 함수이름: sendMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "메시지 보내기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get sendMessage => isEnglish ? 'Send message' : '메시지 보내기';
  // 함수이름: connected
  // 함수역할: 현재 언어와 입력값에 맞춰 "실시간 연결됨" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get connected => isEnglish ? 'Live connection' : '실시간 연결됨';
  // 함수이름: connecting
  // 함수역할: 현재 언어와 입력값에 맞춰 "연결 중" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get connecting => isEnglish ? 'Connecting' : '연결 중';
  // 함수이름: reconnecting
  // 함수역할: 현재 언어와 입력값에 맞춰 "다시 연결 중" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get reconnecting => isEnglish ? 'Reconnecting' : '다시 연결 중';
  // 함수이름: disconnected
  // 함수역할: 현재 언어와 입력값에 맞춰 "연결 끊김" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get disconnected => isEnglish ? 'Disconnected' : '연결 끊김';
  // Function Name: linkUnavailableStatus
  // Description: Labels a conversation whose link is no longer active.
  // Parameters: None.
  // Returns: The localized ended-link status.
  String get linkUnavailableStatus => isEnglish ? 'Link ended' : '연동 해제됨';
  // Function Name: linkUnavailable
  // Description: Explains that the ended link prevents further conversation.
  // Parameters: None.
  // Returns: The localized link-unavailable notice.
  String get linkUnavailable => isEnglish
      ? 'This link has ended, so messages can no longer be sent here. Check the link under Patient/Caregiver link.'
      : '연동이 해제되어 이 대화에서는 더 이상 메시지를 보낼 수 없습니다. 환자·보호자 연동에서 확인해주세요.';
  // 함수이름: clearSelectedMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "선택한 약 해제" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get clearSelectedMedication =>
      isEnglish ? 'Clear selected medication' : '선택한 약 해제';
  // 함수이름: quickReplyLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "먹었어요" 문구를 제공한다.
  // 매개변수:
  // - reply (_ChatQuickReply): 전송할 빠른 답장 종류.
  // - isPatient (bool): 현재 사용자가 연동 환자 역할인지 여부.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String quickReplyLabel(_ChatQuickReply reply, {required bool isPatient}) {
    if (isPatient) {
      return switch (reply) {
        _ChatQuickReply.taken => isEnglish ? 'Taken' : '먹었어요',
        _ChatQuickReply.cannotNow => isEnglish ? 'Not right now' : '지금은 못 먹어요',
        _ChatQuickReply.shortage => isEnglish ? 'Running low' : '약이 부족해요',
        _ChatQuickReply.discomfort =>
          isEnglish ? 'I feel unwell' : '먹고 나서 불편해요',
      };
    }
    return switch (reply) {
      _ChatQuickReply.taken => isEnglish ? 'Taken yet?' : '복용하셨나요?',
      _ChatQuickReply.cannotNow =>
        isEnglish ? 'Can you take it now?' : '지금 복용 가능하세요?',
      _ChatQuickReply.shortage =>
        isEnglish ? 'Enough medication?' : '남은 약이 충분한가요?',
      _ChatQuickReply.discomfort =>
        isEnglish ? 'Any discomfort?' : '불편한 점은 없으세요?',
    };
  }

  // 함수이름: quickReplyIcon
  // 함수역할: 복용 완료·지금 불가·약 부족·불편 증상에 맞는 빠른 답장 아이콘을 선택한다.
  // 매개변수:
  // - reply (_ChatQuickReply): 전송할 빠른 답장 종류.
  // 반환값: IconData: 현재 시간대·빠른 답장 종류에 대응하는 아이콘.
  IconData quickReplyIcon(_ChatQuickReply reply) {
    return switch (reply) {
      _ChatQuickReply.taken => Icons.check_circle_outline_rounded,
      _ChatQuickReply.cannotNow => Icons.schedule_rounded,
      _ChatQuickReply.shortage => Icons.medication_liquid_outlined,
      _ChatQuickReply.discomfort => Icons.health_and_safety_outlined,
    };
  }

  // 함수이름: quickReplyBody
  // 함수역할: 현재 언어와 입력값에 맞춰 "$medicationNames 먹었어요." 문구를 제공한다.
  // 매개변수:
  // - reply (_ChatQuickReply): 전송할 빠른 답장 종류.
  // - medicationNames (String): 요약·전송 문구에 포함할 약품 이름 목록.
  // - isPatient (bool): 현재 사용자가 연동 환자 역할인지 여부.
  // - peerName (String): 대화 상대를 표시할 이름.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String quickReplyBody(
    _ChatQuickReply reply,
    String medicationNames, {
    required bool isPatient,
    required String peerName,
  }) {
    if (isPatient) {
      return switch (reply) {
        _ChatQuickReply.taken =>
          isEnglish ? 'I took $medicationNames.' : '$medicationNames 먹었어요.',
        _ChatQuickReply.cannotNow =>
          isEnglish
              ? 'I cannot take $medicationNames right now.'
              : '$medicationNames 지금은 못 먹어요.',
        _ChatQuickReply.shortage =>
          isEnglish
              ? 'I am running low on $medicationNames.'
              : '$medicationNames 약이 부족해요.',
        _ChatQuickReply.discomfort =>
          isEnglish
              ? 'I feel unwell after taking $medicationNames.'
              : '$medicationNames 먹고 나서 불편해요.',
      };
    }
    return switch (reply) {
      _ChatQuickReply.taken =>
        isEnglish
            ? '$peerName, have you taken $medicationNames?'
            : '$peerName님, $medicationNames 복용하셨나요?',
      _ChatQuickReply.cannotNow =>
        isEnglish
            ? '$peerName, can you take $medicationNames now?'
            : '$peerName님, $medicationNames 지금 복용 가능하세요?',
      _ChatQuickReply.shortage =>
        isEnglish
            ? '$peerName, do you have enough $medicationNames left?'
            : '$peerName님, $medicationNames 남은 약이 충분한가요?',
      _ChatQuickReply.discomfort =>
        isEnglish
            ? '$peerName, do you feel any discomfort after taking $medicationNames?'
            : '$peerName님, $medicationNames 복용 후 불편한 점은 없으세요?',
    };
  }

  // Function Name: onlyCaregiverCanRequest
  // Description: Explains that only the linked caregiver can request dose confirmation.
  // Parameters: None.
  // Returns: The localized role-restriction message.
  String get onlyCaregiverCanRequest => isEnglish
      ? 'Only the linked caregiver can send a check request.'
      : '복약 확인 요청은 연동된 보호자만 보낼 수 있습니다.';
  // 함수이름: scheduleSelectorTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "오늘의 복약 시간대" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get scheduleSelectorTitle =>
      isEnglish ? 'Today\'s medication times' : '오늘의 복약 시간대';
  // Function Name: noRequestableSchedule
  // Description: Explains why the request action is disabled when no dose slot is requestable.
  // Parameters: None.
  // Returns: The localized no-requestable-slot reason.
  String get noRequestableSchedule => isEnglish
      ? 'No medication times to check today'
      : '오늘 확인을 요청할 시간대가 없습니다';
  // Function Name: scheduleLoading
  // Description: Explains why dose actions remain unavailable while today's slots are loading.
  // Parameters: None.
  // Returns: The localized slot-loading reason.
  String get scheduleLoading => isEnglish
      ? 'Loading today\'s medication times...'
      : '오늘 복약 시간대를 불러오는 중입니다';
  // Function Name: scheduleLoadFailed
  // Description: Explains why dose actions are disabled after today's slot query failed.
  // Parameters: None.
  // Returns: The localized slot-load failure reason.
  String get scheduleLoadFailed => isEnglish
      ? 'Could not load today\'s medication times.'
      : '오늘 복약 시간대를 불러오지 못했습니다.';
  // 함수이름: scheduleSelectorCaregiverDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "확인이 필요한 시간대를 선택해 환자에게 알려주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get scheduleSelectorCaregiverDescription => isEnglish
      ? 'Choose a time to ask the patient to check their medication.'
      : '확인이 필요한 시간대를 선택해 환자에게 알려주세요.';
  // Function Name: slotLabel
  // Description: Maps a dose-slot key to its localized name.
  // Parameters: slotKey (String): morning, lunch, evening or bedtime.
  // Returns: The localized slot label.
  String slotLabel(String slotKey) {
    return medicationSlotLabel(
      slotKey,
      isEnglish: isEnglish,
      fallback: isEnglish ? 'Medication' : '복약',
    );
  }

  // 함수이름: slotIcon
  // 함수역할: 시간대 키별 아이콘을 선택하고 알 수 없는 키에는 기본 일정 아이콘을 사용한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // 반환값: IconData: 현재 시간대·빠른 답장 종류에 대응하는 아이콘.
  IconData slotIcon(String slotKey) {
    return switch (slotKey) {
      'morning' => Icons.wb_sunny_outlined,
      'lunch' => Icons.local_cafe_outlined,
      'evening' => Icons.wb_twilight_outlined,
      'bedtime' => Icons.nightlight_round,
      _ => Icons.schedule_rounded,
    };
  }

  // 함수이름: slotCheckRequestBody
  // 함수역할: 현재 언어와 입력값에 맞춰 "${slotLabel(slotKey)} 복약을 확인해주세요." 문구를 제공한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String slotCheckRequestBody(String slotKey) => isEnglish
      ? 'Please check your ${slotLabel(slotKey).toLowerCase()} medication.'
      : '${slotLabel(slotKey)} 복약을 확인해주세요.';
  // Function Name: remainingCourse
  // Description: Formats remaining dose days and the course end date, or explains why the course could not be calculated.
  // Parameters: days (int?): remaining days; endDate (DateTime?): course end.
  // Returns: Localized remaining-course text, or the unavailable message if either value is null.
  String remainingCourse(int? days, DateTime? endDate) {
    if (days == null || endDate == null) {
      return isEnglish
          ? 'The remaining course could not be calculated.'
          : '남은 복용 기간을 계산하지 못했습니다.';
    }
    final dateLabel = MedicationHistoryDates.format(endDate);
    return isEnglish
        ? '$days day(s) remaining · through $dateLabel'
        : '남은 복용 기간 $days일 · $dateLabel까지';
  }

  // 함수이름: findNearbyPharmacy
  // 함수역할: 현재 언어와 입력값에 맞춰 "근처 운영 약국 찾기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get findNearbyPharmacy => isEnglish ? 'Find pharmacies' : '약국 찾기';
  // 함수이름: pharmacyShareBody
  // 함수역할: 현재 언어와 입력값에 맞춰 "$pharmacyName 정보를 공유했어요." 문구를 제공한다.
  // 매개변수:
  // - pharmacyName (String): 공유 문구에 포함할 약국 이름.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String pharmacyShareBody(String pharmacyName) =>
      isEnglish ? 'I am sharing $pharmacyName.' : '$pharmacyName 정보를 공유했어요.';
  // 함수이름: pharmacyPhoneVerifiedBody
  // 함수역할: 현재 언어와 입력값에 맞춰 "$pharmacyName에 전화해 운영 여부를 확인했어요." 문구를 제공한다.
  // 매개변수:
  // - pharmacyName (String): 공유 문구에 포함할 약국 이름.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String pharmacyPhoneVerifiedBody(String pharmacyName) => isEnglish
      ? 'I called $pharmacyName and confirmed availability.'
      : '$pharmacyName에 전화해 운영 여부를 확인했어요.';
  // 함수이름: phoneVerified
  // 함수역할: 현재 언어와 입력값에 맞춰 "전화 확인 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get phoneVerified =>
      isEnglish ? 'Availability confirmed by phone' : '전화 확인 완료';
  // 함수이름: call
  // 함수역할: 현재 언어와 입력값에 맞춰 "Call" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get call => isEnglish ? 'Call' : '전화';
  // 함수이름: directions
  // 함수역할: 현재 언어와 입력값에 맞춰 "길찾기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get directions => isEnglish ? 'Directions' : '길찾기';
  // 함수이름: phoneUnavailable
  // 함수역할: 현재 언어와 입력값에 맞춰 "연결할 수 있는 약국 전화번호가 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get phoneUnavailable => isEnglish
      ? 'This pharmacy does not have a callable number.'
      : '연결할 수 있는 약국 전화번호가 없습니다.';
  // 함수이름: directionsUnavailable
  // 함수역할: 현재 언어와 입력값에 맞춰 "길찾기를 열지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get directionsUnavailable =>
      isEnglish ? 'Could not open directions.' : '길찾기를 열지 못했습니다.';
  // 함수이름: discomfortSafetyGuidance
  // 함수역할: 현재 언어와 입력값에 맞춰 "채팅만으로 증상을 판단할 수 없습니다. 증상이 심하거나 호흡 곤란·의식 변화가 있으면 즉시 119에 연락하고, 임의로 복용법을 바꾸기 전에 의료진이나 약사에게 상담하세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get discomfortSafetyGuidance => isEnglish
      ? 'This chat cannot diagnose symptoms. If symptoms are severe, breathing is difficult, or consciousness changes, call emergency services. Otherwise, contact a medical professional or pharmacist before changing how you take the medicine.'
      : '채팅만으로 증상을 판단할 수 없습니다. 증상이 심하거나 호흡 곤란·의식 변화가 있으면 즉시 119에 연락하고, 임의로 복용법을 바꾸기 전에 의료진이나 약사에게 상담하세요.';
}
