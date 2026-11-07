// 검색약 첨부의 전송 범위·재시도·삭제 시 개인정보 제거를 검증한다.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/chat_message_draft_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';

const reference = ChatMedicationReference(
  itemSeq: '202600001',
  itemName: '검색정',
);

Map<String, dynamic> messageJson() => {
  'message_id': 1,
  'link_id': 17,
  'sender_hash': 'patient-a',
  'client_message_id': 'reference_request_001',
  'body': '질문',
  'created_at': '2026-11-07T00:00:00Z',
  'context': {
    'medication_references': [reference.toJson()],
  },
};

void main() {
  test('검색 결과에서 저장 ID·일정·개인 정보를 제외한다', () {
    final value = ChatMedicationReference.fromDetail(
      const MedicationDetail(
        id: 9,
        patientHash: 'patient-a',
        itemSeq: '202600001',
        itemName: '검색정',
        efficacy: '',
        usageMethod: '',
        warning: '',
        dosagePerTime: '1정',
        scheduleSlotKeys: ['morning'],
        imageUrl: 'https://tracking.example/image',
        localImagePath: '/private/image',
      ),
    );
    expect(value.toJson(), reference.toJson());
  });

  test('참고 첨부는 저장 약 목록과 분리되고 삭제하면 지워진다', () {
    final message = ChatMessage.fromJson(messageJson());
    expect(message.attachedMedicationContexts, isEmpty);
    expect(message.medicationContext, isNull);
    expect(message.medicationReferences.single.itemSeq, reference.itemSeq);
    expect(
      message.copyWith(readAt: DateTime.now()).medicationReferences,
      hasLength(1),
    );
    expect(message.copyWith(hiddenForMe: true).medicationReferences, isEmpty);
    expect(
      message.copyWith(deletedForEveryone: true).medicationReferences,
      isEmpty,
    );
    expect(
      ChatMessage.fromJson({
        ...messageJson(),
        'deleted_for_everyone': true,
      }).medicationReferences,
      isEmpty,
    );
  });

  test('스냅샷을 바꾸면 재시도 요청도 구분한다', () {
    final selected = [reference];
    final first = ChatMessageDraft(body: '질문', medicationReferences: selected);
    selected.clear();
    expect(first.medicationReferences, hasLength(1));
    expect(() => first.medicationReferences.clear(), throwsUnsupportedError);
    expect(
      first.matchesRetryOf(
        ChatMessageDraft(body: '질문', medicationReferences: [reference]),
      ),
      isTrue,
    );
    expect(
      first.matchesRetryOf(
        ChatMessageDraft(
          body: '질문',
          medicationReferences: const [
            ChatMedicationReference(itemSeq: '202600001', itemName: '다른 이름'),
          ],
        ),
      ),
      isFalse,
    );
  });

  test('참고 전송에 저장 약 ID와 복약 일정이 포함되지 않는다', () async {
    Map<String, dynamic>? posted;
    final control = ManageLinkedChat(
      userHash: 'patient-a',
      client: MockClient((request) async {
        posted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'success': true, 'data': messageJson()}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(control.dispose);
    final sent = await control.sendMessage(
      linkId: 17,
      clientMessageId: 'reference_request_001',
      body: '질문',
      medicationReferences: [reference],
    );
    expect(posted!['medication_references'], [reference.toJson()]);
    expect(posted!.containsKey('medication_id'), isFalse);
    expect(posted!.containsKey('medication_ids'), isFalse);
    expect(posted!.containsKey('slot_key'), isFalse);
    expect(sent.medicationReferences, hasLength(1));
  });
}
