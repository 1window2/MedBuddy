// 파일명: chat_medication_reference_tile.dart
// 역할: 채팅 검색약을 복용 일정이나 기록 버튼 없이 참고용 정보로만 표시한다.
import 'package:flutter/material.dart';
import '../entities/chat_medication_reference_entity.dart';
import 'medication_thumbnail.dart';

// 클래스명: ChatMedicationReferenceTile
// 역할: 검색 약품의 사진·이름·제조사와 미등록 상태를 표시한다.
// 주요 책임: 저장 약 첨부와 구분하고 작성 중에만 선택적 첨부 제거 동작을 제공한다.
// 속성: reference: 약품 참조; isEnglish: 표시 언어; onRemove: 선택적 삭제 콜백, 보낸 메시지에서는 null.
class ChatMedicationReferenceTile extends StatelessWidget {
  // 함수이름: ChatMedicationReferenceTile
  // 함수역할: 복약함에 등록되지 않은 약품 참고 첨부와 선택적 삭제 동작을 구성한다.
  // 매개변수: key: 식별자; reference: 공개 약품 참조; isEnglish: 표시 언어; onRemove: 제공 시 첨부 삭제 버튼을 표시할 콜백.
  // 반환값: 참고 약품 행 위젯; 약 등록이나 삭제 저장을 직접 수행하지 않는다.
  const ChatMedicationReferenceTile({
    super.key,
    required this.reference,
    required this.isEnglish,
    this.onRemove,
  });

  final ChatMedicationReference reference;
  final bool isEnglish;
  final VoidCallback? onRemove;

  // 함수이름: build
  // 함수역할: 약 사진·이름·미등록 안내와 제조사를 표시하고 필요한 경우 첨부 제거 버튼을 제공한다.
  // 매개변수: context: 테마를 읽을 구성 문맥.
  // 반환값: 긴 이름·설명을 두 줄로 제한한 참고 첨부 행.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        MedicationThumbnail(imageUrl: reference.imageUrl, size: 40),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reference.itemName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                [
                  isEnglish ? 'Reference only - not saved' : '검색약 · 미등록',
                  if (reference.manufacturer.isNotEmpty) reference.manufacturer,
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (onRemove != null)
          IconButton(
            tooltip: isEnglish ? 'Remove attachment' : '첨부 삭제',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
      ],
    ),
  );
}
