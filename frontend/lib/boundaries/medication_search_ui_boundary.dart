// File Name: medication_search_ui_boundary.dart
// Role: Searches medication products by name on their own, or picks one for manual entry.

import 'package:flutter/material.dart';

import '../controls/check_medication_detail_control.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_match_review_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/user_facing_error_message.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/medbuddy_page_header.dart';
import '../widgets/keep_words_text.dart';
import '../widgets/medbuddy_search_field.dart';
import '../widgets/medication_thumbnail.dart';
import 'check_medication_detail_ui_boundary.dart';

// 클래스명: MedicationSearchUI
// 역할: 약 이름으로 제품을 찾고 상세 보기 또는 수동 등록용 선택을 제공한다.
// 주요 책임: 조회 결과를 표시하고 선택 모드에서는 사용자의 약품 확인을 받는다.
// 속성: userSetting (UserSetting): 표시·검색 설정; selectionMode (bool): 선택 반환 여부; initialQuery (String): 초기 검색어; lookupControl (CheckMedicationDetail?): 외부 소유 조회기.
class MedicationSearchUI extends StatefulWidget {
  // 함수이름: MedicationSearchUI
  // 함수역할: 검색어와 화면 모드를 설정하며 주입된 조회기의 소유권은 호출자에게 남긴다.
  // 매개변수: key (Key?): 위젯 키; userSetting (UserSetting): 설정; selectionMode (bool): 선택 모드; initialQuery (String): 검색어; lookupControl (CheckMedicationDetail?): 조회기.
  // 반환값: 새 MedicationSearchUI.
  const MedicationSearchUI({
    super.key,
    required this.userSetting,
    this.selectionMode = false,
    this.initialQuery = '',
    this.lookupControl,
  });

  final UserSetting userSetting;
  final bool selectionMode;
  final String initialQuery;
  final CheckMedicationDetail? lookupControl;

  // 함수이름: createState
  // 함수역할: 검색 요청과 결과 선택을 관리할 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _MedicationSearchUIState.
  @override
  State<MedicationSearchUI> createState() => _MedicationSearchUIState();
}

// 클래스명: _MedicationSearchUIState
// 역할: 검색 결과와 조회·화면 전환의 중복 실행을 관리한다.
// 주요 책임: 이전 검색어의 응답을 버리고 후보 확인창의 중복 열기·닫기를 막는다.
// 속성: _generation (int): 요청 세대; _results (List<MedicationDetail>): 현재 후보; _retryAt (DateTime?): 재시도 가능 시각; _isOpening (bool): 결과 화면 진행 여부.
class _MedicationSearchUIState extends State<MedicationSearchUI> {
  late final TextEditingController _query;
  late final CheckMedicationDetail _lookup;
  List<MedicationDetail> _results = const [];
  int _generation = 0;
  bool _loading = false;
  bool _searched = false;
  bool _isOpening = false;
  String? _error;
  DateTime? _retryAt;

  // 함수이름: _english
  // 함수역할: 현재 사용자 설정에서 검색 화면의 언어를 읽는다.
  // 매개변수: 없음.
  // 반환값: 영어 설정이면 true.
  bool get _english => widget.userSetting.isEnglish;

  // Function Name: _busyMessage
  // Description: Chooses the retry notice used while the lookup service is occupied.
  // Parameters: None.
  // Returns: Localized busy-search message.
  String get _busyMessage => _english
      ? 'Another search is in progress. Please try again shortly.'
      : '다른 검색이 진행 중입니다. 잠시 후 다시 검색해 주세요.';

