// 파일명: nearby_care_filter_sheet.dart
// 역할: 병원·약국의 운영 조건과 조회 날짜 초안을 적용 전까지 보관한다.

part of 'check_nearby_pharmacy_ui_boundary.dart';

typedef _NearbyCareConditions = ({_PharmacyFilter filter, DateTime? date});

// 클래스명: _NearbyCareFilterSheet
// 역할: 시설 검색 조건을 한 번에 확정하는 선택창.
// 주요 책임: 초기 조건을 복사하고 적용 전에는 검색을 요청하지 않는다.
// 속성: filter (_PharmacyFilter): 조건; selectedDate (DateTime?): 날짜; now (DateTime Function()): 시계; hospitals (bool): 병원; text (_NearbyPharmacyText): 문구; filterLabel (String Function): 조건 이름.
class _NearbyCareFilterSheet extends StatefulWidget {
  // 함수이름: _NearbyCareFilterSheet
  // 함수역할: 초기 검색 조건·날짜와 표시용 의존성을 연결한다.
  // 매개변수: filter (_PharmacyFilter): 조건; selectedDate (DateTime?): 날짜; now (DateTime Function()): 시계; hospitals (bool): 병원; text (_NearbyPharmacyText): 문구; filterLabel (String Function(_PharmacyFilter)): 이름.
  // 반환값: 새 _NearbyCareFilterSheet.
  const _NearbyCareFilterSheet({
    required this.filter,
    required this.selectedDate,
    required this.now,
    required this.hospitals,
    required this.text,
    required this.filterLabel,
  });

  final _PharmacyFilter filter;
  final DateTime? selectedDate;
  final DateTime Function() now;
  final bool hospitals;
  final _NearbyPharmacyText text;
  final String Function(_PharmacyFilter) filterLabel;

  // 함수이름: createState
  // 함수역할: 적용 전의 조건·날짜 초안을 관리할 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _NearbyCareFilterSheetState.
  @override
  State<_NearbyCareFilterSheet> createState() => _NearbyCareFilterSheetState();
}

// Class Name: _NearbyCareFilterSheetState
// Role: Keeps date and operating-condition edits local until applied.
// Responsibilities: Clamps calendar choices and clears selected dates for the open-now filter.
// Attributes: _filter (_PharmacyFilter): draft filter; _date (DateTime?): draft day.
class _NearbyCareFilterSheetState extends State<_NearbyCareFilterSheet> {
  late _PharmacyFilter _filter = widget.filter;
  late DateTime? _date = widget.selectedDate;

  // Function Name: _pickDate
  // Description: Picks a date from seven calendar days ago through 366 days ahead, avoiding DST duration drift.
  // Parameters: None.
  // Returns: Future<void>; cancellation preserves the draft, selection stores noon on the chosen day.
  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(widget.now());
    // 24시간 단위로 더하면 서머타임 전환일을 지날 때 범위가 하루 어긋나므로 달력 날짜로 계산한다.
    final first = DateUtils.addDaysToDate(today, -7);
    final last = DateUtils.addDaysToDate(today, 366);
    final date = _date ?? today;
    final selected = await showDatePicker(
      context: context,
      initialDate: date.isBefore(first)
          ? first
          : (date.isAfter(last) ? last : date),
      firstDate: first,
      lastDate: last,
    );
    if (!mounted || selected == null) return;
    setState(
      () => _date = DateTime(selected.year, selected.month, selected.day, 12),
    );
  }

  // Function Name: _heading
  // Description: Creates a compact subsection heading above filter choices.
  // Parameters: label (String): heading text.
  // Returns: Padded Text widget.
  Widget _heading(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: KeepWordsText(
      label,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    ),
  );

  // Function Name: build
  // Description: Builds a bounded-height filter sheet with scrollable choices and explicit apply/cancel actions.
  // Parameters: context (BuildContext): Sheet location.
  // Returns: Condition editor; changes are returned only on apply.
  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final current = _filter == _PharmacyFilter.openNow;
    return FractionallySizedBox(
      heightFactor: .85,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: KeepWordsText(
                      text.filterPickerTitle,
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: text.close,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                key: const Key('care-filter-content'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _heading(text.isEnglish ? 'Date' : '날짜'),
                    OutlinedButton.icon(
                      key: const Key('care-filter-date'),
                      onPressed: current ? null : _pickDate,
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        minimumSize: const Size(0, 48),
                      ),
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        text.searchDate(
                          current ? widget.now() : (_date ?? widget.now()),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _heading(
                      widget.hospitals
                          ? (text.isEnglish ? 'Consultation status' : '진료 상태')
                          : (text.isEnglish ? 'Business status' : '영업 상태'),
                    ),
                    for (final filter in _PharmacyFilter.values) ...[
                      _option(filter),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('care-filter-apply'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () => Navigator.pop(context, (
                    filter: _filter,
                    date: current ? null : _date,
                  )),
                  icon: const Icon(Icons.check),
                  label: Text(text.isEnglish ? 'Apply' : '적용'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Function Name: _option
  // Description: Builds a selectable condition row; choosing open-now clears any historical/future date.
  // Parameters: filter (_PharmacyFilter): condition to offer.
  // Returns: Accessible selection row reflecting the draft choice.
  Widget _option(_PharmacyFilter filter) {
    final selected = filter == _filter;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? MedBuddyColors.successSurface : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: MedBuddyRadii.small,
          side: BorderSide(
            color: selected ? MedBuddyColors.primary : MedBuddyColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('pharmacy-filter-option-${filter.name}'),
          borderRadius: MedBuddyRadii.small,
          onTap: () => setState(() {
            _filter = filter;
            if (filter == _PharmacyFilter.openNow) _date = null;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KeepWordsText(
                        widget.filterLabel(filter),
                        style: const TextStyle(
                          color: MedBuddyColors.textStrong,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      KeepWordsText(
                        widget.text.filterDescription(filter),
                        style: const TextStyle(
                          color: MedBuddyColors.textMuted,
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
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
