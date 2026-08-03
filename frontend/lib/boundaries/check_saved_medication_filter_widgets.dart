part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_filter_widgets.dart
// 역할: 저장된 복약 정보의 복용 상태 필터와 필터 빈 상태를 구성한다.

class _SavedMedicationFilterControl extends StatelessWidget {
  final _SavedMedicationFilterMode filterMode;
  final _SavedMedicationText text;
  final ValueChanged<_SavedMedicationFilterMode> onChanged;

  const _SavedMedicationFilterControl({
    required this.filterMode,
    required this.text,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Semantics(
        label: text.isEnglish ? 'Medication status filter' : '복약 상태 필터',
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: MedBuddyColors.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              _buildOption(
                mode: _SavedMedicationFilterMode.active,
                label: text.activeMedication,
              ),
              _buildOption(
                mode: _SavedMedicationFilterMode.ended,
                label: text.endedMedication,
              ),
              _buildOption(
                mode: _SavedMedicationFilterMode.all,
                label: text.allMedication,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption({
    required _SavedMedicationFilterMode mode,
    required String label,
  }) {
    final selected = mode == filterMode;
    return Expanded(
      child: Material(
        color: selected ? MedBuddyColors.primary : Colors.white,
        child: InkWell(
          onTap: () => onChanged(mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : MedBuddyColors.textStrong,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedMedicationFilteredEmptyState extends StatelessWidget {
  final _SavedMedicationFilterMode filterMode;
  final _SavedMedicationText text;

  const _SavedMedicationFilteredEmptyState({
    required this.filterMode,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.medication_outlined,
              color: MedBuddyColors.textLight,
              size: 52,
            ),
            const SizedBox(height: 14),
            Text(
              text.filteredEmptyMessage(filterMode),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
