part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_filter_widgets.dart
// 역할: 저장 약품의 복용 상태 필터와 필터별 빈 결과를 제공한다.

// 클래스명: _SavedMedicationFilterControl
// 역할: 저장 약품의 상태·날짜 기준·정렬 방향을 함께 선택하는 버튼.
// 주요 책임: 선택 초안을 시트에 보관하고 적용 시에만 부모 목록을 갱신한다.
// 속성: filterMode/sortMode/sortDirection: 현재 조건 열거값; text (_SavedMedicationText): 문구; enabled (bool): 활성; onChanged (void Function): 세 조건 전달.
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

  // 함수이름: _SavedMedicationFilterControl
  // 함수역할: 현재 필터·정렬 상태와 적용 콜백을 연결한다.
  // 매개변수: filterMode (_SavedMedicationFilterMode): 상태; sortMode (_SavedMedicationSortMode): 날짜 기준; sortDirection (_SavedMedicationSortDirection): 방향; text (_SavedMedicationText): 문구; enabled (bool): 활성; onChanged: 적용 함수.
  // 반환값: 새 _SavedMedicationFilterControl.
  const _SavedMedicationFilterControl({
    required this.filterMode,
    required this.sortMode,
    required this.sortDirection,
    required this.text,
    required this.enabled,
    required this.onChanged,
  });

  // 함수이름: build
  // 함수역할: 선택한 상태와 정렬 기준·방향을 표시하고 활성 상태에서만 선택창을 연다.
  // 매개변수: context (BuildContext): 선택창 위치.
  // 반환값: 조회 조건 OutlinedButton.
  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: const Key('saved-medication-filter-selector'),
    onPressed: enabled ? () => _showFilterPicker(context) : null,
    style: OutlinedButton.styleFrom(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      side: const BorderSide(color: MedBuddyColors.outline),
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
              KeepWordsText(
                text.selectedFilter(filterMode),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MedBuddyColors.textStrong,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              KeepWordsText(
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

  // 함수이름: _sortLabel
  // 함수역할: 등록일 또는 복용일에 해당하는 정렬 기준 문구를 선택한다.
  // 매개변수: mode (_SavedMedicationSortMode): 정렬 기준.
  // 반환값: 현재 언어의 날짜 기준 라벨.
  String _sortLabel(_SavedMedicationSortMode mode) =>
      mode == _SavedMedicationSortMode.registeredDate
      ? text.sortByRegisteredDate
      : text.sortByMedicationDate;
  // 함수이름: _directionLabel
  // 함수역할: 내림차순은 최신순, 오름차순은 오래된순으로 표현한다.
  // 매개변수: direction (_SavedMedicationSortDirection): 정렬 방향.
  // 반환값: 현재 언어의 정렬 방향 문구.
  String _directionLabel(_SavedMedicationSortDirection direction) =>
      direction == _SavedMedicationSortDirection.descending
      ? (text.isEnglish ? 'Newest first' : '최신순')
      : (text.isEnglish ? 'Oldest first' : '오래된순');

  // 함수이름: _showFilterPicker
  // 함수역할: 조건 초안을 높이 제한과 스크롤이 있는 선택창에 보관하고, 적용을 선택한 살아 있는 화면에만 변경을 전달한다.
  // 매개변수: context (BuildContext): 선택창을 여는 위치.
  // 반환값: 선택창 종료 Future<void>; 취소는 기존 조건을 유지한다.
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
                        child: KeepWordsText(
                          text.filterTitle,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
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

  // Function Name: _choiceRow
  // Description: Shows one draft condition and opens its enum choices, applying a result only while the initiating context remains mounted.
  // Parameters: context (BuildContext): sheet location; title/preferenceKey (String): heading/key; value (T): current draft; values (List<T>): options; label (String Function(T)): display text; onSelected (ValueChanged<T>): draft update.
  // Returns: MedBuddyPreferenceRow; T is an Enum.
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
                KeepWordsText(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
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

  // Function Name: _option
  // Description: Exposes one filter choice as a mutually exclusive accessible radio row.
  // Parameters: key (Key): row identity; label (String): choice text; selected (bool): checked state; onTap (VoidCallback): select this choice.
  // Returns: A ListTile with checked semantics.
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
      title: KeepWordsText(
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
      shape: RoundedRectangleBorder(borderRadius: MedBuddyRadii.small),
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
  // 함수역할: 검색 결과 없음과 복용 상태 필터의 빈 결과를 구분하고 전체 보기·등록 동작을 연결한다.
  // 매개변수:
  // - isSearching (bool): true이면 검색어에 맞는 약이 없다는 문구를 사용하며 기본값은 false이다.
  // - filterMode (_SavedMedicationFilterMode): 검색 중이 아닐 때 빈 결과를 설명할 복약 상태 필터.
  // - text (_SavedMedicationText): 현재 언어의 안내와 버튼 문구.
  // - onShowAll, onRegister (VoidCallback?): 전체 약 보기와 새 약 등록 콜백. null인 동작은 비활성화한다.
  // 반환값: 조건에 맞는 빈 결과 안내 위젯.
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
  Widget build(BuildContext context) => _SavedMedicationStateShell(
    icon: Icons.medication_outlined,
    gap: 20,
    message: KeepWordsText(
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
    actions: [
      OutlinedButton(
        key: const Key('saved-medication-show-all'),
        onPressed: onShowAll,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        child: KeepWordsText(text.showAll, textAlign: TextAlign.center),
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
          ),
          icon: const Icon(Icons.add),
          label: KeepWordsText(text.registerMedication, textAlign: TextAlign.center),
        ),
      ],
    ],
  );
}
