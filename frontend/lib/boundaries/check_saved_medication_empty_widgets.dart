part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_empty_widgets.dart
// 역할: 저장 목록의 빈 상태, 선택 삭제 바, 날짜별 카드 위젯을 구성한다.

class _SavedMedicationEmptyState extends StatelessWidget {
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final VoidCallback onPrescriptionInputRequested;

  const _SavedMedicationEmptyState({
    required this.text,
    required this.userSetting,
    required this.onPrescriptionInputRequested,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 34, 22, 32),
                    decoration: BoxDecoration(
                      color: MedBuddyColors.surfaceSubtle,
                      borderRadius: MedBuddyRadii.card,
                      border: Border.all(
                        color: MedBuddyColors.outline,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.medication_outlined,
                          color: MedBuddyColors.textLight,
                          size: 42,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          text.emptyMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: MedBuddyColors.textMuted,
                            fontSize: 16 * scale,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 178),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: MedBuddyColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: MedBuddyRadii.card,
                    ),
                    textStyle: TextStyle(
                      fontSize: 22 * scale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  onPressed: onPrescriptionInputRequested,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.photo_camera_outlined, size: 40),
                      const SizedBox(height: 18),
                      Text(text.scanPrescription, textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      Text(
                        text.scanSubtitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MedBuddyColors.mint,
                          fontSize: 14 * scale,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectionDeleteBar extends StatelessWidget {
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final int selectedCount;
  final Future<void> Function() onDeleteRequested;

  const _SelectionDeleteBar({
    required this.text,
    required this.userSetting,
    required this.selectedCount,
    required this.onDeleteRequested,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.selectedCount(selectedCount),
              style: TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 14 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          FilledButton(
            onPressed: selectedCount == 0
                ? null
                : () async => onDeleteRequested(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF1F2D),
              disabledBackgroundColor: MedBuddyColors.outline,
              foregroundColor: Colors.white,
              minimumSize: const Size(118, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: TextStyle(
                fontSize: 14 * scale,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            child: Text(text.deleteSelected),
          ),
        ],
      ),
    );
  }
}

class _SavedMedicationDateCard extends StatelessWidget {
  final _SavedMedicationGroup group;
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final bool isSelectionMode;
  final Set<int> selectedMedicationIds;
  final void Function(MedicationDetail medication, bool selected)
  onSelectionChanged;
  final void Function(MedicationDetail medication) onGuideRequested;
  final void Function(MedicationDetail medication) onImageRequested;
  final Future<void> Function() onDeleteRequested;

  const _SavedMedicationDateCard({
    required this.group,
    required this.text,
    required this.userSetting,
    required this.isSelectionMode,
    required this.selectedMedicationIds,
    required this.onSelectionChanged,
    required this.onGuideRequested,
    required this.onImageRequested,
    required this.onDeleteRequested,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.outline, width: 1.5),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.displayDate,
                    style: TextStyle(
                      color: const Color(0xFF0A0A0A),
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: MedBuddyColors.outline),
          for (final medication in group.medications) ...[
            _SavedMedicationNameRow(
              medication: medication,
              text: text,
              userSetting: userSetting,
              isSelectionMode: isSelectionMode,
              isSelected:
                  medication.id != null &&
                  selectedMedicationIds.contains(medication.id),
              onSelectionChanged: (selected) {
                onSelectionChanged(medication, selected);
              },
              onGuideRequested: () => onGuideRequested(medication),
              onImageRequested: () => onImageRequested(medication),
            ),
            if (medication != group.medications.last)
              const Divider(height: 1, color: MedBuddyColors.outline),
          ],
          if (!isSelectionMode) ...[
            const Divider(height: 1, color: MedBuddyColors.outline),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(70),
                foregroundColor: const Color(0xFFFF1F2D),
                textStyle: TextStyle(
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              onPressed: onDeleteRequested,
              child: Text(text.delete),
            ),
          ],
        ],
      ),
    );
  }
}

// 클래스명: _SavedMedicationSortControl
// 역할: 저장 목록의 등록일자순과 복용날짜순 정렬 기준을 전환한다.
// 주요 책임:
// - 현재 선택된 정렬 기준을 초록색으로 구분해 표시한다.
// - 사용자가 선택한 기준을 상위 화면 상태로 전달한다.
