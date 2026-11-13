// 파일명: hospital_department_sheet.dart
// 역할: 진료과·증상 검색과 이름순 색인 탐색을 제공한다.

part of 'check_nearby_pharmacy_ui_boundary.dart';

// 클래스명: _HospitalDepartmentSheet
// 역할: 진료과를 검색하거나 초성 색인으로 고르는 화면.
// 주요 책임: 선택 결과를 포함 화면의 콜백 또는 경로 결과로 전달한다.
// 속성: selected (String?): 현재 코드; english (bool): 언어; closeLabel (String): 닫기; embedded (bool): 포함 화면 여부; onSelected (ValueChanged<String>?): 선택 처리.
class _HospitalDepartmentSheet extends StatefulWidget {
  // 함수이름: _HospitalDepartmentSheet
  // 함수역할: 선택 진료과·언어와 독립 또는 포함 화면의 결과 전달 방식을 설정한다.
  // 매개변수: selected (String?): 코드; english (bool): 언어; closeLabel (String): 닫기; embedded (bool): 포함 여부; onSelected (ValueChanged<String>?): 선택.
  // 반환값: 새 _HospitalDepartmentSheet.
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

  // 함수이름: createState
  // 함수역할: 검색어와 진료과 색인 스크롤 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _HospitalDepartmentSheetState.
  @override
  State<_HospitalDepartmentSheet> createState() =>
      _HospitalDepartmentSheetState();
}

// Class Name: _HospitalDepartmentSheetState
// Role: Supports department search and initial-letter navigation at large text sizes.
// Responsibilities: Groups localized names, keeps anchors for real row heights and handles embedded layouts.
// Attributes: _query (TextEditingController): search; _scrollController/_indexController (ScrollController): lists; _groups (Map<String,List<String>>): initials; _anchors (Map<String,GlobalKey>): targets; _activeIndex (String?): selection.
class _HospitalDepartmentSheetState extends State<_HospitalDepartmentSheet> {
  final _query = TextEditingController();
  final _scrollController = ScrollController();
  final _indexController = ScrollController();
  late final Map<String, List<String>> _groups;
  late final Map<String, GlobalKey> _anchors;
  String? _activeIndex;

  // 함수이름: _label
  // 함수역할: 알려진 진료과 코드의 현재 언어 이름을 읽는다.
  // 매개변수: code (String): _hospitalDepartments에 있는 코드.
  // 반환값: 진료과 이름; 알 수 없는 코드는 허용하지 않는다.
  String _label(String code) {
    final label = _hospitalDepartments[code]!;
    return widget.english ? label.$2 : label.$1;
  }

  // 함수이름: _initial
  // 함수역할: 한국어 음절이면 초성을 계산하고 그 외에는 첫 글자를 대문자로 만든다.
  // 매개변수: label (String): 비어 있지 않은 진료과 이름.
  // 반환값: 색인에 사용할 첫 글자.
  String _initial(String label) {
    final syllable = label.runes.first - 0xac00;
    if (!widget.english && syllable >= 0 && syllable <= 11171) {
      return 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ'[syllable ~/ 588];
    }
    return label[0].toUpperCase();
  }

  // 함수이름: initState
  // 함수역할: 전체 항목을 제외한 진료과를 표시 이름순으로 정렬하고 초성별 그룹과 스크롤 앵커를 만든다.
  // 매개변수: 없음.
  // 반환값: 없음.
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

  // 함수이름: dispose
  // 함수역할: 검색 입력과 본문·색인 스크롤 제어기를 해제한다.
  // 매개변수: 없음.
  // 반환값: 없음.
  @override
  void dispose() {
    _query.dispose();
    _scrollController.dispose();
    _indexController.dispose();
    super.dispose();
  }

  // 함수이름: _jumpTo
  // 함수역할: 대상 그룹이 배치되었으면 실제 높이를 기준으로 해당 초성 위치까지 이동한다.
  // 매개변수: initial (String): 그룹 초성.
  // 반환값: 없음. 앵커가 없으면 무시한다.
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