  // 함수이름: initState
  // 함수역할: 초기 검색어를 넣고 검색 모드 설정을 읽는 조회기를 연결한다.
  // 매개변수: 없음.
  // 반환값: 없음. 외부 조회기가 없을 때만 내부 조회기를 만든다.
  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    _lookup =
        widget.lookupControl ??
        CheckMedicationDetail(
          readSearchMode: () => widget.userSetting.medicationSearchMode,
        );
  }

  // 함수이름: dispose
  // 함수역할: 응답 세대를 무효화하고 입력기와 직접 만든 조회기를 해제한다.
  // 매개변수: 없음.
  // 반환값: 없음. 주입된 조회기는 해제하지 않는다.
  @override
  void dispose() {
    _generation++;
    _query.dispose();
    if (widget.lookupControl == null) _lookup.dispose();
    super.dispose();
  }

  // 함수이름: _queryChanged
  // 함수역할: 검색어가 바뀌면 이전 검색 결과를 지우되 진행 중인 요청의 잠금은 그 요청이 끝날 때까지 유지한다.
  // 매개변수: 없음.
  // 반환값: 없음.
  void _queryChanged() {
    setState(() {
      _generation++;
      _results = const [];
      _searched = false;
      _error = null;
      // 진행 중 요청은 끝날 때까지 유지해 입력 변경으로 중복 조회가 생기지 않게 한다.
    });
  }

  // Function Name: _search
  // Description: Looks the query up once per submit and keeps only replies to the current query.
  // Parameters: None. Returns: Completes when the results or the error are shown.
  Future<void> _search() async {
    final query = _query.text.trim();
    if (_loading || query.isEmpty) return;
    if (_retryAt?.isAfter(DateTime.now()) ?? false) {
      setState(() => _error = _busyMessage);
      return;
    }
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _results = const [];
      _searched = false;
    });
    List<MedicationDetail> results = const [];
    String? error;
    try {
      final detail = await _lookup.requestMedicationDetail(
        MedicationSchedule(
          medicationName: query,
          nameCorrectionSource: 'user_edit',
        ),
      );
      if (detail != null) results = [detail];
    } on MedicationMatchReview catch (review) {
      results = review.candidates;
    } on MedicationLookupBusy catch (busy) {
      _retryAt = busy.retryAt;
      error = _busyMessage;
    } catch (failure) {
      // 하루 한도·로그인 만료·지연을 연결 문제로 뭉뚱그리지 않고 처방 조회와 같은 안내를 쓴다.
      error = UserFacingErrorMessage.resolve(
        failure,
        isEnglish: _english,
        context: UserFacingErrorContext.medicationLookup,
      );
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      // 검색어를 바꾼 뒤 도착한 예전 후보는 선택할 수 없게 한다.
      if (generation != _generation) return;
      final seen = <String>{};
      _results = results
          .where(
            (item) =>
                item.itemName.trim().isNotEmpty &&
                seen.add(
                  item.itemSeq.isNotEmpty
                      ? item.itemSeq
                      : '${item.itemName}|${item.manufacturer}',
                ),
          )
          .toList();
      _searched = true;
      _error = error;
    });
  }

  // 함수이름: _open
  // 함수역할: 현재 화면에서 결과 열기를 한 번만 진행하고 완료·예외 시 잠금을 해제한다.
  // 매개변수: medication (MedicationDetail): 선택한 검색 결과.
  // 반환값: 상세 화면 또는 선택 확인이 끝나면 완료; 진행 중·비활성 경로이면 즉시 완료.
  Future<void> _open(MedicationDetail medication) async {
    if (_isOpening || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _isOpening = true;
    try {
      await _openResult(medication);
    } finally {
      _isOpening = false;
    }
  }

  // 함수이름: _openResult
  // 함수역할: 선택 모드에서는 확인 후 현재 검색 화면에만 약품을 반환하고, 일반 모드에서는 상세 화면을 연다.
  // 매개변수: medication (MedicationDetail): 표시하거나 반환할 후보.
  // 반환값: 취소·화면 이탈 시 반환하지 않고 완료되는 Future<void>.
  Future<void> _openResult(MedicationDetail medication) async {
    if (widget.selectionMode) {
      var dismissed = false;
      // 함수이름: close
      // 함수역할: 현재 확인창을 한 번만 닫아 연속 탭으로 검색 화면까지 닫히지 않게 한다.
      // 매개변수: dialogContext (BuildContext): 확인창 위치; confirmed (bool): 선택 확정 여부.
      // 반환값: 없음. 확인창 결과로 confirmed를 전달한다.
      void close(BuildContext dialogContext, bool confirmed) {
        if (dismissed || ModalRoute.of(dialogContext)?.isCurrent != true) {
          return;
        }
        dismissed = true;
        Navigator.pop(dialogContext, confirmed);
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: KeepWordsText(_english ? 'Confirm medication' : '약품 정보 확인'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeepWordsText(
                  medication.itemName,
                  style: MedBuddyTextStyles.menuTitle,
                ),
                if (medication.manufacturer.isNotEmpty)
                  KeepWordsText(medication.manufacturer),
                const SizedBox(height: 16),
                KeepWordsText(
                  _english
                      ? 'Check that the full name, strength and form match your medication.'
                      : '약의 전체 이름, 함량과 제형이 가지고 있는 약과 같은지 확인해 주세요.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => close(context, false),
              child: Text(_english ? 'Cancel' : '취소'),
            ),
            FilledButton(
              onPressed: () => close(context, true),
              child: Text(_english ? 'Select' : '선택'),
            ),
          ],
        ),
      );
      if (!mounted ||
          confirmed != true ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      Navigator.pop(context, medication);
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CheckMedicationDetailUI(
          medicationDetail: medication,
          userSetting: widget.userSetting,
        ),
      ),
    );
  }

  // Function Name: build
  // Description: Displays the query field, loading/error/empty states and selectable medication results.
  // Parameters: context (BuildContext): Theme and navigation location.
  // Returns: Search Scaffold; submit is disabled while loading or the query is empty.
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: MedBuddyColors.pageBackground,
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          MedBuddyPageHeader(
            title: _english ? 'Find medication' : '약 검색',
            subtitle: _english
                ? 'Search by medication name.'
                : '약 이름으로 약품 정보를 찾습니다.',
            onBackRequested: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: MedBuddySearchField(
                        inputKey: const Key('medication-search-query'),
                        controller: _query,
                        label: _english ? 'Medication name' : '약 이름',
                        hint: _english ? 'Enter medication name' : '약 이름 입력',
                        isEnglish: _english,
                        onChanged: _queryChanged,
                        onSubmitted: _search,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      key: const Key('medication-search-submit'),
                      tooltip: _english ? 'Search' : '검색',
                      onPressed: _loading || _query.text.trim().isEmpty
                          ? null
                          : _search,
                      icon: const Icon(Icons.search),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_error != null)
                  KeepWordsText(_error!, style: MedBuddyTextStyles.menuBody)
                else if (_searched && _results.isEmpty)
                  KeepWordsText(
                    _english
                        ? 'No medications found. Try another name.'
                        : '찾은 약이 없어요. 약 이름을 바꿔 검색해 주세요.',
                    style: MedBuddyTextStyles.menuBody,
                  )
                else if (_results.isNotEmpty)
                  MedBuddySearchPanel(
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < _results.length;
                          index++
                        ) ...[
                          if (index > 0) const Divider(height: 1),
                          ListTile(
                            key: Key('medication-search-result-$index'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            leading: MedicationThumbnail(
                              imageUrl: _results[index].imageUrl,
                            ),
                            title: KeepWordsText(
                              _results[index].itemName,
                              style: MedBuddyTextStyles.menuTitle,
                            ),
                            subtitle: _results[index].manufacturer.isEmpty
                                ? null
                                : KeepWordsText(
                                    _results[index].manufacturer,
                                    style: MedBuddyTextStyles.menuBody,
                                  ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(_results[index]),
                          ),
                        ],
                      ],
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
