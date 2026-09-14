part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_filter_widgets.dart
// 역할: 저장 약품의 복용 상태 필터와 필터별 빈 결과를 제공한다.

// 클래스명: _SavedMedicationFilterControl
// 역할: 복용 상태·날짜 기준·정렬 방향을 한 시트에서 선택하고 적용한다.
// 속성: 현재 조회값과 onChanged는 소유 화면의 목록/선택 상태에 연결된다.
class _SavedMedicationFilterControl extends StatelessWidget {
  final _SavedMedicationFilterMode filterMode;
  final _SavedMedicationSortMode sortMode;
  final _SavedMedicationSortDirection sortDirection;
  final _SavedMedicationText text;
  final bool enabled;
  final void Function(
    _SavedMedicationFilterMode,
    _SavedMedicationSortMode,
    _SavedMedicationSortDirection,
  )
  onChanged;

  // 함수역할: 현재 조회 조건과 적용 콜백을 받는다. 반환값: 조회 조건 버튼.
  const _SavedMedicationFilterControl({
    required this.filterMode,
    required this.sortMode,
    required this.sortDirection,
    required this.text,
    required this.enabled,
    required this.onChanged,
  });

  // 함수역할: 현재 조건을 표시하고 선택 시트를 연다. 매개변수: context.
  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: const Key('saved-medication-filter-selector'),
    onPressed: enabled ? () => _showFilterPicker(context) : null,
    style: OutlinedButton.styleFrom(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text.selectedFilter(filterMode),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MedBuddyColors.textStrong,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_sortLabel(sortMode)} · ${_directionLabel(sortDirection)}',
                style: const TextStyle(
                  fontSize: 14,
                  color: MedBuddyColors.textMuted,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.keyboard_arrow_down, color: MedBuddyColors.textMuted),
      ],
    ),
  );

  // 함수역할: 날짜 정렬의 기준/방향을 일상적인 문구로 표시한다. 매개변수: 선택값.
  String _sortLabel(_SavedMedicationSortMode mode) =>
      mode == _SavedMedicationSortMode.registeredDate
      ? text.sortByRegisteredDate
      : text.sortByMedicationDate;
  String _directionLabel(_SavedMedicationSortDirection direction) =>
      direction == _SavedMedicationSortDirection.descending
      ? (text.isEnglish ? 'Newest first' : '최신순')
      : (text.isEnglish ? 'Oldest first' : '오래된순');

  // 함수역할: 임시 선택을 유지하다 적용할 때만 부모에 전달한다. 취소는 기존 조건을 보존한다.
  Future<void> _showFilterPicker(BuildContext context) async {
    FocusScope.of(context).unfocus();
    var filter = filterMode;
    var sort = sortMode;
    var direction = sortDirection;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          text.filterTitle,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: MedBuddyColors.textStrong,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _choiceRow<_SavedMedicationFilterMode>(
                          context: context,
                          title: text.isEnglish ? 'Medication status' : '복용 상태',
                          preferenceKey: 'filter',
                          value: filter,
                          values: _SavedMedicationFilterMode.values,
                          label: text.filterLabel,
                          onSelected: (value) =>
                              setSheetState(() => filter = value),
                        ),
                        const Divider(height: 1, color: MedBuddyColors.divider),
                        _choiceRow<_SavedMedicationSortMode>(
                          context: context,
                          title: text.isEnglish ? 'Date' : '날짜 기준',
                          preferenceKey: 'sort',
                          value: sort,
                          values: _SavedMedicationSortMode.values,
                          label: _sortLabel,
                          onSelected: (value) =>
                              setSheetState(() => sort = value),
                        ),
                        const Divider(height: 1, color: MedBuddyColors.divider),
                        _choiceRow<_SavedMedicationSortDirection>(
                          context: context,
                          title: text.isEnglish ? 'Order' : '표시 순서',
                          preferenceKey: 'direction',
                          value: direction,
                          values: const [
                            _SavedMedicationSortDirection.descending,
                            _SavedMedicationSortDirection.ascending,
                          ],
                          label: _directionLabel,
                          onSelected: (value) =>
                              setSheetState(() => direction = value),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('saved-medication-filter-apply'),
                      onPressed: () => Navigator.pop(sheetContext, true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.all(14),
                      ),
                      child: Text(
                        text.isEnglish ? 'Apply' : '적용',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (context.mounted && applied == true) onChanged(filter, sort, direction);
  }

  // 함수역할: 현재 값을 공통 설정 행에 표시하고 해당 항목의 선택지만 연다.
  // 매개변수: 행 식별자·제목·초안 값·선택지. 반환값: 선택 후 초안만 갱신하는 행.
  Widget _choiceRow<T extends Enum>({
    required BuildContext context,
    required String title,
    required String preferenceKey,
    required T value,
    required List<T> values,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) => MedBuddyPreferenceRow(
    key: ValueKey('saved-medication-$preferenceKey-row'),
    title: title,
    value: label(value),
    onTap: () async {
      final selected = await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: MedBuddyColors.surface,
        builder: (dialogContext) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                for (final option in values)
                  _option(
                    key: ValueKey(
                      'saved-medication-$preferenceKey-option-${option.name}',
                    ),
                    label: label(option),
                    selected: option == value,
                    onTap: () => Navigator.pop(dialogContext, option),
                  ),
              ],
            ),
          ),
        ),
      );
      if (context.mounted && selected != null) onSelected(selected);
    },
  );

  // 함수역할: 단일 선택 상태를 시각 표시와 접근성 정보로 함께 제공한다.
  // 매개변수: 식별 키·문구·선택 여부·선택 콜백. 반환값: 라디오 형식 행.
  Widget _option({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => Semantics(
    checked: selected,
    inMutuallyExclusiveGroup: true,
    child: ListTile(
      key: key,
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? MedBuddyColors.primary : MedBuddyColors.textMuted,
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      selected: selected,
      selectedColor: MedBuddyColors.primaryDark,
      selectedTileColor: MedBuddyColors.successSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

// 클래스명: _SavedMedicationFilteredEmptyState
// 역할: 빈 조회 결과에서 전체 목록 또는 약 등록으로 이동하게 한다.
// 주요 책임: 긴 문구와 큰 글씨에서도 모든 동작을 스크롤로 제공한다.
// 속성: filterMode는 조회 상태, onShowAll과 onRegister는 실제 화면 동작이다.
class _SavedMedicationFilteredEmptyState extends StatelessWidget {
  final bool isSearching;
  final _SavedMedicationFilterMode filterMode;
  final _SavedMedicationText text;
  final VoidCallback? onShowAll;
  final VoidCallback? onRegister;

  // 함수이름: _SavedMedicationFilteredEmptyState
  // 함수역할: 빈 결과의 조건과 연결 동작을 받는다.
  // 매개변수: filterMode, text, onShowAll, onRegister. 반환값: 빈 결과 위젯.
  const _SavedMedicationFilteredEmptyState({
    this.isSearching = false,
    required this.filterMode,
    required this.text,
    required this.onShowAll,
    required this.onRegister,
  });

  // 함수이름: build
  // 함수역할: 전체 보기와 복용 중 빈 상태의 등록 버튼을 구성한다.
  // 매개변수: context는 화면 위치. 반환값: 스크롤 가능한 빈 결과 안내.
  @override
  Widget build(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.medication_outlined,
            color: MedBuddyColors.textMuted,
            size: 42,
          ),
          const SizedBox(height: 14),
          Text(
            isSearching
                ? (text.isEnglish
                      ? 'No medications match your search.'
                      : '검색한 약이 없습니다.')
                : text.filteredEmptyMessage(filterMode),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            key: const Key('saved-medication-show-all'),
            onPressed: onShowAll,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(text.showAll, textAlign: TextAlign.center),
          ),
          if (filterMode == _SavedMedicationFilterMode.active) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('saved-medication-register'),
              onPressed: onRegister,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                backgroundColor: MedBuddyColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text(text.registerMedication, textAlign: TextAlign.center),
            ),
          ],
        ],
      ),
    ),
  );
}