  // 함수이름: _option
  // 함수역할: 선택 상태와 진료과 이름을 표시하고 콜백이 있으면 호출하며 없으면 코드로 경로를 닫는다.
  // 매개변수: code (String): 유효한 진료과 코드.
  // 반환값: 선택 가능한 ListTile.
  Widget _option(String code) => ListTile(
    key: ValueKey('hospital-department-option-$code'),
    selected: widget.selected == code,
    leading: Icon(
      widget.selected == code
          ? Icons.radio_button_checked
          : Icons.radio_button_off,
    ),
    title: Text(
      _label(code),
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0,
      ),
    ),
    onTap: () => widget.onSelected != null
        ? widget.onSelected!(code)
        : Navigator.pop(context, code),
  );

  // Function Name: build
  // Description: Shows search results or initial-grouped departments with scroll access to both list and index.
  // Parameters: context (BuildContext): Viewport and keyboard constraints.
  // Returns: Department picker sized for embedded, keyboard-open or standalone presentation.
  @override
  Widget build(BuildContext context) {
    final searching = _query.text.trim().isNotEmpty;
    final results = FindHospitalDepartment.search(
      _query.text,
      _hospitalDepartments,
    );
    return FractionallySizedBox(
      heightFactor:
          widget.embedded || MediaQuery.viewInsetsOf(context).bottom > 0
          ? 1
          : .78,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 +
                (widget.embedded ? 0 : MediaQuery.viewInsetsOf(context).bottom),
          ),
          child: Column(
            children: [
              MedBuddySearchField(
                inputKey: const Key('hospitalDepartmentSearchInput'),
                clearKey: const Key('hospitalDepartmentSearchClear'),
                controller: _query,
                label: widget.english
                    ? 'Specialty, symptom or condition'
                    : '진료과·증상·질병 검색',
                hint: widget.english
                    ? 'Cough, cold, internal medicine'
                    : '기침, 감기, 내과',
                isEnglish: widget.english,
                onChanged: () {
                  setState(() => _activeIndex = null);
                  if (_scrollController.hasClients) _scrollController.jumpTo(0);
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: MedBuddySearchPanel(
                  key: const Key('hospital-department-panel'),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: KeepWordsText(
                                searching
                                    ? (widget.english
                                          ? 'Related specialties'
                                          : '관련 진료과목')
                                    : widget.embedded
                                    ? (widget.english
                                          ? 'Select specialty'
                                          : '진료과목 선택')
                                    : (widget.english ? 'Specialty' : '진료과목'),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
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
                                    if (searching) ...[
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: KeepWordsText(
                                          results.isEmpty ||
                                                  FindHospitalDepartment.needsUrgentHelp(
                                                    _query.text,
                                                  )
                                              ? (widget.english
                                                    ? 'For severe symptoms, call 119 or seek emergency care.'
                                                    : '심한 증상이 있으면 119 또는 응급실에 도움을 요청하세요.')
                                              : (widget.english
                                                    ? 'Related specialties, not a diagnosis.'
                                                    : '진단이 아닌 관련 진료과 안내입니다.'),
                                          style: MedBuddyTextStyles.menuBody
                                              .copyWith(
                                                color: MedBuddyColors.textMuted,
                                              ),
                                        ),
                                      ),
                                      if (results.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: KeepWordsText(
                                            widget.english
                                                ? 'No matching specialties'
                                                : '검색 결과가 없어요',
                                            style: MedBuddyTextStyles.menuBody,
                                          ),
                                        ),
                                      for (final code in results) _option(code),
                                    ] else ...[
                                      _option(''),
                                      for (final group in _groups.entries) ...[
                                        Container(
                                          key: _anchors[group.key],
                                          alignment: Alignment.centerLeft,
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            12,
                                            16,
                                            4,
                                          ),
                                          child: Text(
                                            group.key,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              height: 1.35,
                                              letterSpacing: 0,
                                              color: MedBuddyColors.primary,
                                            ),
                                          ),
                                        ),
                                        for (final code in group.value)
                                          _option(code),
                                      ],
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (!searching) const VerticalDivider(width: 1),
                            if (!searching)
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
                                                      color: MedBuddyColors
                                                          .primary,
                                                      fontSize: 14,
                                                      height: 1.35,
                                                      letterSpacing: 0,
                                                      fontWeight:
                                                          _activeIndex ==
                                                              initial
                                                          ? FontWeight.w700
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
