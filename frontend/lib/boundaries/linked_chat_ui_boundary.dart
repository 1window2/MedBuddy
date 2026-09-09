// 파일명: linked_chat_ui_boundary.dart
// 역할: 연동 사용자 채팅과 약품·일정·약국 정보 공유를 제공한다.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'check_schedule_ui_boundary.dart';
import 'check_medication_detail_ui_boundary.dart';
import 'check_nearby_pharmacy_ui_boundary.dart';
import '../controls/manage_linked_chat_control.dart';
import '../entities/chat_message_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/authenticated_api_client.dart';
import '../services/linked_chat_realtime_service.dart';
import '../services/pharmacy_external_action_service.dart';
import '../theme/medbuddy_theme.dart';

// 클래스명: LinkedChatUI
// 역할: 연동 사용자 메시지와 복약 관련 첨부를 담당한다.
// 주요 책임:
// - 연동 사용자 메시지와 복약 관련 첨부의 State가 사용할 화면 설정과 외부 의존성을 보관한다.
// 속성:
// - linkId (int): 대화·별칭·연결 작업의 연동 식별자.
// - currentUserHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
// - patientHash (String): 연동된 환자의 계정 해시.
// - peerName (String): 대화 상대를 표시할 이름.
class LinkedChatUI extends StatefulWidget {
  final int linkId;
  final String currentUserHash;
  final String patientHash;
  final String peerName;
  final UserSetting userSetting;
  final List<ChatMedicationContext> initialMedicationContexts;
  final ManageLinkedChat? control;
  final LinkedChatRealtimeService? realtimeService;
  final AuthenticatedApiClient? apiClient;

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
  // 반환값: 입력 설정이 반영된 LinkedChatUI 인스턴스.
  const LinkedChatUI({
    super.key,
    required this.linkId,
    required this.currentUserHash,
    this.patientHash = '',
    this.peerName = '가족',
    this.userSetting = const UserSetting(),
    this.initialMedicationContexts = const [],
    this.control,
    this.realtimeService,
    this.apiClient,
  });

  // 함수이름: createState
  // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _LinkedChatUIState 인스턴스.
  @override
  State<LinkedChatUI> createState() => _LinkedChatUIState();
}

