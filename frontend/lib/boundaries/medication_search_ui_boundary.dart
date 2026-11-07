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

// Class Name: MedicationSearchUI
// Role: Name search over the existing medication lookup.
// Responsibilities:
// - Opens a result's detail, or in selection mode returns the confirmed result to the caller.
class MedicationSearchUI extends StatefulWidget {
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

  @override
  State<MedicationSearchUI> createState() => _MedicationSearchUIState();
}

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

  bool get _english => widget.userSetting.isEnglish;

  String get _busyMessage => _english
      ? 'Another search is in progress. Please try again shortly.'
      : '다른 검색이 진행 중입니다. 잠시 후 다시 검색해 주세요.';

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

  @override
  void dispose() {
    _generation++;
    _query.dispose();
    if (widget.lookupControl == null) _lookup.dispose();
    super.dispose();
  }

  // Function Name: _queryChanged
  // Description: Drops results of the previous query; a request in flight stays until it ends.
  // Parameters: None. Returns: None.
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

  // Function Name: _open
  // Description: Returns the confirmed result in selection mode, otherwise opens its detail.
  // Parameters:
  // - medication (MedicationDetail): Chosen result.
  // Returns: Completes when the dialog or detail screen closes.
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

  Future<void> _openResult(MedicationDetail medication) async {
    if (widget.selectionMode) {
      var dismissed = false;
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
          title: Text(_english ? 'Confirm medication' : '약품 정보 확인'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(medication.itemName, style: MedBuddyTextStyles.menuTitle),
                if (medication.manufacturer.isNotEmpty)
                  Text(medication.manufacturer),
                const SizedBox(height: 16),
                Text(
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
                            title: Text(
                              _results[index].itemName,
                              style: MedBuddyTextStyles.menuTitle,
                            ),
                            subtitle: _results[index].manufacturer.isEmpty
                                ? null
                                : Text(
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
