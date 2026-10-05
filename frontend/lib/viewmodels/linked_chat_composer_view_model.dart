// File Name: linked_chat_composer_view_model.dart
// Role: Owns one conversation's outgoing message concurrency and retry identity.

import 'dart:math';

import 'package:flutter/foundation.dart';

import '../controls/manage_linked_chat_control.dart';
import '../entities/chat_message_draft_entity.dart';
import '../entities/chat_message_entity.dart';

// Class Name: LinkedChatComposerViewModel
// Role: Coordinates outgoing requests independently of text fields, cards and navigation.
// Responsibilities:
// - Serialize one send and retain its failed payload/request ID for safe retries.
// - Preserve explicit care-share retry IDs without coupling to nearby-place presentation data.
// - Invalidate late completions when the account/link-keyed owner is disposed.
// Attributes: linkId: Immutable conversation scope; _control: Borrowed authenticated adapter.
class LinkedChatComposerViewModel extends ChangeNotifier {
  final int linkId;
  final ManageLinkedChat _control;
  final String Function()? _requestIdFactory;
  final Random _random = Random.secure();
  ChatMessageDraft? _pendingDraft;
  String? _pendingRequestId;
  bool _isSending = false;
  bool _sendFailed = false;
  bool _disposed = false;

  // Function Name: LinkedChatComposerViewModel
  // Description: Borrows a scoped control and optionally injects deterministic request identity generation.
  // Parameters: linkId: Conversation ID; control: Authenticated send adapter; requestIdFactory: Optional ID generator.
  // Returns: A scoped outgoing owner; it never disposes the borrowed adapter.
  LinkedChatComposerViewModel({
    required this.linkId,
    required ManageLinkedChat control,
    String Function()? requestIdFactory,
  }) : _control = control,
       _requestIdFactory = requestIdFactory;

  // Function Name: isSending
  // Description: Exposes single-send concurrency without allowing UI mutation.
  // Parameters: None. Returns: Whether an outgoing request is in flight.
  bool get isSending => _isSending;

  // Function Name: sendFailed
  // Description: Exposes technical failure for localization by the presentation boundary.
  // Parameters: None. Returns: Whether the last accepted send failed.
  bool get sendFailed => _sendFailed;

  // Function Name: pendingRequestId
  // Description: Exposes the last attempted identity for a presentation-owned explicit share retry.
  // Parameters: None. Returns: Failed/in-flight request ID, or null after success/reset/disposal.
  String? get pendingRequestId => _pendingRequestId;

  // Function Name: createClientMessageId
  // Description: Generates the existing timestamp/random wire identity, also reusable by dose-request callers.
  // Parameters: None. Returns: A non-sensitive opaque request ID; throws after this scope is disposed.
  String createClientMessageId() {
    if (_disposed) throw StateError('The chat composer is disposed.');
    final injected = _requestIdFactory;
    if (injected != null) return injected();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomPart = _random.nextInt(0x7fffffff).toRadixString(16);
    return 'msg_${timestamp}_$randomPart';
  }

  // Function Name: resetRetry
  // Description: Discards transport retry identity after an attachment edit or a successful send.
  // Parameters: None. Returns: None; does not change presentation-owned draft or error text.
  void resetRetry() {
    _pendingDraft = null;
    _pendingRequestId = null;
  }

  // Function Name: send
  // Description: Sends a frozen payload once, retaining failures and rejecting late disposed completions.
  // Parameters: draft: Transport-ready payload; requestId: Optional explicit ID for a separately retained share retry.
  // Returns: Accepted message, or null for empty/busy/disposed/failed work. Failures never clear the draft.
  Future<ChatMessage?> send(ChatMessageDraft draft, {String? requestId}) async {
    if (_disposed || _isSending || draft.body.isEmpty) return null;
    _isSending = true;
    _sendFailed = false;
    notifyListeners();
    try {
      final pending = _pendingDraft;
      final canReuse = pending != null && draft.matchesRetryOf(pending);
      final id =
          requestId ??
          (canReuse
              ? _pendingRequestId ?? createClientMessageId()
              : createClientMessageId());
      _pendingDraft = draft;
      _pendingRequestId = id;
      final message = await _control.sendMessage(
        linkId: linkId,
        clientMessageId: id,
        body: draft.body,
        medicationId: draft.primaryMedicationId,
        medicationIds: draft.medicationIds,
        messageKind: draft.messageKind,
        slotKey: draft.slotKey,
        pharmacyId: draft.pharmacyId,
        hospitalId: draft.hospitalId,
        hospitalScheduleDate: draft.hospitalScheduleDate,
      );
      if (_disposed) return null;
      resetRetry();
      return message;
    } catch (_) {
      if (!_disposed) _sendFailed = true;
      return null;
    } finally {
      if (!_disposed) {
        _isSending = false;
        notifyListeners();
      }
    }
  }

  // Function Name: dispose
  // Description: Invalidates pending completions and clears local retry input without closing borrowed adapters.
  // Parameters: None. Returns: None; in-flight server work may complete but cannot publish to this session.
  @override
  void dispose() {
    _disposed = true;
    _isSending = false;
    _sendFailed = false;
    resetRetry();
    super.dispose();
  }
}