// 클래스명: _LinkedChatUIState
// 역할: 연동 사용자 메시지와 복약 관련 첨부의 화면 상태를 관리한다.
// 주요 책임:
// - 앱 복귀 시 실시간 연결·메시지 조회를 재개하고 비활성 상태에서는 연결을 멈춘다.
// - 메시지·약품·시간대 맥락과 실시간 연결을 함께 초기화한 뒤 12초 보완 조회를 시작한다.
// - 메시지 추가·삭제·읽음 이벤트를 검증해 반영하고 복약 관련 맥락을 필요 시 갱신한다.
// 속성:
// - _scrollController (ScrollController): 목록 위치 제어와 스크롤 안내에 사용할 컨트롤러.
// - _apiClient (AuthenticatedApiClient): 인증 세션을 사용하는 API 요청 클라이언트.
// - _control (ManageLinkedChat): 화면의 조회·변경 요청을 처리할 컨트롤러.
// - _realtimeService (LinkedChatRealtimeService): 연동 채팅의 이벤트·연결 상태 스트림 제공자.
class _LinkedChatUIState extends State<LinkedChatUI>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Random _random = Random.secure();
  final PharmacyExternalActionService _pharmacyActionService =
      PharmacyExternalActionService();

  late final AuthenticatedApiClient _apiClient;
  late final ManageLinkedChat _control;
  late final LinkedChatRealtimeService _realtimeService;
  late final bool _ownsApiClient;
  late final bool _ownsControl;
  late final bool _ownsRealtimeService;

  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  StreamSubscription<LinkedChatConnectionState>? _stateSubscription;
  Timer? _fallbackRefreshTimer;
  Timer? _medicationContextGuideTimer;
  List<ChatMessage> _messages = const [];
  List<ChatMedicationContext> _medicationContexts = const [];
  List<ChatScheduleContext> _scheduleContexts = const [];
  List<ChatMedicationContext> _selectedMedicationContexts = const [];
  LinkedChatConnectionState _connectionState =
      LinkedChatConnectionState.connecting;
  String? _errorMessage;
  String? _sendErrorMessage;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isSelectingMessages = false;
  bool _isDeletingMessages = false;
  final Set<int> _selectedMessageIds = {};
  final Set<int> _hiddenMessageIds = {};
  final Set<int> _deletedMessageIds = {};
  String? _pendingClientMessageId;
  String? _pendingMessageBody;
  String? _pendingMedicationIdsSignature;
  ChatMessageKind _pendingMessageKind = ChatMessageKind.text;
  String? _pendingSlotKey;
  String? _pendingPharmacyId;
  int? _loadingMedicationId;
  int _requestGeneration = 0;
  bool _showMedicationContextGuide = true;

  // 함수이름: _text
  // 함수역할: 현재 언어에 맞는 연동 사용자 채팅과 약품·일정·약국 정보 공유 문구 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: _LinkedChatText: 현재 화면 언어의 문구 제공 객체.
  _LinkedChatText get _text => _LinkedChatText(widget.userSetting.language);

  // 함수이름: _isPatient
  // 함수역할: 현재 사용자 해시가 비어 있지 않은 연결 환자 해시와 같은지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get _isPatient =>
      widget.patientHash.isNotEmpty &&
      widget.currentUserHash == widget.patientHash;

  // 함수이름: _peerName
  // 함수역할: 영어 화면에서 기본 가족 이름만 번역하고 지정된 상대 이름은 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get _peerName {
    if (_text.isEnglish && widget.peerName == '가족') {
      return _text.family;
    }
    return widget.peerName;
  }

  // 함수이름: initState
  // 함수역할: 초기 약품 맥락·API·실시간 구독을 준비하고 안내 타이머와 첫 채팅 조회를 시작한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    _medicationContexts = widget.initialMedicationContexts;
    WidgetsBinding.instance.addObserver(this);
    _ownsApiClient = widget.apiClient == null;
    _apiClient = widget.apiClient ?? AuthenticatedApiClient();
    _ownsControl = widget.control == null;
    _control =
        widget.control ??
        ManageLinkedChat(userHash: widget.currentUserHash, client: _apiClient);
    _ownsRealtimeService = widget.realtimeService == null;
    _realtimeService =
        widget.realtimeService ??
        LinkedChatRealtimeService(
          linkId: widget.linkId,
          userHash: widget.currentUserHash,
          authenticationClient: _apiClient,
        );
    _eventSubscription = _realtimeService.events.listen(_handleRealtimeEvent);
    // 함수이름: initState.listen callback
    // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에서 캡처된 작업 `setState(() => _connectionState = state)`을 실행한다.
    // 매개변수:
    // - state (콜백 계약에서 추론): 현재 인증 초기화·로그인 상태 또는 전달된 앱 생명주기 상태.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    _stateSubscription = _realtimeService.states.listen((state) {
      if (mounted) {
        // 함수이름: initState.setState callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_connectionState = state`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() => _connectionState = state);
      }
    });
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

  // 함수이름: dispose
  // 함수역할: _fallbackRefreshTimer, _medicationContextGuideTimer, _eventSubscription, _stateSubscription, _realtimeService, _control, _apiClient, _messageController, _scrollController 관련 자원을 정리하고 화면 수명 종료 처리를 수행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requestGeneration += 1;
    _fallbackRefreshTimer?.cancel();
    _medicationContextGuideTimer?.cancel();
    unawaited(_eventSubscription?.cancel());
    unawaited(_stateSubscription?.cancel());
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

  // 함수이름: didChangeAppLifecycleState
  // 함수역할: 앱 복귀 시 실시간 연결·메시지 조회를 재개하고 비활성 상태에서는 연결을 멈춘다.
  // 매개변수:
  // - state (AppLifecycleState): Flutter가 전달한 앱의 전경·배경 생명주기 상태.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_realtimeService.start());
      unawaited(_refreshMessages(showLoading: false));
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_realtimeService.stop());
    }
  }

  // 함수이름: _initializeChat
  // 함수역할: 메시지·약품·시간대 맥락과 실시간 연결을 함께 초기화한 뒤 12초 보완 조회를 시작한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _initializeChat() async {
    await Future.wait([
      _refreshMessages(showLoading: true),
      _refreshMedicationContexts(),
      _refreshScheduleContexts(),
      _realtimeService.start(),
    ]);
    if (!mounted) {
      return;
    }
    // 함수이름: _initializeChat.periodic callback
    // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에서 캡처된 작업 `_refreshMessages(showLoading: false)`을 실행한다.
    // 매개변수:
    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    _fallbackRefreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(_refreshMessages(showLoading: false));
    });
  }

  // 함수이름: _refreshMedicationContexts
  // 함수역할: 현재 연동 환자의 활성 복약정보를 불러와 메시지에 연결할 수 있게 한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _refreshMedicationContexts() async {
    final generation = _requestGeneration;
    try {
      final medications = await _control.requestMedicationContexts(
        linkId: widget.linkId,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      // 함수이름: _refreshMedicationContexts.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_medicationContexts = medications; _selectedMedicationContexts = medications.where((item) => selectedIds.contains(item.medicationId)...`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _medicationContexts = medications;
        final selectedIds = _selectedMedicationContexts
            // 함수이름: _refreshMedicationContexts.map callback
            // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 변환값을 `item.medicationId` 규칙으로 계산한다.
            // 매개변수:
            // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
            // 반환값: 컬렉션 연산에 전달할 변환값.
            .map((item) => item.medicationId)
            .toSet();
        _selectedMedicationContexts = medications
            // 함수이름: _refreshMedicationContexts.where callback
            // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 대해 `selectedIds.contains(item.medicationId)` 조건으로 컬렉션 항목을 판별한다.
            // 매개변수:
            // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
            // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
            .where((item) => selectedIds.contains(item.medicationId))
            .toList(growable: false);
      });
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
          _sendErrorMessage = _text.medicationLoadFailed;
        }
      });
    }
  }

  // 함수이름: _refreshScheduleContexts
  // 함수역할: 채팅에서 공유하거나 확인 요청할 오늘 복약 시간대 상태를 갱신한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _refreshScheduleContexts() async {
    final generation = _requestGeneration;
    try {
      final contexts = await _control.requestScheduleContexts(
        linkId: widget.linkId,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      // 함수이름: _refreshScheduleContexts.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_scheduleContexts = contexts`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _scheduleContexts = contexts);
    } catch (_) {
      // 채팅 자체는 계속 사용할 수 있으므로 시간대 카드 실패는 조용히 보완 조회한다.
    }
  }

  // 함수이름: _refreshMessages
  // 함수역할: 최초 기록과 WebSocket 누락 가능성이 있는 메시지를 REST 조회로 보완한다.
  // 매개변수:
  // - showLoading (bool): 진행 중 표시를 보여줄지 여부.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _refreshMessages({required bool showLoading}) async {
    final generation = _requestGeneration;
    if (showLoading && mounted) {
      // 함수이름: _refreshMessages.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_isLoading = true; _errorMessage = null`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final messages = await _control.requestHistory(linkId: widget.linkId);
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      // 함수이름: _refreshMessages.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_messages = _mergeMessages(_messages, messages); _isLoading = false; _errorMessage = null`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _messages = _mergeMessages(_messages, messages);
        _isLoading = false;
        _errorMessage = null;
      });
      _scrollToLatest();
      await _markLatestIncomingRead();
    } catch (_) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      // 함수이름: _refreshMessages.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_isLoading = false; _errorMessage = _text.historyLoadFailed`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _isLoading = false;
        if (_messages.isEmpty) {
          _errorMessage = _text.historyLoadFailed;
        }
      });
    }
  }

  // 함수이름: _handleRealtimeEvent
  // 함수역할: 메시지 추가·삭제·읽음 이벤트를 검증해 반영하고 복약 관련 맥락을 필요 시 갱신한다.
  // 매개변수:
  // - event (Map<String, dynamic>): 실시간 메시지·읽음·삭제 이벤트 데이터.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _handleRealtimeEvent(Map<String, dynamic> event) {
    if (!mounted) {
      return;
    }
    final type = event['type']?.toString();
    if (type == 'chat_messages_deleted') {
      final ids = event['message_ids'];
      if (ids is List &&
          (event['scope'] == 'me' || event['scope'] == 'everyone')) {
        _applyMessageDeletion(
          ids.whereType<int>().toList(),
          event['scope'] == 'me'
              ? ChatDeletionScope.me
              : ChatDeletionScope.everyone,
        );
      }
      return;
    }
    if (type == 'chat_message') {
      final rawMessage = event['message'];
      if (rawMessage is! Map) {
        return;
      }
      try {
        final message = ChatMessage.fromJson(
          Map<String, dynamic>.from(rawMessage),
        );
        // 함수이름: _handleRealtimeEvent.setState callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_messages = _mergeMessages(_messages, [message]); _errorMessage = null`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() {
          _messages = _mergeMessages(_messages, [message]);
          _errorMessage = null;
        });
        _scrollToLatest();
        if (message.messageKind == ChatMessageKind.slotCheckRequest ||
            message.messageKind == ChatMessageKind.slotCompletion) {
          unawaited(_refreshScheduleContexts());
        }
        if (message.senderHash != widget.currentUserHash) {
          unawaited(_markLatestIncomingRead());
        }
      } on FormatException {
        return;
      }
      return;
    }
    if (type == 'chat_read' &&
        event['reader_hash']?.toString() != widget.currentUserHash) {
      final throughMessageId = int.tryParse(
        event['through_message_id']?.toString() ?? '',
      );
      final readAt = DateTime.tryParse(event['read_at']?.toString() ?? '');
      if (throughMessageId == null || readAt == null) {
        return;
      }
      // 함수이름: _handleRealtimeEvent.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_messages = _messages.map((message) => message.senderHash == widget.currentUserHash && message.me...`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _messages = _messages
            .map(
              // 함수이름: _handleRealtimeEvent.map callback
              // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 변환값을 `message.senderHash == widget.currentUserHash && message.messageId <= throughMessageId ? message.copyWith(readAt: readAt) :...` 규칙으로 계산한다.
              // 매개변수:
              // - message (콜백 계약에서 추론): 현재 작업 결과·오류·상태에 대한 표시 문구.
              // 반환값: 컬렉션 연산에 전달할 변환값.
              (message) =>
                  message.senderHash == widget.currentUserHash &&
                      message.messageId <= throughMessageId
                  ? message.copyWith(readAt: readAt)
                  : message,
            )
            .toList(growable: false);
      });
    }
  }

  // 함수이름: _markLatestIncomingRead
  // 함수역할: 가장 최근 수신 메시지까지 읽음 처리하고 실패는 이후 갱신에서 재시도하도록 남긴다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _markLatestIncomingRead() async {
    final incoming = _messages
        // 함수이름: _markLatestIncomingRead.where callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 대해 `message.senderHash != widget.currentUserHash` 조건으로 컬렉션 항목을 판별한다.
        // 매개변수:
        // - message (콜백 계약에서 추론): 현재 작업 결과·오류·상태에 대한 표시 문구.
        // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
        .where((message) => message.senderHash != widget.currentUserHash)
        .toList(growable: false);
    if (incoming.isEmpty) {
      return;
    }
    try {
      await _control.markRead(
        linkId: widget.linkId,
        throughMessageId: incoming.last.messageId,
      );
    } catch (_) {
      // 읽음 표시는 다음 실시간 이벤트 또는 보완 조회에서 다시 시도한다.
    }
  }

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
      clearComposer: true,
      clearMedicationSelection: true,
    );
  }

  // 함수이름: _submitMessage
  // 함수역할: 일반 문장과 구조화된 복약·약국 메시지의 전송, 재시도와 화면 갱신을 한곳에서 처리한다.
  // 매개변수:
  // - body (String): 앞뒤 공백 제거 후 전송할 메시지 본문.
  // - medications (List<ChatMedicationContext>): 조회·선택·정렬·표시에 사용할 약품 목록.
  // - messageKind (ChatMessageKind): 일반 텍스트·복약·약국 공유 등 메시지 종류.
  // - slotKey (String?): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // - pharmacyId (String?): 공유하거나 지도에서 선택한 약국 ID.
  // - clearComposer (bool): 전송 성공 후 작성 본문을 비울지 여부.
  // - clearMedicationSelection (bool): 전송 성공 후 선택한 약 첨부를 해제할지 여부.
  // 반환값: Future<ChatMessage?>: 저장된 메시지; 전송 실패 또는 요청 생략 시 null.
  Future<ChatMessage?> _submitMessage({
    required String body,
    List<ChatMedicationContext> medications = const [],
    ChatMessageKind messageKind = ChatMessageKind.text,
    String? slotKey,
    String? pharmacyId,
    bool clearComposer = false,
    bool clearMedicationSelection = false,
  }) async {
    final normalizedBody = body.trim();
    if (_isSending ||
        _isDeletingMessages ||
        _isSelectingMessages ||
        normalizedBody.isEmpty) {
      return null;
    }
    FocusScope.of(context).unfocus();
    // 함수이름: _submitMessage.setState callback
    // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_isSending = true; _sendErrorMessage = null`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _isSending = true;
      _sendErrorMessage = null;
    });
    final medicationIdsSignature = _medicationIdsSignature(medications);
    final canReusePendingRequest =
        _pendingMessageBody == normalizedBody &&
        _pendingMedicationIdsSignature == medicationIdsSignature &&
        _pendingMessageKind == messageKind &&
        _pendingSlotKey == slotKey &&
        _pendingPharmacyId == pharmacyId;
    final clientMessageId = canReusePendingRequest
        ? _pendingClientMessageId ?? _createClientMessageId()
        : _createClientMessageId();
    _pendingClientMessageId = clientMessageId;
    _pendingMessageBody = normalizedBody;
    _pendingMedicationIdsSignature = medicationIdsSignature;
    _pendingMessageKind = messageKind;
    _pendingSlotKey = slotKey;
    _pendingPharmacyId = pharmacyId;
    try {
      final message = await _control.sendMessage(
        linkId: widget.linkId,
        clientMessageId: clientMessageId,
        body: normalizedBody,
        medicationId: medications.isEmpty
            ? null
            : medications.first.medicationId,
        medicationIds: medications
            // 함수이름: _submitMessage.map callback
            // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 변환값을 `item.medicationId` 규칙으로 계산한다.
            // 매개변수:
            // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
            // 반환값: 컬렉션 연산에 전달할 변환값.
            .map((item) => item.medicationId)
            .toList(growable: false),
        messageKind: messageKind,
        slotKey: slotKey,
        pharmacyId: pharmacyId,
      );
      if (!mounted) {
        return message;
      }
      if (clearComposer) {
        _messageController.clear();
      }
      _clearPendingRequest();
      // 함수이름: _submitMessage.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_selectedMedicationContexts = const []; _messages = _mergeMessages(_messages, [message]); _errorMessage = null`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        if (clearMedicationSelection) {
          _selectedMedicationContexts = const [];
        }
        _messages = _mergeMessages(_messages, [message]);
        _errorMessage = null;
        _sendErrorMessage = null;
      });
      _scrollToLatest();
      return message;
    } catch (_) {
      if (!mounted) {
        return null;
      }
      // 함수이름: _submitMessage.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_sendErrorMessage = _text.sendFailed`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _sendErrorMessage = _text.sendFailed;
      });
      return null;
    } finally {
      if (mounted) {
        // 함수이름: _submitMessage.setState callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_isSending = false`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() => _isSending = false);
      }
    }
  }

  // 함수이름: _clearPendingRequest
  // 함수역할: 재전송에 사용하던 메시지 ID·본문·첨부·종류·시간대·약국 정보를 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _clearPendingRequest() {
    _pendingClientMessageId = null;
    _pendingMessageBody = null;
    _pendingMedicationIdsSignature = null;
    _pendingMessageKind = ChatMessageKind.text;
    _pendingSlotKey = null;
    _pendingPharmacyId = null;
  }

  // 함수이름: _sendQuickReply
  // 함수역할: 사용자 역할과 선택 약품에 맞는 빠른 답장을 보내고 환자 약 부족 답장 뒤에는 약국 선택을 연다.
  // 매개변수:
  // - reply (_ChatQuickReply): 전송할 빠른 답장 종류.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _sendQuickReply(_ChatQuickReply reply) async {
    final medications = _selectedMedicationContexts;
    if (medications.isEmpty || _isSending) {
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
    final sent = await _submitMessage(
      body: body,
      medications: medications,
      messageKind: messageKind,
      clearMedicationSelection:
          !_isPatient || reply != _ChatQuickReply.shortage,
    );
    if (sent != null &&
        _isPatient &&
        reply == _ChatQuickReply.shortage &&
        mounted) {
      await _showPharmacySelector(medications: medications);
    }
  }

  // 함수이름: _showPharmacySelector
  // 함수역할: 약국 선택 결과를 전화 확인 여부에 맞는 메시지 종류로 공유한다.
  // 매개변수:
  // - medications (List<ChatMedicationContext>): 조회·선택·정렬·표시에 사용할 약품 목록.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showPharmacySelector({
    List<ChatMedicationContext> medications = const [],
  }) async {
    if (_isSending) {
      return;
    }
    final selection = await Navigator.of(context).push<NearbyPharmacySelection>(
      MaterialPageRoute(
        // 함수이름: _showPharmacySelector.builder callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
        // 매개변수:
        // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        builder: (_) =>
            CheckNearbyPharmacyUI.selection(userSetting: widget.userSetting),
      ),
    );
    if (selection == null || !mounted) {
      return;
    }
    final messageKind = selection.phoneVerified
        ? ChatMessageKind.pharmacyPhoneVerified
        : ChatMessageKind.pharmacyShare;
    final sent = await _submitMessage(
      body: selection.phoneVerified
          ? _text.pharmacyPhoneVerifiedBody(selection.pharmacy.name)
          : _text.pharmacyShareBody(selection.pharmacy.name),
      medications: medications,
      messageKind: messageKind,
      pharmacyId: selection.pharmacy.pharmacyId,
      clearMedicationSelection: true,
    );
    if (sent != null && mounted) {
      // 함수이름: _showPharmacySelector.setState callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_selectedMedicationContexts = const []`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _selectedMedicationContexts = const []);
    }
  }

  // 함수이름: _showScheduleSelector
  // 함수역할: 시간대 선택 후 확인 요청 권한을 확인해 복약 체크 요청 메시지를 보낸다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showScheduleSelector() async {
    if (_scheduleContexts.isEmpty || _isSending) {
      if (_scheduleContexts.isEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_text.noScheduleContext)));
      }
      return;
    }
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
          _ScheduleContextSelector(contexts: _scheduleContexts, text: _text),
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
  Future<void> _callPharmacy(ChatPharmacyContext pharmacy) async {
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
  // 함수역할: 공유 약국의 이름과 좌표로 길찾기를 요청하고 실패를 안내한다.
  // 매개변수:
  // - pharmacy (ChatPharmacyContext): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _openPharmacyDirections(ChatPharmacyContext pharmacy) async {
    final succeeded = await _pharmacyActionService.requestDirections(
      name: pharmacy.name,
      latitude: pharmacy.latitude,
      longitude: pharmacy.longitude,
    );
    if (!succeeded && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_text.directionsUnavailable)));
    }
  }

  // 함수이름: _showMedicationSelector
  // 함수역할: 현재 환자가 복용 중인 약을 사진과 함께 보여주고 대화 대상을 선택한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showMedicationSelector() async {
    if (_medicationContexts.isEmpty || _isSending) {
      return;
    }
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
        builder: (context) => CheckScheduleUI.selection(
          schedules: selectionSchedules,
          language: widget.userSetting.language,
          selectedMedicationIds: _selectedMedicationContexts
              // 함수이름: _showMedicationSelector.map callback
              // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 변환값을 `item.medicationId.toString()` 규칙으로 계산한다.
              // 매개변수:
              // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
              // 반환값: 컬렉션 연산에 전달할 변환값.
              .map((item) => item.medicationId.toString())
              .toSet(),
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
        .map((item) => medicationsById[int.tryParse(item.medicationID)])
        .whereType<ChatMedicationContext>()
        .toList(growable: false);
    // 함수이름: _showMedicationSelector.setState callback
    // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_selectedMedicationContexts = selected; _sendErrorMessage = null`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _selectedMedicationContexts = selected;
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

  // 함수이름: _openPatientSchedule
  // 함수역할: 환자가 채팅의 시간대 카드를 누르면 같은 시간대가 보이는 오늘 일정으로 이동한다.
  // 매개변수:
  // - schedule (ChatScheduleContext): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _openPatientSchedule(ChatScheduleContext schedule) async {
    if (!_isPatient) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        // 함수이름: _openPatientSchedule.builder callback
        // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
        // 매개변수:
        // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        builder: (_) => CheckScheduleUI(initialSlotKey: schedule.slotKey),
      ),
    );
  }

  // 함수이름: _medicationIdsSignature
  // 함수역할: 선택한 약품 ID를 정렬해 순서와 무관한 재전송 비교 키를 만든다.
  // 매개변수:
  // - medications (List<ChatMedicationContext>): 조회·선택·정렬·표시에 사용할 약품 목록.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _medicationIdsSignature(List<ChatMedicationContext> medications) {
    // 함수이름: _medicationIdsSignature.map callback
    // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 변환값을 `item.medicationId` 규칙으로 계산한다.
    // 매개변수:
    // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
    // 반환값: 컬렉션 연산에 전달할 변환값.
    final ids = medications.map((item) => item.medicationId).toList()..sort();
    return ids.join(',');
  }

  // 함수이름: _openMedicationDetail
  // 함수역할: 중복 조회를 막고 연동 범위의 약 상세를 조회한 뒤 상세 화면을 열거나 오류를 안내한다.
  // 매개변수:
  // - medication (ChatMedicationContext): 표시·변환·저장·비교할 약품 데이터.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _openMedicationDetail(ChatMedicationContext medication) async {
    if (_loadingMedicationId != null) {
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
        linkId: widget.linkId,
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
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          // 함수이름: _openMedicationDetail.builder callback
          // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
          // 매개변수:
          // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
          // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
          builder: (_) => CheckMedicationDetailUI(
            medicationDetail: detail,
            userSetting: widget.userSetting,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_text.medicationDetailLoadFailed)));
    }
  }

  // 함수이름: _createClientMessageId
  // 함수역할: 마이크로초 시각과 임의의 16진수 값을 조합해 전송 중복 방지용 메시지 ID를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _createClientMessageId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomPart = _random.nextInt(0x7fffffff).toRadixString(16);
    return 'msg_${timestamp}_$randomPart';
  }

  // 함수이름: _mergeMessages
  // 함수역할: 메시지 ID로 새 결과를 병합하고 본인 숨김·전체 삭제 상태를 유지하며 ID 순으로 정렬한다.
  // 매개변수:
  // - current (List<ChatMessage>): 병합 이전에 화면이 보관한 메시지 목록.
  // - incoming (List<ChatMessage>): 조회 또는 실시간으로 수신한 메시지 목록.
  // 반환값: List<ChatMessage>: 숨김·삭제 상태를 반영하고 ID로 정렬한 메시지 목록.
  List<ChatMessage> _mergeMessages(
    List<ChatMessage> current,
    List<ChatMessage> incoming,
  ) {
    final byId = <int, ChatMessage>{
      for (final message in current) message.messageId: message,
      for (final message in incoming) message.messageId: message,
    };
    for (final message in incoming) {
      if (message.hiddenForMe) _hiddenMessageIds.add(message.messageId);
      if (message.deletedForEveryone) _deletedMessageIds.add(message.messageId);
    }
    final merged =
        byId.values
            // 함수이름: _mergeMessages.where callback
            // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 대해 `!_hiddenMessageIds.contains(message.messageId)` 조건으로 컬렉션 항목을 판별한다.
            // 매개변수:
            // - message (콜백 계약에서 추론): 현재 작업 결과·오류·상태에 대한 표시 문구.
            // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
            .where((message) => !_hiddenMessageIds.contains(message.messageId))
            .map(
              // 함수이름: _mergeMessages.map callback
              // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 변환값을 `_deletedMessageIds.contains(message.messageId) ? message.copyWith(deletedForEveryone: true) : message` 규칙으로 계산한다.
              // 매개변수:
              // - message (콜백 계약에서 추론): 현재 작업 결과·오류·상태에 대한 표시 문구.
              // 반환값: 컬렉션 연산에 전달할 변환값.
              (message) => _deletedMessageIds.contains(message.messageId)
                  ? message.copyWith(deletedForEveryone: true)
                  : message,
            )
            .toList(growable: false)
          // 함수이름: _mergeMessages.sort callback
          // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 정렬 비교값을 `left.messageId.compareTo(right.messageId)` 규칙으로 계산한다.
          // 매개변수:
          // - left (콜백 계약에서 추론): 정렬 순서를 비교할 두 항목 중 해당 항목.
          // - right (콜백 계약에서 추론): 정렬 순서를 비교할 두 항목 중 해당 항목.
          // 반환값: 컬렉션 연산에 전달할 정렬 비교값.
          ..sort((left, right) => left.messageId.compareTo(right.messageId));
    return merged;
  }

  // 함수이름: _applyMessageDeletion
  // 함수역할: 삭제 범위별 ID를 누적해 지연 응답이 삭제된 본문·약품 카드를 복원하지 못하게 하고 메시지 병합과 선택 상태를 갱신한다.
  // 매개변수:
  // - ids (List<int>): 선택·삭제 대상으로 사용할 메시지 식별자.
  // - scope (ChatDeletionScope): 본인에게만 삭제할지 모든 참여자에게 삭제할지 범위.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _applyMessageDeletion(List<int> ids, ChatDeletionScope scope) {
    if (!mounted) return;
    // 함수이름: _applyMessageDeletion.setState callback
    // 함수역할: 연동 사용자 메시지와 복약 관련 첨부의 입력·요청 상태를 `_messages = _mergeMessages(_messages, const [])`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      (scope == ChatDeletionScope.me ? _hiddenMessageIds : _deletedMessageIds)
          .addAll(ids);
      _messages = _mergeMessages(_messages, const []);
      _selectedMessageIds.removeAll(ids);
    });
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
      if (!_selectedMessageIds.remove(id) && _selectedMessageIds.length < 50) {
        _selectedMessageIds.add(id);
      }
    });
  }

  // 함수이름: _confirmMessageDeletion
  // 함수역할: 선택 메시지의 전체 삭제 가능 여부를 확인하고 확정한 개인·공유 범위로 삭제하며 실패 시 선택을 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
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
          // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 대해 `message.canDeleteForEveryone(widget.currentUserHash, DateTime.now())` 조건으로 컬렉션 항목을 판별한다.
          // 매개변수:
          // - message (콜백 계약에서 추론): 현재 작업 결과·오류·상태에 대한 표시 문구.
          // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
          (message) => message.canDeleteForEveryone(
            widget.currentUserHash,
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
        linkId: widget.linkId,
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
  // 함수역할: 레이아웃 완료 후 목록이 연결되어 있으면 220ms 동안 최신 메시지로 스크롤한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _scrollToLatest() {
    // 함수이름: _scrollToLatest.addPostFrameCallback callback
    // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에서 캡처된 작업 `_scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut)`을 실행한다.
    // 매개변수:
    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 연동 사용자 메시지와 복약 관련 첨부 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 연동 사용자 메시지와 복약 관련 첨부에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      appBar: AppBar(
        backgroundColor: MedBuddyColors.primary,
        foregroundColor: Colors.white,
        titleSpacing: 0,
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isSelectingMessages
                  ? _text.selectedCount(_selectedMessageIds.length)
                  : _peerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            Text(
              _connectionLabel,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_showMedicationContextGuide)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                color: const Color(0xFFEAFBF4),
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
            Expanded(child: _buildMessageArea()),
            if (!_isSelectingMessages) _buildComposer(),
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
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      itemCount: _messages.length,
      // 함수이름: _buildMessageArea.itemBuilder callback
      // 함수역할: 연동 사용자 메시지와 복약 관련 첨부에 EdgeInsets.all을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      itemBuilder: (context, index) => GestureDetector(
        // 함수이름: _buildMessageArea.onLongPress callback
        // 함수역할: 전송·삭제 중에는 선택을 막고 메시지 선택을 최대 50개까지 전환한다.
        // 매개변수:
        // - 없음.
        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
        onLongPress: () => _toggleMessageSelection(_messages[index].messageId),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isSelectingMessages)
              Checkbox(
                key: ValueKey(
                  'selectChatMessage-${_messages[index].messageId}',
                ),
                semanticLabel: _text.selectMessage,
                value: _selectedMessageIds.contains(_messages[index].messageId),
                onChanged: _isDeletingMessages
                    ? null
                    // 함수이름: _buildMessageArea.onChanged callback
                    // 함수역할: 전송·삭제 중에는 선택을 막고 메시지 선택을 최대 50개까지 전환한다.
                    // 매개변수:
                    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    : (_) =>
                          _toggleMessageSelection(_messages[index].messageId),
              ),
            Expanded(
              child: _messages[index].deletedForEveryone
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_text.deletedMessage),
                    )
                  : IgnorePointer(
                      ignoring: _isSelectingMessages,
                      child: _MessageBubble(
                        message: _messages[index],
                        isMine:
                            _messages[index].senderHash ==
                            widget.currentUserHash,
                        text: _text,
                        userSetting: widget.userSetting,
                        loadingMedicationId: _loadingMedicationId,
                        onMedicationPressed: _openMedicationDetail,
                        onSchedulePressed: _isPatient
                            ? _openPatientSchedule
                            : null,
                        onPharmacyCallRequested: _callPharmacy,
                        onPharmacyDirectionsRequested: _openPharmacyDirections,
                        // 함수이름: _buildMessageArea.onFindPharmacyRequested callback
                        // 함수역할: 약국 선택 결과를 전화 확인 여부에 맞는 메시지 종류로 공유한다.
                        // 매개변수:
                        // - medication (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
                        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                        onFindPharmacyRequested: (medication) {
                          unawaited(
                            _showPharmacySelector(medications: [medication]),
                          );
                        },
                      ),
                    ),
            ),
          ],
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
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final selectedMedicationCardHeight = (66 + (textScale - 1) * 34)
        .clamp(66.0, 94.0)
        .toDouble();
    return Material(
      color: Colors.white,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              _QuickReplyBar(
                text: _text,
                isPatient: _isPatient,
                enabled: !_isSending,
                onSelected: _sendQuickReply,
              ),
              const SizedBox(height: 8),
            ],
            if (_sendErrorMessage != null) ...[
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton.outlined(
                  key: const ValueKey('chatMedicationSelector'),
                  tooltip: _medicationContexts.isEmpty
                      ? _text.noActiveMedication
                      : _text.selectMedication,
                  onPressed: _medicationContexts.isEmpty || _isSending
                      ? null
                      : _showMedicationSelector,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  icon: const Icon(Icons.medication_outlined),
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  key: const ValueKey('chatScheduleSelector'),
                  tooltip: _text.selectScheduleSlot,
                  onPressed: _scheduleContexts.isEmpty || _isSending
                      ? null
                      : _showScheduleSelector,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  icon: const Icon(Icons.schedule_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: !_isSending,
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
                        borderRadius: BorderRadius.circular(20),
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
          ],
        ),
      ),
    );
  }

  // 함수이름: _connectionLabel
  // 함수역할: 실시간 연결·연결 중·재연결·끊김 상태를 현지화 문구로 변환한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get _connectionLabel {
    return switch (_connectionState) {
      LinkedChatConnectionState.connected => _text.connected,
      LinkedChatConnectionState.connecting => _text.connecting,
      LinkedChatConnectionState.reconnecting => _text.reconnecting,
      LinkedChatConnectionState.disconnected => _text.disconnected,
    };
  }
}

