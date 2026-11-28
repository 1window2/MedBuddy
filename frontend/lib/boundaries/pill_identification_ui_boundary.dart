// File Name: pill_identification_ui_boundary.dart
// Role: UI boundaries and helpers for pill-photo identification, candidate comparison, duplicate resolution, and schedule review.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../widgets/medbuddy_page_header.dart';
import '../widgets/medication_review_image_gallery.dart';
import 'package:image_picker/image_picker.dart';

import '../controls/identify_pill_control.dart';
import '../controls/resolve_duplicate_pill_selection_control.dart';
import '../entities/identified_pill_save_request_entity.dart';
import '../entities/medication_image_url_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/pill_identification_entity.dart';
import '../entities/user_setting_entity.dart';
import '../widgets/medbuddy_notice.dart';
import '../theme/medbuddy_theme.dart';
import 'medication_schedule_review_ui_boundary.dart';
import 'medication_photo_source_sheet.dart';
import 'medication_image_viewer_boundary.dart';
import '../widgets/keep_words_text.dart';

// 클래스명: PillIdentificationUI
// 역할: 한 장의 알약 사진에서 알약을 찾고 후보를 고른 뒤 복약 일정 검토를 거쳐 공통 결과 단계로 넘긴다.
// 주요 책임:
// - 화면 State가 사용할 설정과 외부 의존성을 보관한다.
// 속성:
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시에 사용할 사용자 설정.
// - control (IdentifyPill?): 화면의 조회·변경 요청을 처리할 컨트롤러.
// - onReviewRequested: 검토한 일정을 공통 결과 단계에 넘긴다. 이 콜백은 저장을 실행하지 않는다.
class PillIdentificationUI extends StatefulWidget {
  final UserSetting userSetting;
  final IdentifyPill? control;
  // 선택·중복 정리한 일정을 공통 결과 단계에 넘긴다. 이 콜백은 저장을 실행하지 않는다.
  final bool Function(List<IdentifiedPillSaveRequest>) onReviewRequested;

  // 함수이름: PillIdentificationUI
  // 함수역할: 알약 사진 식별과 후보 검토에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시에 사용할 사용자 설정.
  // - control (IdentifyPill?): 화면의 조회·변경 요청을 처리할 컨트롤러.
  // - onReviewRequested: 검토한 일정을 받으면 true를 반환하는 결과 단계 인계 콜백.
  // 반환값: 입력 설정이 반영된 PillIdentificationUI 인스턴스.
  const PillIdentificationUI({
    super.key,
    required this.userSetting,
    this.control,
    required this.onReviewRequested,
  });

  // Function Name: createState
  // Description: Creates the state object that coordinates the pill photo, candidate selection and schedule review.
  // Parameters:
  // - None.
  // Returns: A new _PillIdentificationUIState instance.
  @override
  State<PillIdentificationUI> createState() => _PillIdentificationUIState();
}

// Class Name: _PillPhotoDraft
// Role: One detected pill's photos, analysis and review draft.
// Responsibilities: Keeps image inputs separate from analysis, selection and reviewed schedule so refinements and repeated reviews retain useful work.
// Attributes: frontImage/backImage: source bytes; result/selectedItemSeq/errorMessage: analysis state; sourceRegion/croppedFrontImage: refinement input; reviewedSchedule: reviewed values; visibleCandidateCount: presentation.
class _PillPhotoDraft {
  Uint8List? frontImage;
  Uint8List? backImage;
  PillIdentificationResult? result;
  String? selectedItemSeq;
  String errorMessage = '';
  PillBoundingBox? sourceRegion;
  Uint8List? croppedFrontImage;
  int visibleCandidateCount = 5;
  // 일정 검토에서 확인한 값. 다시 확인할 때 입력을 되살린다.
  MedicationSchedule? reviewedSchedule;

  // 함수이름: hasFrontImage
  // 함수역할: 필수 앞면 사진 바이트가 있는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get hasFrontImage => frontImage != null;
}

// 클래스명: _DuplicatePillResolution
// 역할: 동일 약품으로 선택한 사진의 중복 처리 방식.
// 주요 책임: 같은 일정만 병합하거나 사진별 별도 일정을 유지하도록 구분한다.
// 속성: mergeMatchingSchedules/keepSeparate: 처리 값.
enum _DuplicatePillResolution { mergeMatchingSchedules, keepSeparate }

// 클래스명: _PillIdentificationUIState
// 역할: 알약 사진·후보 선택·일정 검토의 화면 상태.
// 주요 책임: 알약별 분석·재분석과 선택 상태를 유지하고 전체 확인과 일정 검토를 연결한다.
// 속성: _control: 전체 사진·알약 영역 식별; _multiplePillSourceImage/_multiplePillObservations: 촬영 사진과 찾은 알약 영역.
class _PillIdentificationUIState extends State<PillIdentificationUI> {
  late final IdentifyPill _control;
  late final bool _ownsControl;
  final ResolveDuplicatePillSelectionControl _duplicateSelectionControl =
      const ResolveDuplicatePillSelectionControl();
  final List<_PillPhotoDraft> _drafts = [_PillPhotoDraft()];
  Uint8List? _multiplePillSourceImage;
  List<MultiplePillObservation> _multiplePillObservations = const [];
  bool _isAnalyzing = false;
  bool _isSelectingImage = false;
  bool _isConfirmingCandidates = false;
  String _errorMessage = '';
  int? _refiningDraftIndex;
  Timer? _disclosureTimer;
  bool _showDisclosure = true;

  // 함수이름: _isBusy
  // 함수역할: 분석·사진 선택·후보 확인 중인지 확인해 겹치는 작업을 막는다.
  // 매개변수: 없음.
  // 반환값: 어느 작업이든 진행 중이면 true.
  bool get _isBusy =>
      _isAnalyzing || _isSelectingImage || _isConfirmingCandidates;

  List<_PillPhotoDraft> get _selectedDrafts => [
    for (final draft in _drafts)
      if (draft.selectedItemSeq != null) draft,
  ];

  bool get _canConfirmSelections {
    final selectedDrafts = _selectedDrafts;
    return selectedDrafts.isNotEmpty &&
        selectedDrafts.every(
          (draft) =>
              draft.hasFrontImage &&
              draft.result?.hasMoreCandidates == false &&
              _selectedCandidate(draft) != null,
        );
  }

