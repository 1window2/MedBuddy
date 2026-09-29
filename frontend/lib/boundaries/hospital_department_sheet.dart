part of 'check_nearby_pharmacy_ui_boundary.dart';

// 진료과를 이름순으로 묶고 오른쪽 초성으로 이동한다. 이동만으로 조회 조건을 바꾸지는 않는다.
class _HospitalDepartmentSheet extends StatefulWidget {
  const _HospitalDepartmentSheet({
    required this.selected,
    required this.english,
    required this.closeLabel,
    this.embedded = false,
    this.onSelected,
  });

  final String? selected;
  final bool english;
  final String closeLabel;
  final bool embedded;
  final ValueChanged<String>? onSelected;

  @override
  State<_HospitalDepartmentSheet> createState() =>
      _HospitalDepartmentSheetState();
}

class _HospitalDepartmentSheetState extends State<_HospitalDepartmentSheet> {
  final _scrollController = ScrollController();
  final _indexController = ScrollController();
  late final Map<String, List<String>> _groups;
  late final Map<String, GlobalKey> _anchors;
  String? _activeIndex;

  String _label(String code) {
    final label = _hospitalDepartments[code]!;
    return widget.english ? label.$2 : label.$1;
  }

  // 한글 음절의 초성을 구하고 영어 화면에서는 첫 알파벳을 사용한다.
  String _initial(String label) {
    final syllable = label.runes.first - 0xac00;
    if (!widget.english && syllable >= 0 && syllable <= 11171) {
      return 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ'[syllable ~/ 588];
    }
    return label[0].toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    final codes =
        _hospitalDepartments.keys.where((code) => code.isNotEmpty).toList()
          ..sort((a, b) => _label(a).compareTo(_label(b)));
    _groups = {};
    for (final code in codes) {
      (_groups[_initial(_label(code))] ??= []).add(code);
    }
    _anchors = {for (final initial in _groups.keys) initial: GlobalKey()};
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _indexController.dispose();
    super.dispose();
  }

  // 모든 과목을 배치해 큰 글씨로 행 높이가 달라져도 정확한 그룹 위치로 이동한다.
  void _jumpTo(String initial) {
    final target = _anchors[initial]?.currentContext;
    if (target == null) return;
    setState(() => _activeIndex = initial);
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      alignment: 0,
    );
  }

  Widget _option(String code) => ListTile(
    key: ValueKey('hospital-department-option-$code'),
    selected: widget.selected == code,
    leading: Icon(
      widget.selected == code
          ? Icons.radio_button_checked
          : Icons.radio_button_off,
    ),
    title: Text(_label(code)),
    onTap: () => widget.onSelected != null
        ? widget.onSelected!(code)
        : Navigator.pop(context, code),
  );

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: widget.embedded ? 1 : .78,
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
                    widget.embedded
                        ? (widget.english ? 'Select specialty' : '진료과목 선택')
                        : (widget.english ? 'Specialty' : '진료과목'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                if (!widget.embedded)
                  IconButton(
                    tooltip: widget.closeLabel,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    key: const Key('hospital-department-list'),
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(8, 8, 0, 24),
                    child: Column(
                      children: [
                        _option(''),
                        for (final group in _groups.entries) ...[
                          Container(
                            key: _anchors[group.key],
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              group.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: MedBuddyColors.primary,
                              ),
                            ),
                          ),
                          for (final code in group.value) _option(code),
                        ],
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 48,
                  child: SingleChildScrollView(
                    key: const Key('hospital-department-index'),
                    controller: _indexController,
                    child: Column(
                      children: [
                        for (final initial in _groups.keys)
                          Tooltip(
                            message: widget.english
                                ? 'Jump to $initial'
                                : '$initial 진료과목으로 이동',
                            child: Semantics(
                              button: true,
                              selected: _activeIndex == initial,
                              label: widget.english
                                  ? 'Jump to $initial'
                                  : '$initial 진료과목으로 이동',
                              excludeSemantics: true,
                              child: InkWell(
                                key: ValueKey(
                                  'hospital-department-index-$initial',
                                ),
                                onTap: () => _jumpTo(initial),
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Center(
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        color: MedBuddyColors.primary,
                                        fontWeight: _activeIndex == initial
                                            ? FontWeight.w900
                                            : FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
      ),
    ),
  );
}
