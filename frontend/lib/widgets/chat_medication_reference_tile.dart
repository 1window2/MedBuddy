// 파일명: chat_medication_reference_tile.dart
// 역할: 채팅 검색약을 복용 일정이나 기록 버튼 없이 참고용 정보로만 표시한다.
import 'package:flutter/material.dart';
import '../entities/chat_medication_reference_entity.dart';
import 'medication_thumbnail.dart';

// 클래스명: ChatMedicationReferenceTile
// 역할: 검색약 한 품목의 사진·이름·제조사와 미등록 표시를 한 줄로 보여 준다.
// 속성:
// - reference (ChatMedicationReference): 표시할 검색약.
// - isEnglish (bool): 영어 문구 사용 여부.
// - onRemove (VoidCallback?): 작성 중 첨부에서 뺄 때의 콜백. 보낸 메시지에서는 null.
class ChatMedicationReferenceTile extends StatelessWidget {
  const ChatMedicationReferenceTile({
    super.key,
    required this.reference,
    required this.isEnglish,
    this.onRemove,
  });

  final ChatMedicationReference reference;
  final bool isEnglish;
  final VoidCallback? onRemove;

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