// 클래스명: _ChatQuickReply
// 역할: 빠른 답장 문구와 복약 행동 종류를 담당한다.
// 주요 책임:
// - 빠른 답장 문구와 복약 행동 종류에서 지원하는 선택지를 열거하고 구분한다: taken, cannotNow, shortage, discomfort.
enum _ChatQuickReply { taken, cannotNow, shortage, discomfort }

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

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 채팅에 연결할 복약 일정 요약 선택 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 채팅에 연결할 복약 일정 요약 선택에 쓰는 위젯 트리.
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
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                // 함수이름: build.any callback
                // 함수역할: 채팅에 연결할 복약 일정 요약 선택에 대해 `item.canRequestCheck` 조건으로 컬렉션 항목을 판별한다.
                // 매개변수:
                // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
                // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
                contexts.any((item) => item.canRequestCheck)
                    ? text.scheduleSelectorCaregiverDescription
                    : text.scheduleSelectorPatientDescription,
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
                      borderRadius: BorderRadius.circular(8),
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
                          borderRadius: BorderRadius.circular(8),
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
// - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
// - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _MessageScheduleContext extends StatelessWidget {
  final ChatScheduleContext schedule;
  final bool isMine;
  final _LinkedChatText text;
  final VoidCallback? onPressed;

  // 함수이름: _MessageScheduleContext
  // 함수역할: 메시지에 첨부된 일정 요약에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - schedule (ChatScheduleContext): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _MessageScheduleContext 인스턴스.
  const _MessageScheduleContext({
    required this.schedule,
    required this.isMine,
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
    final foreground = isMine ? Colors.white : MedBuddyColors.textStrong;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMine
                ? Colors.white.withValues(alpha: 0.16)
                : const Color(0xFFEAFBF4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: _ScheduleSummaryContent(
            schedule: schedule,
            text: text,
            foreground: foreground,
            trailing: onPressed == null
                ? null
                : Icon(Icons.chevron_right_rounded, color: foreground),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _ScheduleSummaryContent
// 역할: 약품 수·완료 상태와 시간대별 복약 요약을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약품 수·완료 상태와 시간대별 복약 요약 위젯을 구성한다.
// 속성:
// - schedule (ChatScheduleContext): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// - foreground (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
// - trailing (Widget?): 행 끝에 배치할 보조 콘텐츠.
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

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약품 수·완료 상태와 시간대별 복약 요약 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약품 수·완료 상태와 시간대별 복약 요약에 쓰는 위젯 트리.
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
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
            Text(
              '${schedule.completedCount}/$total',
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w800,
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
// - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
// - onFindPharmacyRequested (VoidCallback): 주변 약국 검색을 여는 콜백.
class _MedicationShortageContext extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final _LinkedChatText text;
  final VoidCallback onFindPharmacyRequested;

  // 함수이름: _MedicationShortageContext
  // 함수역할: 약 부족 알림과 약국 찾기 동작에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - message (ChatMessage): 본문·발신자·시각·읽음 상태·첨부를 담은 메시지.
  // - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - onFindPharmacyRequested (VoidCallback): 주변 약국 검색을 여는 콜백.
  // 반환값: 입력 설정이 반영된 _MedicationShortageContext 인스턴스.
  const _MedicationShortageContext({
    required this.message,
    required this.isMine,
    required this.text,
    required this.onFindPharmacyRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약 부족 알림과 약국 찾기 동작 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약 부족 알림과 약국 찾기 동작에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final foreground = isMine ? Colors.white : MedBuddyColors.textStrong;
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
        OutlinedButton.icon(
          onPressed: onFindPharmacyRequested,
          icon: const Icon(Icons.local_pharmacy_outlined, size: 18),
          label: Text(text.findNearbyPharmacy),
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground,
            side: BorderSide(color: foreground.withValues(alpha: 0.72)),
          ),
        ),
      ],
    );
  }
}

// 클래스명: _MedicationSafetyGuidance
// 역할: 복약 대화의 안전 안내 문구를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 복약 대화의 안전 안내 문구 위젯을 구성한다.
// 속성:
// - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
class _MedicationSafetyGuidance extends StatelessWidget {
  final bool isMine;
  final _LinkedChatText text;

  // 함수이름: _MedicationSafetyGuidance
  // 함수역할: 복약 대화의 안전 안내 문구에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _MedicationSafetyGuidance 인스턴스.
  const _MedicationSafetyGuidance({required this.isMine, required this.text});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 복약 대화의 안전 안내 문구 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 복약 대화의 안전 안내 문구에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final foreground = isMine ? Colors.white : const Color(0xFF8A3B12);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMine
            ? Colors.white.withValues(alpha: 0.15)
            : const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(8),
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
// - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
// - phoneVerified (bool): 사용자가 전화로 운영 여부를 확인했는지 여부.
// - onCallRequested (VoidCallback): 해당 약국으로 전화 연결을 요청할 콜백.
class _MessagePharmacyContext extends StatelessWidget {
  final ChatPharmacyContext pharmacy;
  final bool isMine;
  final bool phoneVerified;
  final _LinkedChatText text;
  final VoidCallback onCallRequested;
  final VoidCallback onDirectionsRequested;

  // 함수이름: _MessagePharmacyContext
  // 함수역할: 메시지에 공유된 약국과 전화 확인 상태에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - pharmacy (ChatPharmacyContext): 표시하거나 전화·길찾기·공유할 약국.
  // - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
  // - phoneVerified (bool): 사용자가 전화로 운영 여부를 확인했는지 여부.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - onCallRequested (VoidCallback): 해당 약국으로 전화 연결을 요청할 콜백.
  // - onDirectionsRequested (VoidCallback): 해당 약국의 길찾기를 요청할 콜백.
  // 반환값: 입력 설정이 반영된 _MessagePharmacyContext 인스턴스.
  const _MessagePharmacyContext({
    required this.pharmacy,
    required this.isMine,
    required this.phoneVerified,
    required this.text,
    required this.onCallRequested,
    required this.onDirectionsRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 메시지에 공유된 약국과 전화 확인 상태 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 메시지에 공유된 약국과 전화 확인 상태에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final foreground = isMine ? Colors.white : MedBuddyColors.textStrong;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMine
            ? Colors.white.withValues(alpha: 0.16)
            : const Color(0xFFEAFBF4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_pharmacy_outlined, color: foreground, size: 22),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  pharmacy.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          if (pharmacy.todayHours.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              pharmacy.todayHours,
              style: TextStyle(
                color: foreground.withValues(alpha: 0.84),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
          if (pharmacy.address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              pharmacy.address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground.withValues(alpha: 0.78),
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w500,
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
                fontSize: 11,
                fontWeight: FontWeight.w800,
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
                  label: Text(text.call),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: foreground,
                    side: BorderSide(color: foreground.withValues(alpha: 0.72)),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDirectionsRequested,
                  icon: const Icon(Icons.directions_outlined, size: 17),
                  label: Text(text.directions),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: foreground,
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
        color: const Color(0xFFEAFBF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB8F0D8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
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
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                          if (medication.dosagePerTime.isNotEmpty)
                            Text(
                              text.dose(medication.dosagePerTime),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MedBuddyColors.textMuted,
                                fontSize: 12,
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
// - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
// - isLoading (bool): 진행 중 표시를 보여줄지 여부.
// - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _MessageMedicationContext extends StatelessWidget {
  final ChatMedicationContext medication;
  final bool isMine;
  final bool isLoading;
  final _LinkedChatText text;
  final VoidCallback? onPressed;

  // 함수이름: _MessageMedicationContext
  // 함수역할: 메시지에 첨부된 약품 상세 진입에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medication (ChatMedicationContext): 표시·변환·저장·비교할 약품 데이터.
  // - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
  // - isLoading (bool): 진행 중 표시를 보여줄지 여부.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _MessageMedicationContext 인스턴스.
  const _MessageMedicationContext({
    required this.medication,
    required this.isMine,
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
    final foreground = isMine ? Colors.white : MedBuddyColors.textStrong;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isMine
                ? Colors.white.withValues(alpha: 0.16)
                : const Color(0xFFEAFBF4),
            borderRadius: BorderRadius.circular(10),
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
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
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
                          fontSize: 11,
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

// 클래스명: _MedicationThumbnail
// 역할: 약품 사진과 사진 부재·불러오기 실패 대체 표시를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약품 사진과 사진 부재·불러오기 실패 대체 표시 위젯을 구성한다.
// 속성:
// - imageUrl (String): 검증 후 사용할 약품 이미지 네트워크 URL.
// - size (double): 위젯 또는 캔버스의 표시 크기.
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

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약품 사진과 사진 부재·불러오기 실패 대체 표시 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약품 사진과 사진 부재·불러오기 실패 대체 표시에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.medication_outlined,
        color: MedBuddyColors.textMuted,
        size: size * 0.52,
      ),
    );
    if (imageUrl.trim().isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.contain,
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
  final ValueChanged<ChatScheduleContext>? onSchedulePressed;
  final ValueChanged<ChatPharmacyContext> onPharmacyCallRequested;
  final ValueChanged<ChatPharmacyContext> onPharmacyDirectionsRequested;
  final ValueChanged<ChatMedicationContext> onFindPharmacyRequested;

  // 함수이름: _MessageBubble
  // 함수역할: 발신자 구분·메시지 시각·텍스트·첨부 본문에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - message (ChatMessage): 본문·발신자·시각·읽음 상태·첨부를 담은 메시지.
  // - isMine (bool): 현재 사용자가 보낸 메시지인지 여부.
  // - loadingMedicationId (int?): 현재 개별 복약 상태를 갱신하는 약품 ID.
  // - text (_LinkedChatText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - onMedicationPressed (ValueChanged<ChatMedicationContext>): 대상 약품의 상세 정보 또는 복용 가이드를 여는 콜백.
  // - onSchedulePressed (ValueChanged<ChatScheduleContext>?): 오늘 복약 일정 화면을 여는 콜백.
  // - onPharmacyCallRequested (ValueChanged<ChatPharmacyContext>): 해당 약국으로 전화 연결을 요청할 콜백.
  // - onPharmacyDirectionsRequested (ValueChanged<ChatPharmacyContext>): 해당 약국의 길찾기를 요청할 콜백.
  // - onFindPharmacyRequested (ValueChanged<ChatMedicationContext>): 주변 약국 검색을 여는 콜백.
  // 반환값: 입력 설정이 반영된 _MessageBubble 인스턴스.
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.loadingMedicationId,
    required this.text,
    required this.userSetting,
    required this.onMedicationPressed,
    required this.onSchedulePressed,
    required this.onPharmacyCallRequested,
    required this.onPharmacyDirectionsRequested,
    required this.onFindPharmacyRequested,
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
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.76,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: isMine ? MedBuddyColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isMine
              ? null
              : Border.all(color: MedBuddyColors.outline, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final medication in message.attachedMedicationContexts) ...[
              _MessageMedicationContext(
                medication: medication,
                isMine: isMine,
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
            if (message.scheduleContext != null) ...[
              _MessageScheduleContext(
                schedule: message.scheduleContext!,
                isMine: isMine,
                text: text,
                onPressed: onSchedulePressed == null
                    ? null
                    // 함수이름: build.onPressed callback
                    // 함수역할: 발신자 구분·메시지 시각·텍스트·첨부 본문의 캡처된 상태에서 `onSchedulePressed!(message.scheduleContext!)` 값을 제공한다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: `onSchedulePressed!(message.scheduleContext!)`의 값.
                    : () => onSchedulePressed!(message.scheduleContext!),
              ),
              const SizedBox(height: 8),
            ],
            if (message.pharmacyContext != null) ...[
              _MessagePharmacyContext(
                pharmacy: message.pharmacyContext!,
                isMine: isMine,
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
              ),
              const SizedBox(height: 8),
            ],
            if (message.messageKind == ChatMessageKind.medicationShortage &&
                message.attachedMedicationContexts.isNotEmpty) ...[
              _MedicationShortageContext(
                message: message,
                isMine: isMine,
                text: text,
                // 함수이름: build.onFindPharmacyRequested callback
                // 함수역할: 발신자 구분·메시지 시각·텍스트·첨부 본문에서 캡처된 작업 `onFindPharmacyRequested(message.attachedMedicationContexts.first)`을 실행한다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onFindPharmacyRequested: () => onFindPharmacyRequested(
                  message.attachedMedicationContexts.first,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message.body,
              style: TextStyle(
                color: isMine ? Colors.white : const Color(0xFF111827),
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
            if (message.showSafetyGuidance) ...[
              const SizedBox(height: 8),
              _MedicationSafetyGuidance(isMine: isMine, text: text),
            ],
            const SizedBox(height: 4),
            Text(
              isMine && message.readAt != null
                  ? text.readAt(timeLabel)
                  : timeLabel,
              style: TextStyle(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.78)
                    : MedBuddyColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 클래스명: _LinkedChatText
// 역할: 연동 사용자 채팅과 약품·일정·약국 정보 공유에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 연동 사용자 채팅과 약품·일정·약국 정보 공유에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _LinkedChatText {
  final String language;

  // 함수이름: _LinkedChatText
  // 함수역할: 연동 사용자 채팅과 약품·일정·약국 정보 공유에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _LinkedChatText 인스턴스.
  const _LinkedChatText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두어로 영어 여부를 판별한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

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
  // 함수이름: noActiveMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 중인 약이 없습니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noActiveMedication =>
      isEnglish ? 'No active medications' : '복용 중인 약이 없습니다';
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

  // 함수이름: selectScheduleSlot
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 시간대 공유" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get selectScheduleSlot =>
      isEnglish ? 'Share a medication time' : '복약 시간대 공유';
  // 함수이름: noScheduleContext
  // 함수역할: 현재 언어와 입력값에 맞춰 "오늘 확인할 복약 일정이 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noScheduleContext => isEnglish
      ? 'There is no active medication schedule today.'
      : '오늘 확인할 복약 일정이 없습니다.';
  // 함수이름: onlyCaregiverCanRequest
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 확인 요청은 연결된 보호자만 보낼 수 있습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get onlyCaregiverCanRequest => isEnglish
      ? 'Only the linked caregiver can send a check request.'
      : '복약 확인 요청은 연결된 보호자만 보낼 수 있습니다.';
  // 함수이름: scheduleSelectorTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "오늘의 복약 시간대" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get scheduleSelectorTitle =>
      isEnglish ? 'Today\'s medication times' : '오늘의 복약 시간대';
  // 함수이름: scheduleSelectorCaregiverDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "확인이 필요한 시간대를 선택해 환자에게 알려주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get scheduleSelectorCaregiverDescription => isEnglish
      ? 'Choose a time to ask the patient to check their medication.'
      : '확인이 필요한 시간대를 선택해 환자에게 알려주세요.';
  // 함수이름: scheduleSelectorPatientDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "시간대별 약과 복용 진행률을 확인할 수 있습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get scheduleSelectorPatientDescription => isEnglish
      ? 'Review progress for each medication time.'
      : '시간대별 약과 복용 진행률을 확인할 수 있습니다.';
  // 함수이름: slotLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "취침 전" 문구를 제공한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String slotLabel(String slotKey) {
    return switch (slotKey) {
      'morning' => isEnglish ? 'Morning' : '아침',
      'lunch' => isEnglish ? 'Lunch' : '점심',
      'evening' => isEnglish ? 'Evening' : '저녁',
      'bedtime' => isEnglish ? 'Bedtime' : '취침 전',
      _ => isEnglish ? 'Medication' : '복약',
    };
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
  // 함수이름: remainingCourse
  // 함수역할: 현재 언어와 입력값에 맞춰 "남은 복용 기간을 계산하지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - days (int?): 복용 기간의 일수 또는 이를 표현한 원본 문구.
  // - endDate (DateTime?): 복용 기간의 마지막 날짜.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String remainingCourse(int? days, DateTime? endDate) {
    if (days == null || endDate == null) {
      return isEnglish
          ? 'The remaining course could not be calculated.'
          : '남은 복용 기간을 계산하지 못했습니다.';
    }
    final dateLabel =
        '${endDate.year}.${endDate.month.toString().padLeft(2, '0')}.${endDate.day.toString().padLeft(2, '0')}';
    return isEnglish
        ? '$days day(s) remaining · through $dateLabel'
        : '남은 복용 기간 $days일 · $dateLabel까지';
  }

  // 함수이름: findNearbyPharmacy
  // 함수역할: 현재 언어와 입력값에 맞춰 "근처 운영 약국 찾기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get findNearbyPharmacy =>
      isEnglish ? 'Find nearby pharmacies' : '근처 운영 약국 찾기';
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
  // 함수이름: readAt
  // 함수역할: 현재 언어와 입력값에 맞춰 "$timeLabel · 읽음" 문구를 제공한다.
  // 매개변수:
  // - timeLabel (String): 시간대 또는 알림 시각의 표시 문구.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String readAt(String timeLabel) =>
      isEnglish ? '$timeLabel · Read' : '$timeLabel · 읽음';
}
