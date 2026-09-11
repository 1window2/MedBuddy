part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_filter_widgets.dart
// 역할: 저장 약품의 복용 상태 필터와 필터별 빈 결과를 제공한다.

// 클래스명: _SavedMedicationFilterControl
// 역할: 복용 중·종료·전체 약품 선택 필터를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 복용 중·종료·전체 약품 선택 필터 위젯을 구성한다.
// 속성:
// - filterMode (_SavedMedicationFilterMode): 저장 약품의 복용 중·종료·전체 표시 기준.
// - onChanged (ValueChanged<_SavedMedicationFilterMode>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
class _SavedMedicationFilterControl extends StatelessWidget {
  final _SavedMedicationFilterMode filterMode;
  final _SavedMedicationText text;
  final ValueChanged<_SavedMedicationFilterMode> onChanged;

  // 함수이름: _SavedMedicationFilterControl
  // 함수역할: 복용 중·종료·전체 약품 선택 필터에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - filterMode (_SavedMedicationFilterMode): 저장 약품의 복용 중·종료·전체 표시 기준.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // - onChanged (ValueChanged<_SavedMedicationFilterMode>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // 반환값: 입력 설정이 반영된 _SavedMedicationFilterControl 인스턴스.
  const _SavedMedicationFilterControl({
    required this.filterMode,
    required this.text,
    required this.onChanged,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 복용 중·종료·전체 약품 선택 필터 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 복용 중·종료·전체 약품 선택 필터에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: const Key('saved-medication-filter-selector'),
      onPressed: () => _showFilterPicker(context),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: const BorderSide(color: MedBuddyColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.filter_alt_outlined,
            color: MedBuddyColors.primaryDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text.selectedFilter(filterMode),
              style: const TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down,
            color: MedBuddyColors.textMuted,
          ),
        ],
      ),
    );
  }

  // 함수이름: _showFilterPicker
  // 함수역할: 약국 화면과 같은 선택 시트를 열고 실제 변경만 부모에 전달한다.
  // 매개변수: context: 필터 버튼 위치. 반환값: 선택 또는 취소 처리 완료.
  Future<void> _showFilterPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<_SavedMedicationFilterMode>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      // 함수역할: 큰 글씨에서는 선택 항목만 스크롤되도록 시트 높이를 제한한다.
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        text.filterTitle,
                        style: const TextStyle(
                          color: MedBuddyColors.textStrong,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('saved-medication-filter-close'),
                      tooltip: text.close,
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Column(
                    children: [
                      for (final mode in _SavedMedicationFilterMode.values) ...[
                        if (mode != _SavedMedicationFilterMode.active)
                          const SizedBox(height: 8),
                        _buildOption(sheetContext, mode),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (context.mounted && selected != null && selected != filterMode) {
      onChanged(selected);
    }
  }

  // 함수이름: _buildOption
  // 함수역할: 현재 복용 상태를 라디오 표시·초록 테두리로 강조하고 선택한 값을 시트 결과로 돌려준다.
  // 매개변수:
  // - mode (_SavedMedicationFilterMode): 선택한 필터·알림 모드 또는 옵션 종류.
  // - sheetContext (BuildContext): 선택 결과로 닫을 시트 위치.
  // 반환값: 복용 중·종료·전체 약품 선택 필터에 쓰는 위젯 트리.
  Widget _buildOption(
    BuildContext sheetContext,
    _SavedMedicationFilterMode mode,
  ) {
    final selected = mode == filterMode;
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? MedBuddyColors.successSurface : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? MedBuddyColors.primary : MedBuddyColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('saved-medication-filter-option-${mode.name}'),
          borderRadius: BorderRadius.circular(8),
          // 함수이름: _buildOption.onTap callback
          // 함수역할: 선택한 복용 상태를 반환하며 시트를 닫는다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onTap: () => Navigator.pop(sheetContext, mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? MedBuddyColors.primary
                      : MedBuddyColors.textSubtle,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text.filterLabel(mode),
                    style: const TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _SavedMedicationFilteredEmptyState
// 역할: 선택한 복용 상태에 해당하는 약이 없다는 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 선택한 복용 상태에 해당하는 약이 없다는 안내 위젯을 구성한다.
// 속성:
// - filterMode (_SavedMedicationFilterMode): 저장 약품의 복용 중·종료·전체 표시 기준.
class _SavedMedicationFilteredEmptyState extends StatelessWidget {
  final _SavedMedicationFilterMode filterMode;
  final _SavedMedicationText text;

  // 함수이름: _SavedMedicationFilteredEmptyState
  // 함수역할: 선택한 복용 상태에 해당하는 약이 없다는 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - filterMode (_SavedMedicationFilterMode): 저장 약품의 복용 중·종료·전체 표시 기준.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _SavedMedicationFilteredEmptyState 인스턴스.
  const _SavedMedicationFilteredEmptyState({
    required this.filterMode,
    required this.text,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 선택한 복용 상태에 해당하는 약이 없다는 안내 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 선택한 복용 상태에 해당하는 약이 없다는 안내에 쓰는 위젯 트리.
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
