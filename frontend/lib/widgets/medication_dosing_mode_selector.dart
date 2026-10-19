import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 등록 경로가 달라도 같은 복용 유형과 알림 제외 안내를 제공한다.
class MedicationDosingModeSelector extends StatelessWidget {
  final bool isAsNeeded;
  final bool isEnglish;
  final ValueChanged<bool>? onChanged;
  final String keyPrefix;

  const MedicationDosingModeSelector({
    super.key,
    required this.isAsNeeded,
    required this.isEnglish,
    required this.onChanged,
    required this.keyPrefix,
  });

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
        Text(
          isEnglish
              ? 'Excluded from scheduled dose and missed-dose reminders. Follow your prescription when taking it.'
              : '정해진 시간의 복용 알림과 미복약 알림에서 제외됩니다. 복용할 때는 처방·복약지도를 따라 주세요.',
          style: const TextStyle(color: MedBuddyColors.textMuted, height: 1.4),
        ),
      ],
    ],
  );
}
