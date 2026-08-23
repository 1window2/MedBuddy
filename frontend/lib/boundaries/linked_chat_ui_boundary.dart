// 파일명: linked_chat_ui_boundary.dart
// 역할: 연동된 환자와 보호자가 문자 메시지를 주고받는 채팅 화면을 제공한다.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../controls/manage_linked_chat_control.dart';
import '../entities/chat_message_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/authenticated_api_client.dart';
import '../services/linked_chat_realtime_service.dart';
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

  late final AuthenticatedApiClient _apiClient;
  late final ManageLinkedChat _control;
  late final LinkedChatRealtimeService _realtimeService;
  late final bool _ownsApiClient;
  late final bool _ownsControl;
  late final bool _ownsRealtimeService;

  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  StreamSubscription<LinkedChatConnectionState>? _stateSubscription;
  Timer? _fallbackRefreshTimer;
  List<ChatMessage> _messages = const [];
  List<ChatMedicationContext> _medicationContexts = const [];
  ChatMedicationContext? _selectedMedicationContext;
  LinkedChatConnectionState _connectionState =
      LinkedChatConnectionState.connecting;
  String? _errorMessage;
  String? _sendErrorMessage;
  bool _isLoading = true;
  bool _isSending = false;
  String? _pendingClientMessageId;
  String? _pendingMessageBody;
  int? _pendingMedicationId;
  int _requestGeneration = 0;

  _LinkedChatText get _text => _LinkedChatText(widget.userSetting.language);

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeChat());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requestGeneration += 1;
    _fallbackRefreshTimer?.cancel();
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
        final selectedId = _selectedMedicationContext?.medicationId;
        _selectedMedicationContext = _findMedicationContext(
          medications,
          selectedId,
        );
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

  ChatMedicationContext? _findMedicationContext(
    List<ChatMedicationContext> medications,
    int? medicationId,
  ) {
    if (medicationId == null) {
      return null;
    }
    for (final medication in medications) {
      if (medication.medicationId == medicationId) {
        return medication;
      }
    }
    return null;
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
    if (_isSending) {
      return;
    }
    final body = _messageController.text.trim();
    final medication = _selectedMedicationContext;
    if (body.isEmpty || medication == null) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isSending = true;
      _sendErrorMessage = null;
    });
    final canReusePendingRequest =
        _pendingMessageBody == body &&
        _pendingMedicationId == medication.medicationId;
    final clientMessageId = canReusePendingRequest
        ? _pendingClientMessageId ?? _createClientMessageId()
        : _createClientMessageId();
    _pendingClientMessageId = clientMessageId;
    _pendingMessageBody = body;
    _pendingMedicationId = medication.medicationId;
    try {
      final message = await _control.sendMessage(
        linkId: widget.linkId,
        clientMessageId: clientMessageId,
        body: body,
        medicationId: medication.medicationId,
      );
      if (!mounted) {
        return;
      }
      _messageController.clear();
      _pendingClientMessageId = null;
      _pendingMessageBody = null;
      _pendingMedicationId = null;
      setState(() {
        _selectedMedicationContext = null;
        _messages = _mergeMessages(_messages, [message]);
        _errorMessage = null;
        _sendErrorMessage = null;
      });
      _scrollToLatest();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sendErrorMessage = _text.sendFailed;
      });
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  // 함수명: _showMedicationSelector
  // 역할:
  // - 현재 환자가 복용 중인 약을 사진과 함께 보여주고 대화 대상을 선택한다.
  Future<void> _showMedicationSelector() async {
    if (_medicationContexts.isEmpty || _isSending) {
      return;
    }
    final selected = await showModalBottomSheet<ChatMedicationContext>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
                child: Text(
                  _text.chooseMedication,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                  itemCount: _medicationContexts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final medication = _medicationContexts[index];
                    return ListTile(
                      key: ValueKey(
                        'chatMedicationOption_${medication.medicationId}',
                      ),
                      minVerticalPadding: 10,
                      leading: _MedicationThumbnail(
                        imageUrl: medication.imageUrl,
                        size: 52,
                      ),
                      title: Text(
                        medication.medicationName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MedBuddyColors.textStrong,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      subtitle: medication.dosagePerTime.isEmpty
                          ? null
                          : Text(
                              _text.dose(medication.dosagePerTime),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(context, medication),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _selectedMedicationContext = selected;
      _sendErrorMessage = null;
      if (_messageController.text.trim().isEmpty) {
        _messageController.text = _suggestedMessage(selected);
        _messageController.selection = TextSelection.collapsed(
          offset: _messageController.text.length,
        );
      }
    });
  }

  String _suggestedMessage(ChatMedicationContext medication) {
    if (widget.patientHash.isNotEmpty &&
        widget.currentUserHash == widget.patientHash) {
      return _text.patientSuggestedMessage(medication.medicationName);
    }
    return _text.caregiverSuggestedMessage(
      _peerName,
      medication.medicationName,
    );
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
      ),
    );
  }

  Widget _buildComposer() {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedMedicationContext != null) ...[
              _SelectedMedicationContext(
                medication: _selectedMedicationContext!,
                text: _text,
                onRemoveRequested: _isSending
                    ? null
                    : () => setState(() {
                        _selectedMedicationContext = null;
                        _pendingClientMessageId = null;
                        _pendingMessageBody = null;
                        _pendingMedicationId = null;
                      }),
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
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: _medicationContexts.isNotEmpty && !_isSending,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 500,
                    textInputAction: TextInputAction.newline,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: _medicationContexts.isEmpty
                          ? _text.noActiveMedication
                          : _selectedMedicationContext == null
                          ? _text.selectMedicationFirst
                          : _text.enterMessage,
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
                  tooltip: _text.sendMessage,
                  onPressed:
                      !_isSending &&
                          _selectedMedicationContext != null &&
                          _messageController.text.trim().isNotEmpty
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

class _SelectedMedicationContext extends StatelessWidget {
  final ChatMedicationContext medication;
  final _LinkedChatText text;
  final VoidCallback? onRemoveRequested;

  const _SelectedMedicationContext({
    required this.medication,
    required this.text,
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
          _MedicationThumbnail(imageUrl: medication.imageUrl, size: 42),
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
  final _LinkedChatText text;

  const _MessageMedicationContext({
    required this.medication,
    required this.isMine,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = isMine ? Colors.white : MedBuddyColors.textStrong;
    return Container(
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
        ],
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
  final _LinkedChatText text;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.text,
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
            if (message.medicationContext != null) ...[
              _MessageMedicationContext(
                medication: message.medicationContext!,
                isMine: isMine,
                text: text,
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
  String get historyLoadFailed =>
      isEnglish ? 'Could not load the conversation.' : '대화 내용을 불러오지 못했습니다.';
  String get sendFailed => isEnglish
      ? 'Could not send the message. Tap send again.'
      : '메시지를 보내지 못했습니다. 다시 눌러주세요.';
  String get chooseMedication =>
      isEnglish ? 'Choose a medication to discuss' : '대화할 약을 선택하세요';
  String dose(String value) => isEnglish ? 'Dose: $value' : '1회 $value';
  String patientSuggestedMessage(String medicationName) => isEnglish
      ? 'I finished taking $medicationName.'
      : '$medicationName 복용을 완료했어요.';
  String caregiverSuggestedMessage(String peerName, String medicationName) =>
      isEnglish
      ? '$peerName, have you taken $medicationName yet?'
      : '$peerName님, $medicationName 아직 안 드셨나요?';
  String get medicationContextGuide => isEnglish
      ? 'Choose a medication to include its photo and dose with the message.'
      : '대화할 약을 선택하면 사진과 복용량이 메시지에 함께 표시됩니다.';
  String get retry => isEnglish ? 'Try again' : '다시 시도';
  String get emptyConversation => isEnglish
      ? 'No messages yet.\nChoose an active medication to start the conversation.'
      : '아직 대화가 없습니다.\n복용 중인 약을 골라 첫 메시지를 보내보세요.';
  String get noActiveMedication =>
      isEnglish ? 'No active medications' : '복용 중인 약이 없습니다';
  String get selectMedication => isEnglish ? 'Choose medication' : '대화할 약 선택';
  String get selectMedicationFirst =>
      isEnglish ? 'Choose a medication first' : '약을 먼저 선택하세요';
  String get enterMessage => isEnglish ? 'Enter a message' : '메시지를 입력하세요';
  String get sendMessage => isEnglish ? 'Send message' : '메시지 보내기';
  String get connected => isEnglish ? 'Live connection' : '실시간 연결됨';
  String get connecting => isEnglish ? 'Connecting' : '연결 중';
  String get reconnecting => isEnglish ? 'Reconnecting' : '다시 연결 중';
  String get disconnected => isEnglish ? 'Disconnected' : '연결 끊김';
  String get clearSelectedMedication =>
      isEnglish ? 'Clear selected medication' : '선택한 약 해제';
  String readAt(String timeLabel) =>
      isEnglish ? '$timeLabel · Read' : '$timeLabel · 읽음';
}
