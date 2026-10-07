part of 'check_nearby_pharmacy_ui_boundary.dart';

typedef _NearbyCareConditions = ({_PharmacyFilter filter, DateTime? date});

// 병원과 약국이 같은 날짜·운영 상태 선택창을 사용한다. 적용 전에는 검색하지 않는다.
class _NearbyCareFilterSheet extends StatefulWidget {
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

  @override
  State<_NearbyCareFilterSheet> createState() => _NearbyCareFilterSheetState();
}

class _NearbyCareFilterSheetState extends State<_NearbyCareFilterSheet> {
  late _PharmacyFilter _filter = widget.filter;
  late DateTime? _date = widget.selectedDate;

  // 날짜 선택 취소는 기존 초안을 유지한다. 과거 조회일도 달력 범위 안으로 제한한다.
  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(widget.now());
    final first = today.subtract(const Duration(days: 7));
    final last = today.add(const Duration(days: 366));
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

  Widget _heading(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    ),
  );

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
                    child: Text(
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
                        shape: RoundedRectangleBorder(
                          borderRadius: MedBuddyRadii.small,
                        ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: MedBuddyRadii.small,
                    ),
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

  // 현재 영업 조건으로 돌아가면 과거·미래 날짜 선택을 제거한다.
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
                      Text(
                        widget.filterLabel(filter),
                        style: const TextStyle(
                          color: MedBuddyColors.textStrong,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
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
