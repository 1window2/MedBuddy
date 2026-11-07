// 파일명: chat_medication_reference_entity.dart
// 역할: 채팅에 첨부하는 검색약(저장하지 않은 약품)의 표시 정보를 정의한다.
// 검색약은 저장 약 ID나 복용 일정 없이 참고용 표시 정보만 전달한다.
import 'medication_detail_entity.dart';
import 'medication_image_url_entity.dart';

// 한 메시지에 첨부할 수 있는 저장 약과 검색약의 합계. 서버의 MAX_CHAT_MEDICATION_CONTEXTS와 같다.
const int maxChatMedicationAttachments = 10;

// 클래스명: ChatMedicationReference
// 역할: 검색 결과 한 품목의 품목기준코드·이름·제조사·사진 주소를 담는다.
// 주요 책임:
// - 서버 스키마와 같은 형식·길이 규칙으로 읽고, 사진 주소는 허용한 공공 이미지 주소만 남긴다.
// 속성:
// - itemSeq (String): 품목기준코드.
// - itemName (String): 품목 이름.
// - manufacturer (String): 제조사. 모르면 빈 문자열.
// - imageUrl (String): 허용한 공공 이미지 주소. 없으면 빈 문자열.
class ChatMedicationReference {
  final String itemSeq;
  final String itemName;
  final String manufacturer;
  final String imageUrl;

  // 함수이름: ChatMedicationReference
  // 함수역할: 복약함 등록과 별개인 약품 참고 첨부의 공개 표시 정보를 보관한다.
  // 매개변수: itemSeq/itemName: 약품 식별자와 이름; manufacturer/imageUrl: 생략 가능한 제조사와 이미지 주소.
  // 반환값: 참고 첨부 객체; 직접 생성 시 입력 검증은 하지 않는다.
  const ChatMedicationReference({
    required this.itemSeq,
    required this.itemName,
    this.manufacturer = '',
    this.imageUrl = '',
  });

  // 함수이름: ChatMedicationReference.fromDetail
  // 함수역할: 약 검색 결과를 첨부용 표시 정보로 바꾼다.
  // 매개변수:
  // - detail (MedicationDetail): 사용자가 고른 검색 결과.
  // 반환값: 검증한 ChatMedicationReference. 형식이 맞지 않으면 FormatException.
  factory ChatMedicationReference.fromDetail(MedicationDetail detail) =>
      ChatMedicationReference.fromJson({
        'item_seq': detail.itemSeq,
        'item_name': detail.itemName,
        'manufacturer': detail.manufacturer,
        'image_url': detail.imageUrl,
      });

  // 함수이름: ChatMedicationReference.fromJson
  // 함수역할: 서버 응답이나 첨부 입력을 서버 스키마와 같은 규칙으로 검증해 읽는다.
  // 매개변수:
  // - json (Map<String, dynamic>): item_seq·item_name·manufacturer·image_url 값.
  // 반환값: 검증한 ChatMedicationReference. 형식이 맞지 않으면 FormatException.
  factory ChatMedicationReference.fromJson(Map<String, dynamic> json) {
    final id = (json['item_seq'] as String? ?? '').trim();
    final name = (json['item_name'] as String? ?? '').trim();
    final maker = (json['manufacturer'] as String? ?? '').trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id) ||
        name.isEmpty ||
        name.length > 300 ||
        maker.length > 200) {
      throw const FormatException('검색약 첨부 정보가 올바르지 않습니다.');
    }
    return ChatMedicationReference(
      itemSeq: id,
      itemName: name,
      manufacturer: maker,
      imageUrl: safeMedicationImageUrl(json['image_url']),
    );
  }

  // 함수이름: toJson
  // 함수역할: 전송용 JSON으로 바꾼다.
  // 매개변수: 없음.
  // 반환값: 서버 스키마의 필드 이름을 쓴 Map.
  Map<String, String> toJson() => {
    'item_seq': itemSeq,
    'item_name': itemName,
    'manufacturer': manufacturer,
    'image_url': safeMedicationImageUrl(imageUrl),
  };
}
