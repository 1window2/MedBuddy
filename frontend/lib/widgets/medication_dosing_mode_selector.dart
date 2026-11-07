// 파일명: medication_dosing_mode_selector.dart
// 역할: 정기·필요시 복용 유형 선택과 알림 제외 안내를 공통으로 표시한다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';

// 등록 경로가 달라도 같은 복용 유형과 알림 제외 안내를 제공한다.
// 클래스명: MedicationDosingModeSelector
// 역할: 정기 복용과 필요시 복용 선택을 같은 방식으로 표시한다.
// 주요 책임: 선택 변경을 상위 폼에 전달하고 필요시 약의 정기 알림 제외 안내를 표시한다.
// 속성: isAsNeeded/isEnglish (bool): 선택·언어; onChanged (ValueChanged<bool>?): 변경 콜백; keyPrefix (String): 선택 버튼 키 접두사.
class MedicationDosingModeSelector extends StatelessWidget {
  final bool isAsNeeded;
  final bool isEnglish;
  final ValueChanged<bool>? onChanged;
  final String keyPrefix;

  // 함수이름: MedicationDosingModeSelector
  // 함수역할: 선택 상태·표시 언어·식별 키·변경 콜백을 입력받는다.
  // 매개변수: key (Key?): 식별 키; isAsNeeded/isEnglish (bool): 상태·언어; onChanged (ValueChanged<bool>?): null이면 비활성; keyPrefix (String): 버튼 키 접두사.
  // 반환값: 선택 상태를 자체 보관하지 않는 복용 유형 위젯.
  const MedicationDosingModeSelector({
    super.key,
    required this.isAsNeeded,
    required this.isEnglish,
    required this.onChanged,
    required this.keyPrefix,
  });

  // Function Name: build
  // Description: Render scheduled/as-needed choices and contextual as-needed guidance; disable choices when no change callback is provided.
  // Parameters: context (BuildContext): widget build context.
  // Returns: Widget: localized dosing-mode selector.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        isEnglish ? 'Dosing type' : '복용 유형',
        style: MedBuddyTextStyles.formSectionTitle,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            key: Key('$keyPrefix-scheduled'),
            label: Text(isEnglish ? 'Scheduled' : '정기 복용'),
            selected: !isAsNeeded,
            onSelected: onChanged == null ? null : (_) => onChanged!(false),
          ),
          ChoiceChip(
            key: Key('$keyPrefix-as-needed'),
            label: Text(isEnglish ? 'As needed' : '필요시 복용'),
            selected: isAsNeeded,
            onSelected: onChanged == null ? null : (_) => onChanged!(true),
          ),
        ],
      ),
      if (isAsNeeded) ...[
        const SizedBox(height: 8),
        KeepWordsText(
          isEnglish
              ? 'Excluded from scheduled dose and missed-dose reminders. Follow your prescription when taking it.'
              : '정해진 시간의 복용 알림과 미복약 알림에서 제외됩니다. 복용할 때는 처방·복약지도를 따라 주세요.',
          style: const TextStyle(color: MedBuddyColors.textMuted, height: 1.4),
        ),
      ],
    ],
  );
}
