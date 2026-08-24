// 파일명: linked_chat_ui_boundary.dart
// 역할: 연동된 환자와 보호자가 문자 메시지를 주고받는 채팅 화면을 제공한다.

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

  @override
  State<LinkedChatUI> createState() => _LinkedChatUIState();
}

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
  String? _pendingClientMessageId;
  String? _pendingMessageBody;
  String? _pendingMedicationIdsSignature;
  ChatMessageKind _pendingMessageKind = ChatMessageKind.text;
  String? _pendingSlotKey;
  String? _pendingPharmacyId;
  int? _loadingMedicationId;
  int _requestGeneration = 0;
  bool _showMedicationContextGuide = true;

  _LinkedChatText get _text => _LinkedChatText(widget.userSetting.language);

  bool get _isPatient =>
      widget.patientHash.isNotEmpty &&
      widget.currentUserHash == widget.patientHash;

  String get _peerName {
    if (_text.isEnglish && widget.peerName == '가족') {
      return _text.family;
    }
    return widget.peerName;
  }

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
    _stateSubscription = _realtimeService.states.listen((state) {
      if (mounted) {
        setState(() => _connectionState = state);
      }
    });
    _medicationContextGuideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showMedicationContextGuide = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeChat());
    });
  }

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
    _fallbackRefreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(_refreshMessages(showLoading: false));
    });
  }

  // 함수명: _refreshMedicationContexts
  // 역할:
  // - 현재 연동 환자의 활성 복약정보를 불러와 메시지에 연결할 수 있게 한다.
  Future<void> _refreshMedicationContexts() async {
    final generation = _requestGeneration;
    try {
      final medications = await _control.requestMedicationContexts(
        linkId: widget.linkId,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _medicationContexts = medications;
        final selectedIds = _selectedMedicationContexts
            .map((item) => item.medicationId)
            .toSet();
        _selectedMedicationContexts = medications
            .where((item) => selectedIds.contains(item.medicationId))
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        if (_medicationContexts.isEmpty) {
          _sendErrorMessage = _text.medicationLoadFailed;
        }
      });
    }
  }

  // 함수명: _refreshScheduleContexts
  // 역할:
  // - 채팅에서 공유하거나 확인 요청할 오늘 복약 시간대 상태를 갱신한다.
  Future<void> _refreshScheduleContexts() async {
    final generation = _requestGeneration;
    try {
      final contexts = await _control.requestScheduleContexts(
        linkId: widget.linkId,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() => _scheduleContexts = contexts);
    } catch (_) {
      // 채팅 자체는 계속 사용할 수 있으므로 시간대 카드 실패는 조용히 보완 조회한다.
    }
  }

  // 함수명: _refreshMessages
  // 역할:
  // - 최초 기록과 WebSocket 누락 가능성이 있는 메시지를 REST 조회로 보완한다.
  Future<void> _refreshMessages({required bool showLoading}) async {
    final generation = _requestGeneration;
    if (showLoading && mounted) {
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
      setState(() {
        _isLoading = false;
        if (_messages.isEmpty) {
          _errorMessage = _text.historyLoadFailed;
        }
      });
    }
  }

  void _handleRealtimeEvent(Map<String, dynamic> event) {
    if (!mounted) {
      return;
    }
    final type = event['type']?.toString();
    if (type == 'chat_message') {
      final rawMessage = event['message'];
      if (rawMessage is! Map) {
        return;
      }
      try {
        final message = ChatMessage.fromJson(
          Map<String, dynamic>.from(rawMessage),
        );
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
      setState(() {
        _messages = _messages
            .map(
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

  Future<void> _markLatestIncomingRead() async {
    final incoming = _messages
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

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    await _submitMessage(
      body: body,
      medications: _selectedMedicationContexts,
      clearComposer: true,
      clearMedicationSelection: true,
    );
  }

  // 함수명: _submitMessage
  // 역할:
  // - 일반 문장과 구조화된 복약·약국 메시지의 전송, 재시도와 화면 갱신을 한곳에서 처리한다.
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
    if (_isSending || normalizedBody.isEmpty) {
      return null;
    }
    FocusScope.of(context).unfocus();
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
      setState(() {
        _sendErrorMessage = _text.sendFailed;
      });
      return null;
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _clearPendingRequest() {
    _pendingClientMessageId = null;
    _pendingMessageBody = null;
    _pendingMedicationIdsSignature = null;
    _pendingMessageKind = ChatMessageKind.text;
    _pendingSlotKey = null;
    _pendingPharmacyId = null;
  }

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

  Future<void> _showPharmacySelector({
    List<ChatMedicationContext> medications = const [],
  }) async {
    if (_isSending) {
      return;
    }
    final selection = await Navigator.of(context).push<NearbyPharmacySelection>(
      MaterialPageRoute(
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
      setState(() => _selectedMedicationContexts = const []);
    }
  }

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

  // 함수명: _showMedicationSelector
  // 역할:
  // - 현재 환자가 복용 중인 약을 사진과 함께 보여주고 대화 대상을 선택한다.
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
        builder: (context) => CheckScheduleUI.selection(
          schedules: selectionSchedules,
          language: widget.userSetting.language,
          selectedMedicationIds: _selectedMedicationContexts
              .map((item) => item.medicationId.toString())
              .toSet(),
        ),
      ),
    );
    if (selectedSchedules == null || !mounted) {
      return;
    }
    final selected = selectedSchedules
        .map((item) => medicationsById[int.tryParse(item.medicationID)])
        .whereType<ChatMedicationContext>()
        .toList(growable: false);
    setState(() {
      _selectedMedicationContexts = selected;
      _sendErrorMessage = null;
      _clearPendingRequest();
    });
  }

  String _suggestedMessage(List<ChatMedicationContext> medications) {
    final medicationNames = medications
        .map((item) => item.medicationName)
        .join(', ');
    if (_isPatient) {
      return _text.patientSuggestedMessage(medicationNames);
    }
    return _text.caregiverSuggestedMessage(_peerName, medicationNames);
  }

  // 함수명: _openPatientSchedule
  // 역할: 환자가 채팅의 시간대 카드를 누르면 같은 시간대가 보이는 오늘 일정으로 이동한다.
  Future<void> _openPatientSchedule(ChatScheduleContext schedule) async {
    if (!_isPatient) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CheckScheduleUI(initialSlotKey: schedule.slotKey),
      ),
    );
  }

  String _medicationIdsSignature(List<ChatMedicationContext> medications) {
    final ids = medications.map((item) => item.medicationId).toList()..sort();
    return ids.join(',');
  }

  // 함수명: _openMedicationDetail
  // 역할:
  // - 채팅 약 카드를 누르면 서버에서 권한이 확인된 상세정보를 불러와 공통 화면으로 연다.
  Future<void> _openMedicationDetail(ChatMedicationContext medication) async {
    if (_loadingMedicationId != null) {
      return;
    }
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
      setState(() => _loadingMedicationId = null);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
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
      setState(() => _loadingMedicationId = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_text.medicationDetailLoadFailed)));
    }
  }

  String _createClientMessageId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomPart = _random.nextInt(0x7fffffff).toRadixString(16);
    return 'msg_${timestamp}_$randomPart';
  }

  List<ChatMessage> _mergeMessages(
    List<ChatMessage> current,
    List<ChatMessage> incoming,
  ) {
    final byId = <int, ChatMessage>{
      for (final message in current) message.messageId: message,
      for (final message in incoming) message.messageId: message,
    };
    final merged = byId.values.toList(growable: false)
      ..sort((left, right) => left.messageId.compareTo(right.messageId));
    return merged;
  }

  void _scrollToLatest() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      appBar: AppBar(
        backgroundColor: MedBuddyColors.primary,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _peerName,
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
            _buildComposer(),
          ],
        ),
      ),
    );
  }

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
      itemBuilder: (context, index) => _MessageBubble(
        message: _messages[index],
        isMine: _messages[index].senderHash == widget.currentUserHash,
        text: _text,
        loadingMedicationId: _loadingMedicationId,
        onMedicationPressed: _openMedicationDetail,
        onSchedulePressed: _isPatient ? _openPatientSchedule : null,
        onPharmacyCallRequested: _callPharmacy,
        onPharmacyDirectionsRequested: _openPharmacyDirections,
        onFindPharmacyRequested: (medication) {
          unawaited(_showPharmacySelector(medications: [medication]));
        },
      ),
    );
  }

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
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
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
                            ? () => _openMedicationDetail(medication)
                            : null,
                        onRemoveRequested: _isSending
                            ? null
                            : () => setState(() {
                                _selectedMedicationContexts =
                                    _selectedMedicationContexts
                                        .where(
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

  String get _connectionLabel {
    return switch (_connectionState) {
      LinkedChatConnectionState.connected => _text.connected,
      LinkedChatConnectionState.connecting => _text.connecting,
      LinkedChatConnectionState.reconnecting => _text.reconnecting,
      LinkedChatConnectionState.disconnected => _text.disconnected,
    };
  }
}

enum _ChatQuickReply { taken, cannotNow, shortage, discomfort }

class _QuickReplyBar extends StatelessWidget {
  final _LinkedChatText text;
  final bool isPatient;
  final bool enabled;
  final ValueChanged<_ChatQuickReply> onSelected;

  const _QuickReplyBar({
    required this.text,
    required this.isPatient,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _ChatQuickReply.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final reply = _ChatQuickReply.values[index];
          return ActionChip(
            tooltip: text.quickReplyLabel(reply, isPatient: isPatient),
            avatar: Icon(text.quickReplyIcon(reply), size: 17),
            label: Text(text.quickReplyLabel(reply, isPatient: isPatient)),
            onPressed: enabled ? () => onSelected(reply) : null,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}

class _ScheduleContextSelector extends StatelessWidget {
  final List<ChatScheduleContext> contexts;
  final _LinkedChatText text;

  const _ScheduleContextSelector({required this.contexts, required this.text});

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
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final schedule = contexts[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
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

class _MessageScheduleContext extends StatelessWidget {
  final ChatScheduleContext schedule;
  final bool isMine;
  final _LinkedChatText text;
  final VoidCallback? onPressed;

  const _MessageScheduleContext({
    required this.schedule,
    required this.isMine,
    required this.text,
    this.onPressed,
  });

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

class _ScheduleSummaryContent extends StatelessWidget {
  final ChatScheduleContext schedule;
  final _LinkedChatText text;
  final Color foreground;
  final Widget? trailing;

  const _ScheduleSummaryContent({
    required this.schedule,
    required this.text,
    required this.foreground,
    this.trailing,
  });

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

class _MedicationShortageContext extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final _LinkedChatText text;
  final VoidCallback onFindPharmacyRequested;

  const _MedicationShortageContext({
    required this.message,
    required this.isMine,
    required this.text,
    required this.onFindPharmacyRequested,
  });

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

class _MedicationSafetyGuidance extends StatelessWidget {
  final bool isMine;
  final _LinkedChatText text;

  const _MedicationSafetyGuidance({required this.isMine, required this.text});

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

class _MessagePharmacyContext extends StatelessWidget {
  final ChatPharmacyContext pharmacy;
  final bool isMine;
  final bool phoneVerified;
  final _LinkedChatText text;
  final VoidCallback onCallRequested;
  final VoidCallback onDirectionsRequested;

  const _MessagePharmacyContext({
    required this.pharmacy,
    required this.isMine,
    required this.phoneVerified,
    required this.text,
    required this.onCallRequested,
    required this.onDirectionsRequested,
  });

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

class _SelectedMedicationContext extends StatelessWidget {
  final ChatMedicationContext medication;
  final _LinkedChatText text;
  final bool isLoading;
  final VoidCallback? onOpenRequested;
  final VoidCallback? onRemoveRequested;

  const _SelectedMedicationContext({
    required this.medication,
    required this.text,
    required this.isLoading,
    required this.onOpenRequested,
    required this.onRemoveRequested,
  });

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

class _MessageMedicationContext extends StatelessWidget {
  final ChatMedicationContext medication;
  final bool isMine;
  final bool isLoading;
  final _LinkedChatText text;
  final VoidCallback? onPressed;

  const _MessageMedicationContext({
    required this.medication,
    required this.isMine,
    required this.isLoading,
    required this.text,
    required this.onPressed,
  });

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

class _MedicationThumbnail extends StatelessWidget {
  final String imageUrl;
  final double size;

  const _MedicationThumbnail({required this.imageUrl, required this.size});

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
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final int? loadingMedicationId;
  final _LinkedChatText text;
  final ValueChanged<ChatMedicationContext> onMedicationPressed;
  final ValueChanged<ChatScheduleContext>? onSchedulePressed;
  final ValueChanged<ChatPharmacyContext> onPharmacyCallRequested;
  final ValueChanged<ChatPharmacyContext> onPharmacyDirectionsRequested;
  final ValueChanged<ChatMedicationContext> onFindPharmacyRequested;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.loadingMedicationId,
    required this.text,
    required this.onMedicationPressed,
    required this.onSchedulePressed,
    required this.onPharmacyCallRequested,
    required this.onPharmacyDirectionsRequested,
    required this.onFindPharmacyRequested,
  });

  @override
  Widget build(BuildContext context) {
    final localTime = message.createdAt.toLocal();
    final timeLabel =
        '${localTime.hour.toString().padLeft(2, '0')}:'
        '${localTime.minute.toString().padLeft(2, '0')}';
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
                onCallRequested: () =>
                    onPharmacyCallRequested(message.pharmacyContext!),
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
// 역할: 복약 대화 화면의 사용자 문구를 설정 언어에 맞게 제공한다.
class _LinkedChatText {
  final String language;

  const _LinkedChatText(this.language);

  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  String get family => isEnglish ? 'Family' : '가족';
  String get medicationLoadFailed => isEnglish
      ? 'Could not load active medication information.'
      : '복용 중인 약 정보를 불러오지 못했습니다.';
  String get medicationDetailLoadFailed => isEnglish
      ? 'Could not load the medication details.'
      : '약 상세정보를 불러오지 못했습니다.';
  String get historyLoadFailed =>
      isEnglish ? 'Could not load the conversation.' : '대화 내용을 불러오지 못했습니다.';
  String get sendFailed => isEnglish
      ? 'Could not send the message. Tap send again.'
      : '메시지를 보내지 못했습니다. 다시 눌러주세요.';
  String dose(String value) => isEnglish ? 'Dose: $value' : '1회 $value';
  String patientSuggestedMessage(String medicationName) => isEnglish
      ? 'I finished taking $medicationName.'
      : '$medicationName 복용을 완료했어요.';
  String caregiverSuggestedMessage(String peerName, String medicationName) =>
      isEnglish
      ? '$peerName, have you taken $medicationName yet?'
      : '$peerName님, $medicationName 아직 안 드셨나요?';
  String exampleMessage(String value) =>
      isEnglish ? 'Example: $value' : '예: $value';
  String get medicationContextGuide => isEnglish
      ? 'Choose a medication to include its photo and dose with the message.'
      : '대화할 약을 선택하면 사진과 복용량이 메시지에 함께 표시됩니다.';
  String get retry => isEnglish ? 'Try again' : '다시 시도';
  String get emptyConversation => isEnglish
      ? 'No messages yet.\nSend a message to start the conversation.'
      : '아직 대화가 없습니다.\n메시지를 보내 대화를 시작해보세요.';
  String get noActiveMedication =>
      isEnglish ? 'No active medications' : '복용 중인 약이 없습니다';
  String get selectMedication => isEnglish ? 'Choose medication' : '대화할 약 선택';
  String get sendMessage => isEnglish ? 'Send message' : '메시지 보내기';
  String get connected => isEnglish ? 'Live connection' : '실시간 연결됨';
  String get connecting => isEnglish ? 'Connecting' : '연결 중';
  String get reconnecting => isEnglish ? 'Reconnecting' : '다시 연결 중';
  String get disconnected => isEnglish ? 'Disconnected' : '연결 끊김';
  String get clearSelectedMedication =>
      isEnglish ? 'Clear selected medication' : '선택한 약 해제';
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

  IconData quickReplyIcon(_ChatQuickReply reply) {
    return switch (reply) {
      _ChatQuickReply.taken => Icons.check_circle_outline_rounded,
      _ChatQuickReply.cannotNow => Icons.schedule_rounded,
      _ChatQuickReply.shortage => Icons.medication_liquid_outlined,
      _ChatQuickReply.discomfort => Icons.health_and_safety_outlined,
    };
  }

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

  String get selectScheduleSlot =>
      isEnglish ? 'Share a medication time' : '복약 시간대 공유';
  String get noScheduleContext => isEnglish
      ? 'There is no active medication schedule today.'
      : '오늘 확인할 복약 일정이 없습니다.';
  String get onlyCaregiverCanRequest => isEnglish
      ? 'Only the linked caregiver can send a check request.'
      : '복약 확인 요청은 연결된 보호자만 보낼 수 있습니다.';
  String get scheduleSelectorTitle =>
      isEnglish ? 'Today\'s medication times' : '오늘의 복약 시간대';
  String get scheduleSelectorCaregiverDescription => isEnglish
      ? 'Choose a time to ask the patient to check their medication.'
      : '확인이 필요한 시간대를 선택해 환자에게 알려주세요.';
  String get scheduleSelectorPatientDescription => isEnglish
      ? 'Review progress for each medication time.'
      : '시간대별 약과 복용 진행률을 확인할 수 있습니다.';
  String slotLabel(String slotKey) {
    return switch (slotKey) {
      'morning' => isEnglish ? 'Morning' : '아침',
      'lunch' => isEnglish ? 'Lunch' : '점심',
      'evening' => isEnglish ? 'Evening' : '저녁',
      'bedtime' => isEnglish ? 'Bedtime' : '취침 전',
      _ => isEnglish ? 'Medication' : '복약',
    };
  }

  IconData slotIcon(String slotKey) {
    return switch (slotKey) {
      'morning' => Icons.wb_sunny_outlined,
      'lunch' => Icons.local_cafe_outlined,
      'evening' => Icons.wb_twilight_outlined,
      'bedtime' => Icons.nightlight_round,
      _ => Icons.schedule_rounded,
    };
  }

  String slotCheckRequestBody(String slotKey) => isEnglish
      ? 'Please check your ${slotLabel(slotKey).toLowerCase()} medication.'
      : '${slotLabel(slotKey)} 복약을 확인해주세요.';
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

  String get findNearbyPharmacy =>
      isEnglish ? 'Find nearby pharmacies' : '근처 운영 약국 찾기';
  String pharmacyShareBody(String pharmacyName) =>
      isEnglish ? 'I am sharing $pharmacyName.' : '$pharmacyName 정보를 공유했어요.';
  String pharmacyPhoneVerifiedBody(String pharmacyName) => isEnglish
      ? 'I called $pharmacyName and confirmed availability.'
      : '$pharmacyName에 전화해 운영 여부를 확인했어요.';
  String get phoneVerified =>
      isEnglish ? 'Availability confirmed by phone' : '전화 확인 완료';
  String get call => isEnglish ? 'Call' : '전화';
  String get directions => isEnglish ? 'Directions' : '길찾기';
  String get phoneUnavailable => isEnglish
      ? 'This pharmacy does not have a callable number.'
      : '연결할 수 있는 약국 전화번호가 없습니다.';
  String get directionsUnavailable =>
      isEnglish ? 'Could not open directions.' : '길찾기를 열지 못했습니다.';
  String get discomfortSafetyGuidance => isEnglish
      ? 'This chat cannot diagnose symptoms. If symptoms are severe, breathing is difficult, or consciousness changes, call emergency services. Otherwise, contact a medical professional or pharmacist before changing how you take the medicine.'
      : '채팅만으로 증상을 판단할 수 없습니다. 증상이 심하거나 호흡 곤란·의식 변화가 있으면 즉시 119에 연락하고, 임의로 복용법을 바꾸기 전에 의료진이나 약사에게 상담하세요.';
  String readAt(String timeLabel) =>
      isEnglish ? '$timeLabel · Read' : '$timeLabel · 읽음';
}