  // 함수이름: initState
  // 함수역할: 알약 식별 컨트롤러의 소유 여부를 정하고 안내 문구를 닫을 타이머를 시작한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    _ownsControl = widget.control == null;
    _control = widget.control ?? IdentifyPill();
    _disclosureTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showDisclosure = false);
    });
  }

  // Function Name: dispose
  // Description: Releases _control and detaches this screen from active updates.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void dispose() {
    _disclosureTimer?.cancel();
    if (_ownsControl) {
      _control.dispose();
    }
    super.dispose();
  }

  // Function Name: build
  // Description: Renders the pill photo, candidate selection and review action from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the pill photo, candidate selection and review action.
  @override
  Widget build(BuildContext context) {
    final text = _PillIdentificationText(widget.userSetting.language);
    // 함수이름: build.any callback
    // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 대해 `draft.result != null` 조건으로 컬렉션 항목을 판별한다.
    // 매개변수:
    // - draft (콜백 계약에서 추론): 앞·뒷면 사진과 결과·선택을 보관한 알약 작업 초안.
    // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
    final hasVisibleResults = _drafts.any((draft) => draft.result != null);
    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            MedBuddyPageHeader(
              title: text.title,
              subtitle: text.isEnglish
                  ? 'Find pill matches from photos.'
                  : '사진으로 알약 후보를 찾습니다.',
              onBackRequested: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_showDisclosure) ...[
                      MedBuddyNotice(
                        key: const Key('pill-ai-disclosure'),
                        message: text.safetyNotice,
                        padding: const EdgeInsets.all(16),
                      ),
                      const SizedBox(height: 22),
                    ],
                    Row(
                      key: const Key('pill-photo-heading'),
                      children: [
                        Expanded(
                          flex: 3,
                          child: KeepWordsText(
                            hasVisibleResults
                                ? text.detectedPillCount(_drafts.length)
                                : text.photoSectionTitle,
                            style: const TextStyle(
                              color: MedBuddyColors.textStrong,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        if (hasVisibleResults) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                key: const Key(
                                  'identify-multiple-pills-from-one-photo-button',
                                ),
                                onPressed: _isBusy
                                    ? null
                                    : () => _selectMultiplePillPhoto(text),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: KeepWordsText(text.changePhoto),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    4,
                                    0,
                                    4,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  alignment: Alignment.centerRight,
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!hasVisibleResults) ...[
                      const SizedBox(height: 6),
                      KeepWordsText(
                        text.photoSectionDescription,
                        style: const TextStyle(
                          color: MedBuddyColors.textMuted,
                          fontSize: 13,
                          height: 1.45,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                    SizedBox(height: hasVisibleResults ? 8 : 16),
                    if (_multiplePillSourceImage != null)
                      _MultiplePillObservationPreview(
                        imageBytes: _multiplePillSourceImage!,
                        observations: _multiplePillObservations,
                        description: text.multiplePhotoPreviewLabel,
                      )
                    else
                      _buildAddPhotoActions(text),
                    if (_multiplePillSourceImage != null &&
                        !hasVisibleResults) ...[
                      const SizedBox(height: 14),
                      _buildAddPhotoActions(text),
                    ],
                    if (_errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _ErrorNotice(message: _errorMessage),
                    ],
                    if (hasVisibleResults) ...[
                      const SizedBox(height: 16),
                      _buildAllResults(text),
                    ],
                  ],
                ),
              ),
            ),
            if (hasVisibleResults)
              Container(
                key: const Key('pill-review-footer'),
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration: const BoxDecoration(
                  color: MedBuddyColors.pageBackground,
                  border: Border(
                    top: BorderSide(color: MedBuddyColors.divider),
                  ),
                ),
                child: _buildConfirmationButton(text),
              ),
          ],
        ),
      ),
    );
  }

  // Function Name: _buildAddPhotoActions
  // Description: Offers the first photo, a retry for a photo without detected pills, or a secondary photo change.
  // Parameters: text (_PillIdentificationText): localized action labels.
  // Returns: Photo-add, retry or replacement controls.
  Widget _buildAddPhotoActions(_PillIdentificationText text) {
    final hasPhoto = _multiplePillSourceImage != null;
    if (!hasPhoto) {
      return _MultiplePillPhotoFrame(
        child: InkWell(
          key: const Key('identify-multiple-pills-from-one-photo-button'),
          onTap: _isBusy ? null : () => _selectMultiplePillPhoto(text),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 36,
                    color: MedBuddyColors.primary,
                  ),
                  const SizedBox(height: 8),
                  KeepWordsText(
                    text.addPhoto,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: MedBuddyColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final needsRetry =
        hasPhoto && _multiplePillObservations.isEmpty && !_isAnalyzing;
    final label = KeepWordsText(
      _isAnalyzing
          ? (text.isEnglish
                ? 'Finding pills in the photo...'
                : '사진 속 알약을 찾는 중...')
          : needsRetry
          ? text.retryMultiplePillPhoto
          : hasPhoto
          ? text.changePhoto
          : text.addPhoto,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
    final icon = _isAnalyzing
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            hasPhoto && !needsRetry
                ? Icons.edit_outlined
                : Icons.add_a_photo_outlined,
          );
    final VoidCallback? onPressed = _isBusy
        ? null
        : needsRetry
        ? () => _analyzeMultiplePillPhoto(_multiplePillSourceImage!, text)
        : () => _selectMultiplePillPhoto(text);
    if (hasPhoto && !needsRetry && !_isAnalyzing) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const Key('identify-multiple-pills-from-one-photo-button'),
          onPressed: onPressed,
          icon: icon,
          label: label,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('identify-multiple-pills-from-one-photo-button'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onPressed: onPressed,
          icon: icon,
          label: label,
        ),
        if (needsRetry)
          TextButton.icon(
            key: const Key('replace-multiple-pill-photo-button'),
            onPressed: _isBusy ? null : () => _selectMultiplePillPhoto(text),
            icon: const Icon(Icons.photo_library_outlined),
            label: KeepWordsText(text.changePhoto),
          ),
      ],
    );
  }

  // Function Name: _buildAllResults
  // Description: Groups per-pill actions and results inside the scrollable area.
  // Parameters: text (_PillIdentificationText): labels.
  // Returns: The result list; confirmation remains fixed below the scroll area.
  Widget _buildAllResults(_PillIdentificationText text) {
    final resultIndexes = [
      for (var index = 0; index < _drafts.length; index += 1)
        if (_drafts[index].result != null) index,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (
          var position = 0;
          position < resultIndexes.length;
          position += 1
        ) ...[
          _buildPillResultGroup(resultIndexes[position], text),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  // Keeps the selection count visible without scrolling the candidates.
  Widget _buildConfirmationButton(_PillIdentificationText text) {
    return OutlinedButton(
      key: const Key('confirm-pill-candidate-button'),
      onPressed: !_canConfirmSelections || _isBusy
          ? null
          // 함수이름: _buildConfirmationButton.onPressed callback
          // 함수역할: 모든 알약의 선택을 모아 중복 처리 방식을 확인한 뒤 일정 검토와 결과 단계 인계를 진행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          : () => _confirmCandidates(text),
      style: OutlinedButton.styleFrom(
        foregroundColor: MedBuddyColors.primaryDark,
        side: const BorderSide(color: MedBuddyColors.primary, width: 1.5),
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_outlined),
          const SizedBox(width: 8),
          Flexible(
            child: KeepWordsText(
              text.confirmSelections(_selectedDrafts.length),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillResultGroup(int index, _PillIdentificationText text) {
    return Container(
      key: Key('pill-result-group-$index'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MedBuddyColors.surface,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeepWordsText(
            text.candidateTitleForPill(
              index + 1,
              _drafts[index].result!.candidates.length,
            ),
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          _buildRefinementActions(index, text),
          _buildResultForDraft(index, text),
        ],
      ),
    );
  }

  // Function Name: _buildRefinementActions
  // Description: Offers reanalysis of a numbered source region or adding the matching pill back photo while retaining results.
  // Parameters: index (int): pill draft; text (_PillIdentificationText): labels.
  // Returns: Refinement actions with per-pill progress/error state.
  Widget _buildRefinementActions(int index, _PillIdentificationText text) {
    final draft = _drafts[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (draft.sourceRegion != null)
              OutlinedButton.icon(
                key: Key('refine-pill-region-$index'),
                icon: const Icon(Icons.center_focus_strong),
                label: KeepWordsText(
                  text.refineRegion(index + 1),
                  style: const TextStyle(fontSize: 13),
                ),
                // 함수이름: 영역 재분석 콜백
                // 함수역할: 이 번호의 영역만 재분석한다. 매개변수: 없음. 반환값: 완료 Future.
                onPressed: _isBusy
                    ? null
                    : () => _refineDraft(index, text, addBack: false),
              ),
            OutlinedButton.icon(
              key: Key('refine-pill-back-$index'),
              icon: const Icon(Icons.cameraswitch_outlined),
              label: KeepWordsText(
                text.addBack(index + 1),
                style: const TextStyle(fontSize: 13),
              ),
              // 함수이름: 뒷면 추가 콜백
              // 함수역할: 동일 알약 여부를 확인받고 앞·뒷면을 비교한다. 매개변수: 없음. 반환값: 완료 Future.
              onPressed: _isBusy
                  ? null
                  : () => _refineDraft(index, text, addBack: true),
            ),
          ],
        ),
        if (_refiningDraftIndex == index) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (draft.errorMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ErrorNotice(message: draft.errorMessage),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  // Function Name: _refineDraft
  // Description: Reanalyzes only the chosen pill from its original region or matched back photo; cancellation/failure preserves previous results and other selections.
  // Parameters: index (int): target draft; text (_PillIdentificationText): messages; addBack (bool): request a back photo.
  // Returns: Future completing after refinement or cancellation.
  Future<void> _refineDraft(
    int index,
    _PillIdentificationText text, {
    required bool addBack,
  }) async {
    final draft = _drafts[index];
    if (_isBusy) return;
    setState(() {
      _isSelectingImage = true;
      _refiningDraftIndex = index;
      draft.errorMessage = '';
    });
    try {
      final front =
          draft.croppedFrontImage ??
          (draft.sourceRegion == null
              ? draft.frontImage!
              : await _control.cropPillImage(
                  draft.frontImage!,
                  draft.sourceRegion!,
                ));
      if (!mounted) return;
      Uint8List? back = draft.backImage;
      if (addBack) {
        setState(() => _refiningDraftIndex = null);
        final source = await showDialog<ImageSource>(
          context: context,
          // 함수이름: 뒷면 확인 대화상자 빌더
          // 함수역할: 선택한 번호의 앞면과 사진 출처를 표시한다. 매개변수: context. 반환값: 대화상자.
          builder: (context) => AlertDialog(
            title: KeepWordsText(text.addBack(index + 1)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.memory(
                    front,
                    height: 140,
                    fit: BoxFit.contain,
                    // 140dp 미리보기에 필요한 해상도까지만 디코딩한다.
                    cacheHeight: (140 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                  ),
                  const SizedBox(height: 12),
                  KeepWordsText(text.samePillBackNotice),
                ],
              ),
            ),
            actions: [
              // 함수이름: 사진 출처 선택 콜백
              // 함수역할: 취소 또는 카메라·갤러리 출처를 반환한다. 매개변수: 없음. 반환값: 없음.
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(text.cancel),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: KeepWordsText(text.gallery),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: KeepWordsText(text.camera),
              ),
            ],
          ),
        );
        if (!mounted || source == null) return;
        back = await _control.requestPillImage(source);
        if (!mounted || back == null) return;
      }
      setState(() => _refiningDraftIndex = index);
      final result = await _control.requestPillIdentification(
        frontImage: front,
        backImage: back,
      );
      if (!mounted) return;
      setState(() {
        draft.croppedFrontImage = front;
        draft.backImage = back;
        draft.result = result;
        draft.selectedItemSeq = null;
        draft.visibleCandidateCount = 5;
        draft.errorMessage = '';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          draft.errorMessage =
              '${_stateErrorMessage(error, text.requestFailed)} ${text.previousResultKept}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSelectingImage = false;
          _refiningDraftIndex = null;
        });
      }
    }
  }

  // Function Name: _buildResultForDraft
  // Description: Selects the photo's no-candidate, low-confidence, candidate-choice or retry presentation.
  // Parameters: index (int): draft position; text (_PillIdentificationText): labels.
  // Returns: The draft-specific analysis result widget.
  Widget _buildResultForDraft(int index, _PillIdentificationText text) {
    final draft = _drafts[index];
    final result = draft.result!;
    final actionsEnabled = !_isBusy;
    if (result.candidates.isEmpty) {
      return Semantics(
        key: index == 0
            ? const Key('pill-empty-results')
            : Key('pill-empty-results-$index'),
        container: true,
        liveRegion: true,
        label: text.candidateResultsAnnouncement(0),
        child: _EmptyResult(
          text: text,
          // 함수이름: _buildResultForDraft.onRetry callback
          // 함수역할: 이 알약 영역만 다시 비교한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onRetry: actionsEnabled
              ? () => _refineDraft(index, text, addBack: false)
              : null,
        ),
      );
    }

    return Semantics(
      key: index == 0
          ? const Key('pill-candidate-results')
          : Key('pill-candidate-results-$index'),
      container: true,
      liveRegion: true,
      label: text.candidateResultsAnnouncement(result.candidates.length),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!result.isConfident ||
              result.hasMoreCandidates ||
              result.observedFeatures.qualityIssues.isNotEmpty) ...[
            _ConfidenceNotice(
              key: index == 0
                  ? const Key('pill-confidence-warning')
                  : Key('pill-confidence-warning-$index'),
              message: result.hasMoreCandidates
                  ? '${text.lowConfidenceNotice} ${text.tooManyCandidates}'
                  : text.lowConfidenceNotice,
            ),
            const SizedBox(height: 12),
          ],
          for (final candidate in result.candidates.take(
            draft.visibleCandidateCount,
          )) ...[
            _PillCandidateCard(
              candidate: candidate,
              selected: candidate.itemSeq == draft.selectedItemSeq,
              duplicateCount: candidate.itemSeq == draft.selectedItemSeq
                  ? _selectedCandidateCount(candidate)
                  : 1,
              text: text,
              onTap: actionsEnabled
                  ? () => setState(() {
                      if (draft.selectedItemSeq == candidate.itemSeq) {
                        draft.selectedItemSeq = null;
                        return;
                      }
                      // 다른 약을 고르면 이전 약의 검토값은 더 이상 맞지 않는다.
                      draft.reviewedSchedule = null;
                      draft.selectedItemSeq = candidate.itemSeq;
                    })
                  : null,
            ),
            const Divider(height: 16),
          ],
          if (draft.visibleCandidateCount < result.candidates.length)
            TextButton.icon(
              key: Key('more-pill-candidates-$index'),
              icon: const Icon(Icons.expand_more),
              label: KeepWordsText(
                text.moreCandidates,
                style: const TextStyle(fontSize: 14),
              ),
              // 함수이름: 후보 더 보기 콜백
              // 함수역할: 현재 알약 후보만 5개 더 펼친다. 매개변수: 없음. 반환값: 없음.
              onPressed: _isBusy
                  ? null
                  : () => setState(() => draft.visibleCandidateCount += 5),
            ),
        ],
      ),
    );
  }

  // 함수이름: _selectMultiplePillPhoto
  // 함수역할: 처리 중이 아니면 여러 알약이 담긴 사진을 선택하고 번호별 식별을 요청한다.
  // 매개변수: text는 현재 언어의 안내 문구이다. 반환값: 사진 선택·분석 완료.
  Future<void> _selectMultiplePillPhoto(_PillIdentificationText text) async {
    if (_isBusy) {
      return;
    }
    final source = await showMedicationPhotoSourceOptions(
      context: context,
      language: widget.userSetting.language,
    );
    if (!mounted || source == null) {
      return;
    }
    // Function Name: _selectMultiplePillPhoto.setState callback
    // Description: Updates the local input or request state for front and back pill photos, candidate selection, and medication saving: `_isSelectingImage = true; _errorMessage = ''`.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
    setState(() {
      _isSelectingImage = true;
      _errorMessage = '';
    });
    try {
      final image = await _control.requestPillImage(source);
      if (!mounted || image == null) {
        return;
      }
      await _analyzeMultiplePillPhoto(image, text);
    } catch (error) {
      if (mounted) {
        // 함수이름: _selectMultiplePillPhoto.setState callback
        // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_errorMessage = _stateErrorMessage(error, text.requestFailed)`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() {
          _errorMessage = _stateErrorMessage(error, text.requestFailed);
        });
      }
    } finally {
      if (mounted) {
        // Function Name: _selectMultiplePillPhoto.setState callback
        // Description: Updates the local input or request state for front and back pill photos, candidate selection, and medication saving: `_isSelectingImage = false`.
        // Parameters:
        // - None.
        // Returns: No payload; applies the captured state changes.
        setState(() => _isSelectingImage = false);
      }
    }
  }

  // 함수이름: _analyzeMultiplePillPhoto
  // 함수역할: 전체 사진으로 초안을 초기화한 뒤 검출된 알약 영역별 후보 초안으로 나누며 화면이 끝난 결과는 반영하지 않는다.
  // 매개변수: image (Uint8List): 전체 알약 사진; text (_PillIdentificationText): 오류·결과 문구.
  // 반환값: 전체 사진 분석과 초안 구성 완료.
  Future<void> _analyzeMultiplePillPhoto(
    Uint8List image,
    _PillIdentificationText text,
  ) async {
    // Function Name: _analyzeMultiplePillPhoto.setState callback
    // Description: Marks analysis as running and replaces earlier drafts with the new photo.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
    setState(() {
      _isAnalyzing = true;
      _errorMessage = '';
      _multiplePillSourceImage = image;
      _multiplePillObservations = const [];
      _drafts
        ..clear()
        ..add(_PillPhotoDraft()..frontImage = image);
    });
    try {
      final result = await _control.requestMultiplePillIdentification(
        image: image,
      );
      if (!mounted) {
        return;
      }
      // Function Name: _analyzeMultiplePillPhoto.setState callback
      // Description: Updates the local input or request state for front and back pill photos, candidate selection, and medication saving: `_multiplePillSourceImage = image; _multiplePillObservations = result.observations; ..frontImage = image`.
      // Parameters:
      // - None.
      // Returns: No payload; applies the captured state changes.
      setState(() {
        _multiplePillSourceImage = image;
        _multiplePillObservations = result.observations;
        _drafts
          ..clear()
          ..addAll([
            for (final observation in result.observations)
              _PillPhotoDraft()
                ..frontImage = image
                ..sourceRegion = observation.boundingBox
                ..result = observation.identification,
          ]);
      });
    } catch (error) {
      if (mounted) {
        // 함수이름: _analyzeMultiplePillPhoto.setState callback
        // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_errorMessage = _stateErrorMessage(error, text.requestFailed)`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() {
          _errorMessage = _stateErrorMessage(error, text.requestFailed);
        });
      }
    } finally {
      if (mounted) {
        // Function Name: _analyzeMultiplePillPhoto.setState callback
        // Description: Updates the local input or request state for front and back pill photos, candidate selection, and medication saving: `_isAnalyzing = false`.
        // Parameters:
        // - None.
        // Returns: No payload; applies the captured state changes.
        setState(() => _isAnalyzing = false);
      }
    }
  }

  // 함수이름: _selectedCandidate
  // 함수역할: 작업의 선택 약품 코드와 일치하는 후보를 찾고 없으면 null을 반환한다.
  // 매개변수:
  // - draft (_PillPhotoDraft): 앞·뒷면 사진과 결과·선택을 보관한 알약 작업 초안.
  // 반환값: PillIdentificationCandidate?: 선택 코드와 일치하는 후보; 선택 또는 후보가 없으면 null.
  PillIdentificationCandidate? _selectedCandidate(_PillPhotoDraft draft) {
    final selectedItemSeq = draft.selectedItemSeq;
    if (selectedItemSeq == null) {
      return null;
    }
    for (final candidate in draft.result?.candidates ?? const []) {
      if (candidate.itemSeq == selectedItemSeq) {
        return candidate;
      }
    }
    return null;
  }

  // 함수이름: _selectedCandidateCount
  // 함수역할: 현재 선택된 후보 중 같은 품목으로 판정된 사진 수를 계산한다.
  // 매개변수:
  // - target (PillIdentificationCandidate): 표시·변환·저장·비교할 약품 데이터.
  // 반환값: int: 중복 선택 제어기가 대상과 동일 약품으로 판정한 선택 후보 개수.
  int _selectedCandidateCount(PillIdentificationCandidate target) {
    final selectedCandidates = _drafts
        .map(_selectedCandidate)
        .whereType<PillIdentificationCandidate>();
    return _duplicateSelectionControl.countEquivalentCandidates(
      selectedCandidates,
      target,
    );
  }

  // 함수이름: _confirmCandidates
  // 함수역할: 현재 화면에서만 후보 검토를 한 번 시작하며 검토 종료·예외 시 후보 확인 잠금을 해제한다.
  // 매개변수: text (_PillIdentificationText): 언어별 안내 문구.
  // 반환값: 검토 종료 후 완료; 이미 작업 중이거나 비활성 경로이면 즉시 완료.
  Future<void> _confirmCandidates(_PillIdentificationText text) async {
    if (_isBusy ||
        !_canConfirmSelections ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() => _isConfirmingCandidates = true);
    try {
      await _reviewCandidates(text);
    } finally {
      if (mounted) setState(() => _isConfirmingCandidates = false);
    }
  }

  // 함수이름: _reviewCandidates
  // 함수역할: 선택한 후보를 모아 중복 처리 방식을 확인하고 일정 검토로 넘긴다.
  // 매개변수: text (_PillIdentificationText): 선택·중복 확인 안내 문구.
  // 반환값: 선택 누락·취소 시 중단하며 검토와 인계가 끝나면 완료되는 Future<void>.
  Future<void> _reviewCandidates(_PillIdentificationText text) async {
    if (!_canConfirmSelections) return;
    final pendingDrafts = _selectedDrafts;
    final candidates = <PillIdentificationCandidate>[];
    for (final draft in pendingDrafts) {
      final candidate = _selectedCandidate(draft);
      if (candidate == null) {
        return;
      }
      candidates.add(candidate);
    }
    if (candidates.isEmpty) {
      return;
    }

    final duplicateGroups = _duplicateSelectionControl.findDuplicateGroups(
      candidates,
    );
    var duplicateResolution = _DuplicatePillResolution.keepSeparate;
    if (duplicateGroups.isNotEmpty) {
      final selectedResolution = await _chooseDuplicateResolution(
        text: text,
        duplicateGroups: duplicateGroups,
      );
      if (!mounted || selectedResolution == null) {
        return;
      }
      duplicateResolution = selectedResolution;
    }

    await _reviewAndHandOffCandidates(
      drafts: pendingDrafts,
      candidates: candidates,
      duplicateResolution: duplicateResolution,
      text: text,
    );
  }

  // 함수이름: _chooseDuplicateResolution
  // 함수역할: 같은 약품 사진을 각각 유지하거나 동일 일정만 묶도록 사용자에게 확인받는다.
  // 매개변수:
  // - text (_PillIdentificationText): 해당 화면 구역의 언어별 표시 문구.
  // - duplicateGroups (List<DuplicatePillSelectionGroup>): 동일 약품으로 선택된 사진들의 중복 그룹.
  // 반환값: Future<_DuplicatePillResolution?>: 중복 일정 병합·유지 선택; 취소 시 null.
  Future<_DuplicatePillResolution?> _chooseDuplicateResolution({
    required _PillIdentificationText text,
    required List<DuplicatePillSelectionGroup> duplicateGroups,
  }) {
    final duplicatePhotoCount = duplicateGroups.fold<int>(
      0,
      // 함수이름: _chooseDuplicateResolution.fold callback
      // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 누적값을 `total + group.count` 규칙으로 계산한다.
      // 매개변수:
      // - total (콜백 계약에서 추론): 누적 합계 또는 지금까지의 최대값.
      // - group (콜백 계약에서 추론): 같은 날짜의 저장 약품 묶음.
      // 반환값: 컬렉션 연산에 전달할 누적값.
      (total, group) => total + group.count,
    );
    return showDialog<_DuplicatePillResolution>(
      context: context,
      // 함수이름: _chooseDuplicateResolution.builder callback
      // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 Key을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context) => AlertDialog(
        title: KeepWordsText(text.duplicateSelectionTitle),
        content: KeepWordsText(
          text.duplicateSelectionMessage(duplicatePhotoCount),
        ),
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actions: [
          TextButton(
            key: const Key('duplicate-pill-cancel'),
            // Function Name: _chooseDuplicateResolution.onPressed callback
            // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context)`.
            // Parameters:
            // - None.
            // Returns: No callback payload; any selection is delivered through the route result.
            onPressed: () => Navigator.pop(context),
            child: Text(text.cancel),
          ),
          OutlinedButton(
            key: const Key('duplicate-pill-keep-separate'),
            // 함수이름: _chooseDuplicateResolution.onPressed callback
            // 함수역할: `Navigator.pop(context, _DuplicatePillResolution.keepSeparate)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onPressed: () =>
                Navigator.pop(context, _DuplicatePillResolution.keepSeparate),
            child: KeepWordsText(text.keepDuplicateSchedulesSeparate),
          ),
          FilledButton(
            key: const Key('duplicate-pill-merge-matching'),
            // 함수이름: _chooseDuplicateResolution.onPressed callback
            // 함수역할: `Navigator.pop(context, _DuplicatePillResolution.mergeMatchingSchedules)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onPressed: () => Navigator.pop(
              context,
              _DuplicatePillResolution.mergeMatchingSchedules,
            ),
            child: KeepWordsText(text.mergeMatchingDuplicateSchedules),
          ),
        ],
      ),
    );
  }

  // Function Name: _reviewAndHandOffCandidates
  // Description: Provides provisional schedules for all selected candidates, reviews them together and hands the confirmed schedules to the shared result step.
  // Parameters: drafts (List<_PillPhotoDraft>): selected drafts aligned with candidates; candidates: confirmed identities; duplicateResolution: merge-or-keep policy; text: result labels.
  // Returns: Future completing after review and the hand-off attempt.
  Future<void> _reviewAndHandOffCandidates({
    required List<_PillPhotoDraft> drafts,
    required List<PillIdentificationCandidate> candidates,
    required _DuplicatePillResolution duplicateResolution,
    required _PillIdentificationText text,
  }) async {
    final reviewedSchedules = await showMedicationScheduleReview(
      context: context,
      initialSchedules: [
        for (var index = 0; index < candidates.length; index += 1)
          // 인계가 거절돼 다시 확인할 때는 앞서 검토한 값을 그대로 보여 준다.
          drafts[index].reviewedSchedule ??
              MedicationSchedule(
                medicationName: candidates[index].itemName,
                prescriptionDate: DateTime.now(),
                dosage: '1정',
                intakeTime: '1회',
                medicationTime: 1,
                scheduleSlotKeys: const [defaultMedicationScheduleSlotKey],
                imageUrl: candidates[index].imageUrl,
                nameConfidence: candidates[index].matchScore,
                nameCorrectionSource: 'pill_identification',
              ),
      ],
      userSetting: widget.userSetting,
      photos: _reviewPhotos(),
    );
    if (!mounted || reviewedSchedules == null) {
      return;
    }
    if (reviewedSchedules.length != candidates.length) {
      _showSnackBar(text.medicationSaveFailed);
      return;
    }
    for (var index = 0; index < drafts.length; index += 1) {
      drafts[index].reviewedSchedule = reviewedSchedules[index];
    }

    final reviewedRequests = [
      for (var index = 0; index < candidates.length; index += 1)
        IdentifiedPillSaveRequest(
          candidate: candidates[index],
          medicationSchedule: reviewedSchedules[index],
        ),
    ];
    // 보낼 요청과 중복 병합은 Control이 정한다.
    final savePlan = _duplicateSelectionControl.buildPillSavePlan(
      reviewedRequests,
      mergeEquivalent:
          duplicateResolution ==
          _DuplicatePillResolution.mergeMatchingSchedules,
    );
    if (!widget.onReviewRequested(savePlan.uniqueRequests) && mounted) {
      _showSnackBar(text.medicationSaveFailed);
    }
  }

  // 함수이름: _reviewPhotos
  // 함수역할: 검토 화면에 촬영한 원본 사진 한 장을 보여 준다.
  // 매개변수: 없음.
  // 반환값: 원본 사진 보기 목록. 사진이 없으면 빈 목록.
  List<MedicationReviewPhoto> _reviewPhotos() {
    final sourceImage = _multiplePillSourceImage;
    if (sourceImage == null) return const [];
    return [
      MedicationReviewPhoto(
        title: _PillIdentificationText(widget.userSetting.language).isEnglish
            ? 'Pill photo'
            : '촬영한 알약 사진',
        aspectRatio: 4 / 3,
        imageBuilder: (context) => _PillReviewPhoto(image: sourceImage),
      ),
    ];
  }

  // 함수이름: _showSnackBar
  // 함수역할: 기존 Snackbar를 교체하여 알약 분석·저장 결과 문구를 표시한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: KeepWordsText(message)));
  }

  // 함수이름: _stateErrorMessage
  // 함수역할: 알약 식별 실패 유형을 현재 언어의 안내로 변환하고 다른 예외는 대체 문구를 사용한다.
  // 매개변수:
  // - error (Object): 사용자 안내 또는 복구 분기에 사용할 실패 정보.
  // - fallback (String): 값이나 약품 정보를 제공할 수 없을 때 사용할 대체 문구.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _stateErrorMessage(Object error, String fallback) {
    if (error is! PillIdentificationException) {
      return fallback;
    }
    final text = _PillIdentificationText(widget.userSetting.language);
    return switch (error.failure) {
      PillIdentificationFailure.emptyImage => text.emptyImage,
      PillIdentificationFailure.oversizedImage => text.oversizedImage,
      PillIdentificationFailure.timedOut => text.timedOut,
      PillIdentificationFailure.invalidPhoto => text.invalidPhoto,
      PillIdentificationFailure.rateLimited => text.rateLimited,
      PillIdentificationFailure.serviceUnavailable => text.serviceUnavailable,
      PillIdentificationFailure.invalidResponse => text.invalidResponse,
      PillIdentificationFailure.fileUnreadable => text.imageSelectionFailed,
    };
  }
}

