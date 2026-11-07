// File Name: chat_message_draft_entity.dart
// Role: Preserves an immutable outgoing message payload and its retry comparison contract.

import 'dart:convert';
import 'chat_message_entity.dart';

// 클래스명: ChatMessageDraft
// 역할: 화면·인증 상태와 분리된 채팅 전송 입력을 보관한다.
// 주요 책임: 첨부 순서를 보존하고 재시도 요청의 동일성을 비교한다.
// 속성: body (String): 공백 정리 본문; medicationIds/medicationReferences (List): 불변 첨부 목록; messageKind 및 시간대·장소·진료일 필드: 전송 문맥; _medicationSignature: 정렬된 약 ID 비교값.
class ChatMessageDraft {
  final String body;
  final List<int> medicationIds;
  final List<ChatMedicationReference> medicationReferences;
  final ChatMessageKind messageKind;
  final String? slotKey;
  final String? pharmacyId;
  final String? hospitalId;
  final String? hospitalScheduleDate;
  final String _medicationSignature;

  // 함수이름: ChatMessageDraft
  // 함수역할: 본문 공백을 정리하고 첨부 목록을 불변 복사하여 재시도 비교용 값을 만든다.
  // 매개변수: body (String): 본문; medicationIds (List<int>): 첨부 ID; medicationReferences (List<ChatMedicationReference>): 첨부 상세; messageKind (ChatMessageKind): 메시지 종류; slotKey/pharmacyId/hospitalId/hospitalScheduleDate (String?): 시간대·약국·병원·진료일 문맥.
  // 반환값: ChatMessageDraft: 서버 검증을 대신하지 않는 정규화된 입력.
  ChatMessageDraft({
    required String body,
    List<int> medicationIds = const [],
    List<ChatMedicationReference> medicationReferences = const [],
    this.messageKind = ChatMessageKind.text,
    this.slotKey,
    this.pharmacyId,
    this.hospitalId,
    this.hospitalScheduleDate,
  }) : body = body.trim(),
       medicationIds = List.unmodifiable(medicationIds),
       medicationReferences = List.unmodifiable(medicationReferences),
       _medicationSignature = (List<int>.of(medicationIds)..sort()).join(',');

  // Function Name: primaryMedicationId
  // Description: Keeps the first selected attachment as the legacy primary wire field.
  // Parameters: None. Returns: Primary medication ID, or null for an unattached message.
  int? get primaryMedicationId => medicationIds.firstOrNull;

  // 함수이름: matchesRetryOf
  // 함수역할: 본문과 모든 문맥을 비교하되 약 ID는 순서를 무시하고 첨부 상세는 JSON 순서까지 비교한다.
  // 매개변수: other (ChatMessageDraft): 이전 실패 요청의 입력.
  // 반환값: bool: 기존 요청 ID로 재시도할 수 있는 동일 입력이면 true.
  bool matchesRetryOf(ChatMessageDraft other) =>
      body == other.body &&
      _medicationSignature == other._medicationSignature &&
      jsonEncode(medicationReferences.map((item) => item.toJson()).toList()) ==
          jsonEncode(
            other.medicationReferences.map((item) => item.toJson()).toList(),
          ) &&
      messageKind == other.messageKind &&
      slotKey == other.slotKey &&
      pharmacyId == other.pharmacyId &&
      hospitalId == other.hospitalId &&
      hospitalScheduleDate == other.hospitalScheduleDate;
}
