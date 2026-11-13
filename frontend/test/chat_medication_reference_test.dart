// 파일명: chat_medication_reference_test.dart
// 역할: 검색약 첨부의 전송 범위·재시도·삭제 시 개인정보 제거를 검증한다.
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

// 함수이름: messageJson
// 함수역할:
// - 저장 약이나 일정 없이 카탈로그 참고 첨부 한 건을 가진 채팅 응답을 만든다.
// 매개변수:
// - 없음; 공용 reference 값을 참고 첨부로 사용한다.
// 반환값:
// - Map<String, dynamic>: 고정 메시지·연동·요청 ID를 가진 수정 가능한 응답 맵.
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

// 함수이름: main
// 함수역할:
// - 카탈로그 참고 첨부의 직렬화·재시도 키·전송 계약을 검증하는 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  // 함수이름: test callback
  // 함수역할:
  // - 환자·저장 ID·복용량·시간대·원격 및 로컬 이미지 경로를 넣은 상세 약에서 품목 코드와 이름만 참고 첨부로 남는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test callback
  // 함수역할:
  // - 읽음 갱신은 참고 첨부를 유지하지만 숨김·전체 삭제·서버 삭제 응답은 첨부를 제거하고 저장 약 문맥으로 취급하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test callback
  // 함수역할:
  // - 초안이 외부 목록의 사본을 불변으로 보관하고 품목 코드가 같아도 표시 이름이 바뀌면 다른 재시도로 구분하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test callback
  // 함수역할:
  // - 실제 채팅 제어기가 참고 첨부만 JSON에 넣고 저장 약 ID·시간대 키를 제외하며 응답 첨부도 복원하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
