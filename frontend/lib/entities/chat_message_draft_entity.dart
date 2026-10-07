// File Name: chat_message_draft_entity.dart
// Role: Preserves an immutable outgoing message payload and its retry comparison contract.

import 'chat_message_entity.dart';

// Class Name: ChatMessageDraft
// Role: Represents transport-ready input without widget, navigation or authentication state.
// Responsibilities:
// - Snapshot attachment IDs while preserving the primary attachment and wire ordering.
// - Compare retry payloads with the existing order-independent medication-ID signature.
// Attributes: body: Trimmed text; medicationIds: Immutable attachment IDs; remaining fields: Structured context IDs.
class ChatMessageDraft {
  final String body;
  final List<int> medicationIds;
  final ChatMessageKind messageKind;
  final String? slotKey;
  final String? pharmacyId;
  final String? hospitalId;
  final String? hospitalScheduleDate;
  final String _medicationSignature;

  // Function Name: ChatMessageDraft
  // Description: Freezes outgoing input without resolving patient roles or changing server validation.
  // Parameters: body: User text; medicationIds: Attachment IDs; kind/context IDs: Existing wire fields.
  // Returns: An immutable normalized payload whose primary attachment keeps its original ordering.
  ChatMessageDraft({
    required String body,
    List<int> medicationIds = const [],
    this.messageKind = ChatMessageKind.text,
    this.slotKey,
    this.pharmacyId,
    this.hospitalId,
    this.hospitalScheduleDate,
  }) : body = body.trim(),
       medicationIds = List.unmodifiable(medicationIds),
       _medicationSignature = (List<int>.of(medicationIds)..sort()).join(',');

  // Function Name: primaryMedicationId
  // Description: Keeps the first selected attachment as the legacy primary wire field.
  // Parameters: None. Returns: Primary medication ID, or null for an unattached message.
  int? get primaryMedicationId => medicationIds.firstOrNull;

  // Function Name: matchesRetryOf
  // Description: Applies the existing retry identity rules to every outgoing context field.
  // Parameters: other: Previously failed payload. Returns: Whether its request ID may be reused.
  bool matchesRetryOf(ChatMessageDraft other) =>
      body == other.body &&
      _medicationSignature == other._medicationSignature &&
      messageKind == other.messageKind &&
      slotKey == other.slotKey &&
      pharmacyId == other.pharmacyId &&
      hospitalId == other.hospitalId &&
      hospitalScheduleDate == other.hospitalScheduleDate;
}