// Keeps the empty upload control and analyzed photo in the same fixed frame.
class _MultiplePillPhotoFrame extends StatelessWidget {
  final Widget child;

  const _MultiplePillPhotoFrame({required this.child});

  @override
  Widget build(BuildContext context) => AspectRatio(
    key: const Key('multiple-pill-photo-frame'),
    aspectRatio: 16 / 9,
    child: Material(
      color: MedBuddyColors.surfaceSubtle,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: MedBuddyRadii.control,
        side: const BorderSide(color: MedBuddyColors.divider),
      ),
      child: child,
    ),
  );
}

// 클래스명: _PillReviewPhoto
// 역할: 검토 화면에 촬영한 원본 알약 사진을 보여준다.
// 주요 책임: 비율을 유지해 표시하고 로드 실패만 아이콘으로 대체한다.
// 속성: image (Uint8List): 원본 촬영 이미지 바이트.
class _PillReviewPhoto extends StatelessWidget {
  final Uint8List image;

  // 함수이름: _PillReviewPhoto
  // 함수역할: 검토할 원본 사진을 보관한다.
  // 매개변수: image: 실제 촬영 사진.
  // 반환값: 사진 보기.
  const _PillReviewPhoto({required this.image});

  // 함수이름: build
  // 함수역할: 사진을 비율 유지하며 배치하고 로드 실패만 아이콘으로 대체한다.
  // 매개변수: context: 화면 표시 위치.
  // 반환값: 사진이 있는 흰색 사진 영역.
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Image.memory(
        image,
        key: const ValueKey('pill-review-photo-side-0'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: MedBuddyColors.textMuted,
          ),
        ),
      ),
    );
  }
}

