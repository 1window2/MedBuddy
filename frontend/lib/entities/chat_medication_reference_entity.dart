// 검색약은 저장 약 ID나 복용 일정 없이 참고용 표시 정보만 전달한다.
import 'medication_detail_entity.dart';
import 'medication_image_url_entity.dart';

class ChatMedicationReference {
  final String itemSeq;
  final String itemName;
  final String manufacturer;
  final String imageUrl;

  const ChatMedicationReference({
    required this.itemSeq,
    required this.itemName,
    this.manufacturer = '',
    this.imageUrl = '',
  });

  factory ChatMedicationReference.fromDetail(MedicationDetail detail) =>
      ChatMedicationReference.fromJson({
        'item_seq': detail.itemSeq,
        'item_name': detail.itemName,
        'manufacturer': detail.manufacturer,
        'image_url': detail.imageUrl,
      });

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

  Map<String, String> toJson() => {
    'item_seq': itemSeq,
    'item_name': itemName,
    'manufacturer': manufacturer,
    'image_url': safeMedicationImageUrl(imageUrl),
  };
}