// Places normalized region markers over the photo without including letterboxing.
class _MultiplePillObservationPreview extends StatefulWidget {
  final Uint8List imageBytes;
  final List<MultiplePillObservation> observations;
  final String description;

  // Function Name: _MultiplePillObservationPreview
  // Description: Initializes identified regions and explanation over a multi-pill photo with the supplied configuration.
  // Parameters:
  // - imageBytes (Uint8List): Camera frame or image bytes used for analysis or preview.
  // - observations (List<MultiplePillObservation>): Pill positions and characteristics detected in the photo.
  // - description (String): Supporting explanation or account detail below the primary label.
  // Returns: Initialized _MultiplePillObservationPreview instance.
  const _MultiplePillObservationPreview({
    required this.imageBytes,
    required this.observations,
    required this.description,
  });

  @override
  State<_MultiplePillObservationPreview> createState() =>
      _MultiplePillObservationPreviewState();
}

class _MultiplePillObservationPreviewState
    extends State<_MultiplePillObservationPreview> {
  ImageStream? _imageStream;
  Size? _imageSize;
  late final ImageStreamListener _imageListener = ImageStreamListener((
    info,
    _,
  ) {
    if (mounted) {
      setState(() {
        _imageSize = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
      });
    }
    info.dispose();
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(_MultiplePillObservationPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBytes != widget.imageBytes) {
      _imageSize = null;
      _resolveImage();
    }
  }

  void _resolveImage() {
    final stream = MemoryImage(
      widget.imageBytes,
    ).resolve(createLocalImageConfiguration(context));
    if (_imageStream?.key == stream.key) return;
    _imageStream?.removeListener(_imageListener);
    _imageStream = stream..addListener(_imageListener);
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_imageListener);
    super.dispose();
  }

  // Function Name: build
  // Description: Renders identified regions and explanation over a multi-pill photo from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for identified regions and explanation over a multi-pill photo.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('multiple-pill-observation-preview'),
      container: true,
      label: widget.description,
      child: _MultiplePillPhotoFrame(
        child: Center(
          // Keep region coordinates aligned with the contained image, not its letterboxing.
          child: AspectRatio(
            aspectRatio: _imageSize?.aspectRatio ?? 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  widget.imageBytes,
                  key: const Key('multiple-pill-preview-image'),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: const Key('multiple-pill-region-overlay'),
                      painter: _MultiplePillBoxPainter(widget.observations),
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

// Class Name: _MultiplePillBoxPainter
// Role: Represents normalized pill-observation boxes and number overlays.
// Responsibilities:
// - Scales normalized detection boxes to the photo and draws numbered badges constrained within the canvas.
// - Requests repainting when the observations list changes.
// Attributes:
// - observations (List<MultiplePillObservation>): Pill positions and characteristics detected in the photo.
class _MultiplePillBoxPainter extends CustomPainter {
  final List<MultiplePillObservation> observations;

  // Function Name: _MultiplePillBoxPainter
  // Description: Combines the supplied values for normalized pill-observation boxes and number overlays in a _MultiplePillBoxPainter instance.
  // Parameters:
  // - observations (List<MultiplePillObservation>): Pill positions and characteristics detected in the photo.
  // Returns: Initialized _MultiplePillBoxPainter instance.
  const _MultiplePillBoxPainter(this.observations);

  // Function Name: paint
  // Description: Scales normalized detection boxes to the photo and draws numbered badges constrained within the canvas.
  // Parameters:
  // - canvas (Canvas): Canvas on which overlay shapes are drawn.
  // - size (Size): Display dimensions of the widget or canvas.
  // Returns: None; updates state or performs the documented action.
  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = MedBuddyColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final badge = Paint()
      ..color = MedBuddyColors.primary
      ..style = PaintingStyle.fill;
    for (final observation in observations) {
      final box = observation.boundingBox;
      final rect = Rect.fromLTWH(
        box.left * size.width,
        box.top * size.height,
        box.width * size.width,
        box.height * size.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        border,
      );
      final badgeCenter = Offset(
        size.width < 28
            ? size.width / 2
            : (rect.left + 14).clamp(14, size.width - 14),
        size.height < 28
            ? size.height / 2
            : (rect.top + 14).clamp(14, size.height - 14),
      );
      canvas.drawCircle(badgeCenter, 14, badge);
      final label = TextPainter(
        text: TextSpan(
          text: '${observation.index}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        badgeCenter - Offset(label.width / 2, label.height / 2),
      );
    }
  }

  // Function Name: shouldRepaint
  // Description: Requests repainting when the observations list changes.
  // Parameters:
  // - oldDelegate (_MultiplePillBoxPainter): Previous painter used to determine whether repainting is needed.
  // Returns: True when the documented condition holds; false otherwise.
  @override
  bool shouldRepaint(covariant _MultiplePillBoxPainter oldDelegate) =>
      oldDelegate.observations != observations;
}

// Class Name: _PillCandidateCard
// Role: Selectable pill-identification candidate.
// Responsibilities: Shows product identity, selection state and any duplicate-photo count.
// Attributes: candidate: identification result; selected: checked state; duplicateCount: matching photos; callbacks: selection/detail actions.
class _PillCandidateCard extends StatelessWidget {
  final PillIdentificationCandidate candidate;
  final bool selected;
  final int duplicateCount;
  final _PillIdentificationText text;
  final VoidCallback? onTap;

  // 함수이름: _PillCandidateCard
  // 함수역할: 후보 약품 정보·선택 상태·중복 사진 수에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - candidate (PillIdentificationCandidate): 사용자가 확인하거나 저장할 식별 후보 약품.
  // - selected (bool): 현재 선택 집합에 포함되는지 여부.
  // - duplicateCount (int): 중복으로 감지되거나 병합한 항목 수.
  // - text (_PillIdentificationText): 해당 화면 구역의 언어별 표시 문구.
  // - onTap (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _PillCandidateCard 인스턴스.
  const _PillCandidateCard({
    required this.candidate,
    required this.selected,
    required this.duplicateCount,
    required this.text,
    required this.onTap,
  });

  // Function Name: build
  // Description: Displays candidate details and selection with duplicate-photo information where applicable.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    final imprint = [
      candidate.printFront,
      candidate.printBack,
      // Function Name: build.where callback
      // Description: Checks the collection condition `value.isNotEmpty` for candidate medication details, selection, and duplicate-photo count.
      // Parameters:
      // - value (inferred by callback contract): Input to validate, normalize, display, or pass through a selection callback.
      // Returns: Boolean predicate result for the supplied item.
    ].where((value) => value.isNotEmpty).join(' / ');
    final details = Column(
      key: Key('pill-candidate-details-${candidate.itemSeq}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeepWordsText(
          candidate.itemName,
          style: const TextStyle(
            color: MedBuddyColors.textStrong,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        if (duplicateCount > 1) ...[
          const SizedBox(height: 6),
          KeepWordsText(
            key: Key('duplicate-pill-badge-${candidate.itemSeq}'),
            text.sameMedicinePhotoCount(duplicateCount),
            style: const TextStyle(
              color: MedBuddyColors.reminderAccent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (candidate.manufacturer.isNotEmpty) ...[
          const SizedBox(height: 4),
          KeepWordsText(
            candidate.manufacturer,
            style: const TextStyle(
              color: MedBuddyColors.textSubtle,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
        ],
        if (imprint.isNotEmpty) ...[
          const SizedBox(height: 4),
          KeepWordsText(
            '${text.imprintLabel}: $imprint',
            style: const TextStyle(
              color: MedBuddyColors.primaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ],
    );
    final selectionIcon = Icon(
      selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      color: selected ? MedBuddyColors.primary : MedBuddyColors.textLight,
      semanticLabel: selected ? text.selected : text.notSelected,
    );
    return Semantics(
      container: true,
      selected: selected,
      child: Material(
        color: selected ? MedBuddyColors.surfaceSubtle : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? MedBuddyColors.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  key: Key('pill-candidate-row-${candidate.itemSeq}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CandidateImage(
                      candidate: candidate,
                      dimension: constraints.maxWidth < 320 ? 72 : 80,
                      text: text,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: details),
                    const SizedBox(width: 8),
                    selectionIcon,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// Class Name: _CandidateImage
// Role: Represents a candidate's safe network image and unavailable-image fallback.
// Responsibilities:
// - Composes a candidate's safe network image and unavailable-image fallback using the display values and actions supplied by its parent.
// Attributes:
// - candidate: Candidate whose validated image opens in the shared viewer.
// - dimension: Thumbnail edge length; text: Localized accessibility labels.
class _CandidateImage extends StatelessWidget {
  final PillIdentificationCandidate candidate;
  final double dimension;
  final _PillIdentificationText text;

  // Function Name: _CandidateImage
  // Description: Initializes a candidate's safe network image and unavailable-image fallback with the supplied configuration.
  // Parameters:
  // - candidate: Candidate image and viewer title; dimension: Thumbnail size; text: Localized labels.
  // Returns: Initialized _CandidateImage instance.
  const _CandidateImage({
    required this.candidate,
    required this.dimension,
    required this.text,
  });

  // Function Name: build
  // Description: Renders a candidate's safe network image and unavailable-image fallback from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a candidate's safe network image and unavailable-image fallback.
  @override
  Widget build(BuildContext context) {
    final normalizedUrl = safeMedicationImageUrl(candidate.imageUrl);
    const placeholder = ColoredBox(
      color: MedBuddyColors.surfaceSubtle,
      child: Center(
        child: Icon(Icons.medication_outlined, color: MedBuddyColors.textLight),
      ),
    );
    final thumbnail = ClipRRect(
      borderRadius: MedBuddyRadii.small,
      child: SizedBox.square(
        dimension: dimension,
        child: normalizedUrl.isEmpty
            ? placeholder
            : Image.network(
                normalizedUrl,
                fit: BoxFit.contain,
                cacheWidth: (dimension * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                // Function Name: build.errorBuilder callback
                // Description: Substitutes the unavailable-image presentation when the image cannot be decoded or loaded.
                // Parameters:
                // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
                // - error (inferred by callback contract): Failure information used for user guidance or recovery selection.
                // - stackTrace (inferred by callback contract): Optional image-error stack trace, not used for display.
                // Returns: Widget subtree for the described layout or fallback.
                errorBuilder: (context, error, stackTrace) => placeholder,
                // Function Name: build.loadingBuilder callback
                // Description: Composes a candidate's safe network image and unavailable-image fallback with the current parent constraints for the active layout.
                // Parameters:
                // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
                // - child (inferred by callback contract): Content widget placed within this layout.
                // - progress (inferred by callback contract): Completion fraction from zero to one.
                // Returns: Widget subtree for the described layout or fallback.
                loadingBuilder: (context, child, progress) {
                  return progress == null ? child : placeholder;
                },
              ),
      ),
    );
    final label = normalizedUrl.isEmpty
        ? text.imageUnavailable
        : text.enlargeImage(candidate.itemName);
    return Semantics(
      button: normalizedUrl.isNotEmpty,
      image: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: Key('pill-candidate-image-${candidate.itemSeq}'),
          borderRadius: MedBuddyRadii.small,
          excludeFromSemantics: normalizedUrl.isEmpty,
          // Thumbnail taps must never toggle the candidate, even for placeholders.
          onTap: () {
            if (normalizedUrl.isEmpty) return;
            MedicationImageViewer.show(
              context,
              medicationName: candidate.itemName,
              imageUrl: normalizedUrl,
              language: text.language,
            );
          },
          child: thumbnail,
        ),
      ),
    );
  }
}

// Class Name: _ErrorNotice
// Role: Represents an error notice for pill-identification operations.
// Responsibilities:
// - Composes an error notice for pill-identification operations using the display values and actions supplied by its parent.
// Attributes:
// - message (String): Visible wording for the current result, error, or state.
class _ErrorNotice extends StatelessWidget {
  final String message;

  // Function Name: _ErrorNotice
  // Description: Initializes an error notice for pill-identification operations with the supplied configuration.
  // Parameters:
  // - message (String): Visible wording for the current result, error, or state.
  // Returns: Initialized _ErrorNotice instance.
  const _ErrorNotice({required this.message});

  // Function Name: build
  // Description: Renders an error notice for pill-identification operations from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for an error notice for pill-identification operations.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: MedBuddyNotice(
        icon: Icons.warning_amber_rounded,
        message: message,
        padding: const EdgeInsets.all(12),
      ),
    );
  }
}

// Class Name: _ConfidenceNotice
// Role: Represents identification-confidence and verification-required notices.
// Responsibilities:
// - Composes identification-confidence and verification-required notices using the display values and actions supplied by its parent.
// Attributes:
// - message (String): Visible wording for the current result, error, or state.
class _ConfidenceNotice extends StatelessWidget {
  final String message;

  // Function Name: _ConfidenceNotice
  // Description: Initializes identification-confidence and verification-required notices with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - message (String): Visible wording for the current result, error, or state.
  // Returns: Initialized _ConfidenceNotice instance.
  const _ConfidenceNotice({super.key, required this.message});

  // Function Name: build
  // Description: Renders identification-confidence and verification-required notices from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for identification-confidence and verification-required notices.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MedBuddyColors.warningSurface,
          borderRadius: MedBuddyRadii.small,
          border: Border.all(color: MedBuddyColors.warningBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: MedBuddyColors.reminderAccent,
              size: 21,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: KeepWordsText(
                message,
                style: const TextStyle(
                  color: MedBuddyColors.reminderAccent,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Class Name: _EmptyResult
// Role: No pill candidates found.
// Responsibilities: Explains the empty result and offers changing the photo or retrying when a callback is available.
// Attributes: onRetry (VoidCallback?): retry action; text: localized empty-result copy.
class _EmptyResult extends StatelessWidget {
  final _PillIdentificationText text;
  final VoidCallback? onRetry;

  // 함수이름: _EmptyResult
  // 함수역할: 후보 부재 안내와 사진 변경 후 재시도에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_PillIdentificationText): 해당 화면 구역의 언어별 표시 문구.
  // - onRetry (VoidCallback?): 실패하거나 오래된 화면 데이터를 다시 조회할 콜백.
  // 반환값: 입력 설정이 반영된 _EmptyResult 인스턴스.
  const _EmptyResult({required this.text, this.onRetry});

  // Function Name: build
  // Description: Shows the no-candidate explanation and optional photo/retry action.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            const Icon(
              Icons.search_off,
              color: MedBuddyColors.textLight,
              size: 44,
            ),
            const SizedBox(height: 10),
            KeepWordsText(
              text.noCandidates,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: KeepWordsText(text.retryComparison),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Class Name: _PillIdentificationText
// Role: Represents localized wording for pill-photo identification, candidate comparison, duplicate resolution, and schedule saving.
// Responsibilities:
// - Selects Korean or English labels and interpolates message values for localized wording for pill-photo identification, candidate comparison, duplicate resolution, and schedule saving.
// Attributes:
// - language (String): Language code selecting visible wording.
class _PillIdentificationText {
  // 함수이름: moreCandidates
  // 함수역할: 후보 확장 명령을 번역한다. 매개변수: 없음. 반환값: 표시 문자열.
  String get moreCandidates =>
      isEnglish ? 'Show more candidates' : '비슷한 후보 더 보기';
  // 함수이름: tooManyCandidates
  // 함수역할: 서버 상한 밖의 동점 후보 존재를 알린다. 매개변수: 없음. 반환값: 안내.
  String get tooManyCandidates => isEnglish
      ? 'More matching products exist. Add the back of this pill to narrow the results.'
      : '표시된 목록 밖에도 비슷한 약이 있습니다. 같은 알약의 뒷면을 추가해 후보를 좁혀주세요.';
  // 함수이름: refineRegion
  // 함수역할: 번호별 영역 재분석 명령을 번역한다. 매개변수: number는 알약 번호. 반환값: 명령.
  String refineRegion(int number) =>
      isEnglish ? 'Reanalyze pill $number region' : '알약 $number 영역 다시 분석';
  // 함수이름: addBack
  // 함수역할: 번호별 뒷면 추가 명령을 번역한다. 매개변수: number는 알약 번호. 반환값: 명령.
  String addBack(int number) =>
      isEnglish ? 'Add pill $number back photo' : '알약 $number 뒷면 추가';
  // 함수이름: samePillBackNotice
  // 함수역할: 다른 알약과 앞뒷면을 잘못 연결하지 않도록 안내한다. 매개변수: 없음. 반환값: 안내.
  String get samePillBackNotice => isEnglish
      ? 'Turn over this same pill and photograph its back alone. Do not use a different pill.'
      : '위 사진의 같은 알약을 뒤집어 뒷면만 촬영해주세요. 다른 알약의 사진을 연결하지 마세요.';
  // 함수이름: previousResultKept
  // 함수역할: 실패 시 기존 결과 유지 상태를 알린다. 매개변수: 없음. 반환값: 안내.
  String get previousResultKept =>
      isEnglish ? 'Previous results were kept.' : '기존 결과는 유지했습니다.';
  String enlargeImage(String name) =>
      isEnglish ? 'Enlarge image of $name' : '$name 사진 확대';
  String get imageUnavailable => isEnglish ? 'Image unavailable' : '사진 없음';
  // 함수이름: imprintLabel
  // 함수역할: 참고 각인 표시명을 번역한다. 매개변수: 없음. 반환값: 표시명.
  String get imprintLabel => isEnglish ? 'Imprint' : '각인';
  final String language;

  // 함수이름: _PillIdentificationText
  // 함수역할: 알약 사진 식별, 후보 비교 및 중복 조정 후 일정 저장에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _PillIdentificationText 인스턴스.
  const _PillIdentificationText(this.language);

  // Function Name: isEnglish
  // Description: Checks whether the language code is English using the shared language predicate.
  // Parameters:
  // - None.
  // Returns: True when the documented condition holds; false otherwise.
  bool get isEnglish => isEnglishLanguage(language);
  // 함수이름: title
  // 함수역할: 화면 제목을 번역한다. 매개변수: 없음. 반환값: 제목.
  String get title => isEnglish ? 'Identify loose pills' : '낱알약 식별';

  // 함수이름: safetyNotice
  // 함수역할: 사진 처리와 후보 결과의 한계를 간결하게 안내한다. 매개변수: 없음. 반환값: 안내.
  String get safetyNotice => isEnglish
      ? 'Photos are analyzed by external AI, not stored by MedBuddy. Verify candidates with the packaging or a pharmacist.'
      : '사진은 외부 AI로 분석되며 MedBuddy에 저장되지 않아요. 후보는 포장 정보나 약사에게 확인하세요.';

  // 함수이름: photoSectionTitle
  // 함수역할: 필요한 사진을 안내한다. 매개변수: 없음. 반환값: 구역 제목.
  String get photoSectionTitle =>
      isEnglish ? 'Add a photo of your pills' : '알약 사진을 추가하세요';

  // 함수이름: photoSectionDescription
  // 함수역할: 촬영 조건을 안내한다. 매개변수: 없음. 반환값: 설명.
  String get photoSectionDescription => isEnglish
      ? 'One pill or several, up to 10 in one photo, not overlapping. You can add a back photo for each pill afterwards.'
      : '한 알이든 여러 알이든 한 장에 찍어 주세요. 최대 10개까지, 서로 겹치지 않게요. 찍은 뒤 알약마다 뒷면을 더할 수 있어요.';

  // 함수이름: detectedPillCount
  // 함수역할: 촬영 안내 대신 확인할 알약 수를 표시한다. 매개변수: count. 반환값: 결과 제목.
  String detectedPillCount(int count) => isEnglish
      ? 'Review $count pill${count == 1 ? '' : 's'}'
      : '알약 $count개 후보 확인';

  // 함수이름: addPhoto
  // 함수역할: 카메라·갤러리 선택을 여는 명령을 번역한다. 매개변수: 없음. 반환값: 버튼 문구.
  String get addPhoto => isEnglish ? 'Add photo' : '사진 추가';

  // 함수이름: changePhoto
  // 함수역할: 기존 전체 사진을 교체하는 보조 명령을 번역한다. 매개변수: 없음. 반환값: 버튼 문구.
  String get changePhoto => isEnglish ? 'Change photo' : '사진 변경';

  // Function Name: retryMultiplePillPhoto
  // Description: Provides localized wording for "Analyze this photo again" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get retryMultiplePillPhoto =>
      isEnglish ? 'Analyze this photo again' : '이 사진 다시 분석';
  // Accessibility label only; the photo has no visible explanatory paragraph.
  String get multiplePhotoPreviewLabel =>
      isEnglish ? 'Analyzed pill photo' : '분석한 알약 사진';

  // Function Name: camera
  // Description: Provides localized wording for "Take a photo" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get camera => isEnglish ? 'Take a photo' : '카메라로 촬영';
  // Function Name: gallery
  // Description: Provides localized wording for "Choose from gallery" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get gallery => isEnglish ? 'Choose from gallery' : '갤러리에서 선택';

  // 함수이름: candidateTitleForPill
  // 함수역할: 현재 언어와 입력값에 맞춰 "알약 $pillNumber · 가능한 후보 $count개" 문구를 제공한다.
  // 매개변수:
  // - pillNumber (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String candidateTitleForPill(int pillNumber, int count) => isEnglish
      ? 'Pill $pillNumber · $count possible matches'
      : '알약 $pillNumber · 가능한 후보 $count개';
  // Function Name: candidateResultsAnnouncement
  // Description: Provides localized wording for "Pill identification completed. $count possible matches." using the current language and message inputs.
  // Parameters:
  // - count (int): Item count or ordinal number used in wording or a list.
  // Returns: The formatted display text or identifier described above.
  String candidateResultsAnnouncement(int count) => isEnglish
      ? 'Pill identification completed. $count possible matches.'
      : '알약 식별이 완료되었습니다. 가능한 후보는 $count개입니다.';
  // Function Name: lowConfidenceNotice
  // Description: Provides one concise caution for an uncertain pill group.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get lowConfidenceNotice => isEnglish
      ? 'Uncertain matches. Compare both sides and imprints before choosing.'
      : '불확실한 후보입니다. 앞뒷면과 각인을 대조한 뒤 선택하세요.';
  // Function Name: selected
  // Description: Provides localized wording for "Selected" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get selected => isEnglish ? 'Selected' : '선택됨';
  // Function Name: notSelected
  // Description: Provides localized wording for "Not selected" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get notSelected => isEnglish ? 'Not selected' : '선택 안 됨';
  // 함수이름: sameMedicinePhotoCount
  // 함수역할: 현재 언어와 입력값에 맞춰 "동일 약품 사진 $count장" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String sameMedicinePhotoCount(int count) =>
      isEnglish ? 'Same medicine ×$count' : '동일 약품 사진 $count장';
  // 함수이름: duplicateSelectionTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "동일 약품 사진 확인" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get duplicateSelectionTitle =>
      isEnglish ? 'Review matching medicines' : '동일 약품 사진 확인';
  // 함수이름: duplicateSelectionMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "같은 약품으로 확인된 사진이 $photoCount장 있습니다. 각 복약 정보를 검토한 뒤, 내용이 완전히 같은 일정만 하나로 묶을지 선택해주세요. 복용량, 날짜 또는 기간이 다르면 항상 별도로 유지됩니다." 문구를 제공한다.
  // 매개변수:
  // - photoCount (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String duplicateSelectionMessage(int photoCount) => isEnglish
      ? '$photoCount photos were matched to the same medicine. Review every schedule, then choose whether completely identical schedules should be merged. Different doses, dates, or durations will always stay separate.'
      : '같은 약품으로 확인된 사진이 $photoCount장 있습니다. 각 복약 정보를 검토한 뒤, 내용이 완전히 같은 일정만 하나로 묶을지 선택해주세요. 복용량, 날짜 또는 기간이 다르면 항상 별도로 유지됩니다.';
  // 함수이름: cancel
  // 함수역할: 현재 언어와 입력값에 맞춰 "Cancel" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get cancel => isEnglish ? 'Cancel' : '취소';
  // 함수이름: keepDuplicateSchedulesSeparate
  // 함수역할: 현재 언어와 입력값에 맞춰 "각각 유지" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get keepDuplicateSchedulesSeparate =>
      isEnglish ? 'Keep separately' : '각각 유지';
  // 함수이름: mergeMatchingDuplicateSchedules
  // 함수역할: 현재 언어와 입력값에 맞춰 "같은 일정만 묶기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get mergeMatchingDuplicateSchedules =>
      isEnglish ? 'Merge identical schedules' : '같은 일정만 묶기';
  // 함수이름: confirmSelections
  // 함수역할: 현재 언어와 입력값에 맞춰 "선택한 후보 확인" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String confirmSelections(int count) => isEnglish
      ? count == 0
            ? '0 pills selected'
            : 'Review and save $count selected pill${count == 1 ? '' : 's'}'
      : count == 0
      ? '선택한 알약 0개'
      : '선택한 알약 $count개 검토 후 저장';
  // 함수이름: medicationSaveFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 정보를 저장하지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationSaveFailed =>
      isEnglish ? 'Could not save the medication plan.' : '복약 정보를 저장하지 못했습니다.';

  // Function Name: noCandidates
  // Description: Provides localized wording for "No reliable candidates were found. Retake both sides more clearly." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get noCandidates => isEnglish
      ? 'No reliable candidates were found. Retake both sides more clearly.'
      : '신뢰할 수 있는 후보를 찾지 못했습니다. 앞뒷면을 더 선명하게 다시 촬영해주세요.';
  // 함수이름: retryComparison
  // 함수역할: 현재 언어와 입력값에 맞춰 "이 알약 다시 비교" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get retryComparison =>
      isEnglish ? 'Compare this pill again' : '이 알약 다시 비교';
  // Function Name: imageSelectionFailed
  // Description: Provides localized wording for "Could not read the selected image." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get imageSelectionFailed =>
      isEnglish ? 'Could not read the selected image.' : '선택한 이미지를 읽지 못했습니다.';
  // Function Name: requestFailed
  // Description: Provides localized wording for "Pill identification failed. Please try again." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get requestFailed => isEnglish
      ? 'Pill identification failed. Please try again.'
      : '알약 식별에 실패했습니다. 다시 시도해주세요.';
  // Function Name: emptyImage
  // Description: Provides localized wording for "The selected image is empty." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get emptyImage =>
      isEnglish ? 'The selected image is empty.' : '선택한 이미지가 비어 있습니다.';
  // Function Name: oversizedImage
  // Description: Provides localized wording for "Each pill image must be 10 MB or smaller." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get oversizedImage => isEnglish
      ? 'Each pill image must be 10 MB or smaller.'
      : '알약 이미지는 장당 10MB 이하여야 합니다.';
  // Function Name: timedOut
  // Description: Provides localized wording for "Pill identification timed out. Please try again." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get timedOut => isEnglish
      ? 'Pill identification timed out. Please try again.'
      : '알약 식별 시간이 초과되었습니다. 다시 시도해주세요.';
  // Function Name: invalidPhoto
  // Description: Provides localized wording for "The pill could not be distinguished. Avoid fingers, strong glare, and occlusion, then retake the photo in focus." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get invalidPhoto => isEnglish
      ? 'The pill could not be distinguished. Avoid fingers, strong glare, and occlusion, then retake the photo in focus.'
      : '알약을 구분할 수 없습니다. 손가락, 강한 반사, 가림을 피하고 초점을 맞춰 다시 촬영해주세요.';
  // 함수이름: rateLimited
  // 함수역할: 현재 언어와 입력값에 맞춰 "요청이 많아 식별하지 못했습니다. 실패한 알약만 잠시 후 다시 시도해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get rateLimited => isEnglish
      ? 'There were too many requests. Please retry the failed pill shortly.'
      : '요청이 많아 식별하지 못했습니다. 실패한 알약만 잠시 후 다시 시도해주세요.';
  // Function Name: serviceUnavailable
  // Description: Provides localized wording for "The pill identification service is temporarily unavailable." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get serviceUnavailable => isEnglish
      ? 'The pill identification service is temporarily unavailable.'
      : '알약 식별 서비스에 일시적으로 연결할 수 없습니다.';
  // Function Name: invalidResponse
  // Description: Provides localized wording for "The pill identification response was invalid. Please try again." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get invalidResponse => isEnglish
      ? 'The pill identification response was invalid. Please try again.'
      : '알약 식별 응답을 처리하지 못했습니다. 다시 시도해주세요.';
}
