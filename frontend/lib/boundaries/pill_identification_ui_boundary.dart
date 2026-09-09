// File Name: pill_identification_ui_boundary.dart
// Role: UI boundaries and helpers for pill-photo identification, candidate comparison, duplicate resolution, and schedule saving.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../controls/check_saved_medication_control.dart';
import '../controls/identify_pill_batch_control.dart';
import '../controls/identify_pill_control.dart';
import '../controls/resolve_duplicate_pill_selection_control.dart';
import '../entities/identified_pill_save_request_entity.dart';
import '../entities/medication_image_url_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/pill_identification_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import 'medication_schedule_review_ui_boundary.dart';

// 타입명: IdentifiedPillSaveCallback
// 역할: 사용자가 확인한 낱알약 후보와 복약 일정을 기존 저장 흐름으로 전달한다.
// 함수이름: IdentifiedPillSaveCallback
// 함수역할: 확인한 알약 후보와 검토한 복약 일정을 함께 저장하는 콜백 계약이다.
// 매개변수:
// - candidate (PillIdentificationCandidate): 사용자가 확인하거나 저장할 식별 후보 약품.
// - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// 반환값: Future<MedicationSaveResult>: 약품 저장 성공·중복·실패 상태.
typedef IdentifiedPillSaveCallback =
    Future<MedicationSaveResult> Function(
      PillIdentificationCandidate candidate,
      MedicationSchedule medicationSchedule,
    );

// 타입명: IdentifiedPillBatchSaveCallback
// 역할: 사용자가 확인한 여러 낱알약과 일정을 한 번의 저장 흐름으로 전달한다.
// 함수이름: IdentifiedPillBatchSaveCallback
// 함수역할: 후보·일정 요청 목록을 일괄 저장하고 항목별 결과를 반환하는 콜백 계약이다.
// 매개변수:
// - requests (List<IdentifiedPillSaveRequest>): 확인된 후보 약품과 검토 일정을 묶은 저장 요청 목록.
// 반환값: Future<List<MedicationSaveResult>>: 각 요청에 대응하는 저장 성공·중복·실패 결과 목록.
typedef IdentifiedPillBatchSaveCallback =
    Future<List<MedicationSaveResult>> Function(
      List<IdentifiedPillSaveRequest> requests,
    );

// 클래스명: PillIdentificationUI
// 역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장을 담당한다.
// 주요 책임:
// - 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 State가 사용할 화면 설정과 외부 의존성을 보관한다.
// 속성:
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - control (IdentifyPill?): 화면의 조회·변경 요청을 처리할 컨트롤러.
// - batchControl (IdentifyPillBatch?): 여러 알약 사진의 분석 순서·재시도 제어.
// - onSaveRequested (IdentifiedPillSaveCallback?): 검증한 약품과 복약 정보를 저장할 콜백.
class PillIdentificationUI extends StatefulWidget {
  final UserSetting userSetting;
  final IdentifyPill? control;
  final IdentifyPillBatch? batchControl;
  final IdentifiedPillSaveCallback? onSaveRequested;
  final IdentifiedPillBatchSaveCallback? onBatchSaveRequested;

  // 함수이름: PillIdentificationUI
  // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - control (IdentifyPill?): 화면의 조회·변경 요청을 처리할 컨트롤러.
  // - batchControl (IdentifyPillBatch?): 여러 알약 사진의 분석 순서·재시도 제어.
  // - onSaveRequested (IdentifiedPillSaveCallback?): 검증한 약품과 복약 정보를 저장할 콜백.
  // - onBatchSaveRequested (IdentifiedPillBatchSaveCallback?): 선택한 약품 또는 분석 결과를 일괄 저장할 콜백.
  // 반환값: 입력 설정이 반영된 PillIdentificationUI 인스턴스.
  const PillIdentificationUI({
    super.key,
    required this.userSetting,
    this.control,
    this.batchControl,
    this.onSaveRequested,
    this.onBatchSaveRequested,
  });

  // Function Name: createState
  // Description: Creates the state object that coordinates front and back pill photos, candidate selection, and medication saving.
  // Parameters:
  // - None.
  // Returns: A new _PillIdentificationUIState instance.
  @override
  State<PillIdentificationUI> createState() => _PillIdentificationUIState();
}

// 클래스명: _PillPhotoDraft
// 역할: 한 알약의 사진·분석 결과·선택 후보 상태를 담당한다.
// 주요 책임:
// - 필수 앞면 사진 바이트가 있는지 확인한다.
// - 앞면 또는 뒷면 사진 중 하나라도 있는지 확인한다.
// 속성:
// - result (PillIdentificationResult?): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
class _PillPhotoDraft {
  Uint8List? frontImage;
  Uint8List? backImage;
  PillIdentificationResult? result;
  String? selectedItemSeq;
  String errorMessage = '';
  PillBoundingBox? sourceRegion;
  Uint8List? croppedFrontImage;
  int visibleCandidateCount = 5;

  // 함수이름: hasFrontImage
  // 함수역할: 필수 앞면 사진 바이트가 있는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get hasFrontImage => frontImage != null;
  // 함수이름: hasAnyImage
  // 함수역할: 앞면 또는 뒷면 사진 중 하나라도 있는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get hasAnyImage => frontImage != null || backImage != null;

  // 함수이름: clearResult
  // 함수역할: 사진은 유지하면서 분석 결과·선택 후보·오류만 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void clearResult() {
    croppedFrontImage = null;
    result = null;
    selectedItemSeq = null;
    errorMessage = '';
    visibleCandidateCount = 5;
  }
}

// 클래스명: _DuplicatePillResolution
// 역할: 같은 약으로 선택된 사진의 일정 병합 여부를 담당한다.
// 주요 책임:
// - 같은 약으로 선택된 사진의 일정 병합 여부에서 지원하는 선택지를 열거하고 구분한다: mergeMatchingSchedules, keepSeparate.
enum _DuplicatePillResolution { mergeMatchingSchedules, keepSeparate }

// Class Name: _PillIdentificationUIState
// Role: Manages state for front and back pill photos, candidate selection, and medication saving.
// Responsibilities:
// - Builds photo-set and gallery batch-add controls based on experiment availability, busy state, and capacity.
// - Displays completed per-photo results together with the confirm-all action.
// - Builds a photo's empty, low-confidence, candidate-selection, and retry states.
// Attributes:
// - _control (IdentifyPill): Controller handling this screen's queries and update requests.
// - _batchControl (IdentifyPillBatch): Controller coordinating multi-pill photo analysis and retries.
// - _isSaving (bool): Whether the associated save, analysis, or medication update is in progress.
// - _retryAfter (Duration?): Delay required before a retry.
class _PillIdentificationUIState extends State<PillIdentificationUI> {
  late final IdentifyPill _control;
  late final IdentifyPillBatch _batchControl;
  late final bool _ownsControl;
  final ResolveDuplicatePillSelectionControl _duplicateSelectionControl =
      const ResolveDuplicatePillSelectionControl();
  final List<_PillPhotoDraft> _drafts = [_PillPhotoDraft()];
  Uint8List? _multiplePillSourceImage;
  List<MultiplePillObservation> _multiplePillObservations = const [];
  bool _isAnalyzing = false;
  bool _isSelectingImage = false;
  bool _isSaving = false;
  bool _isBatchSaved = false;
  int _analysisCompletedCount = 0;
  int _analysisTotalCount = 0;
  int _retryingRequestCount = 0;
  Duration? _retryAfter;
  int? _selectingDraftIndex;
  bool? _selectingFront;
  String _errorMessage = '';
  int? _refiningDraftIndex;

  // 함수이름: _isBusy
  // 함수역할: 분석·사진 선택·저장 중 어느 작업이라도 진행 중인지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get _isBusy => _isAnalyzing || _isSelectingImage || _isSaving;

  // 함수이름: _batchEnabled
  // 함수역할: 현재 사용자 설정에서 여러 알약 식별 실험 기능이 켜져 있는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get _batchEnabled =>
      widget.userSetting.multiPillIdentificationLabEnabled;

  // 함수이름: _allDraftsReady
  // 함수역할: 작업이 하나 이상 있고 모든 작업에 필수 앞면 사진이 있는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get _allDraftsReady =>
      // 함수이름: _allDraftsReady.every callback
      // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 대해 `draft.hasFrontImage` 조건으로 컬렉션 항목을 판별한다.
      // 매개변수:
      // - draft (콜백 계약에서 추론): 앞·뒷면 사진과 결과·선택을 보관한 알약 작업 초안.
      // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
      _drafts.isNotEmpty && _drafts.every((draft) => draft.hasFrontImage);

  // 함수이름: _pendingDraftIndexes
  // 함수역할: 앞면 사진은 있지만 분석 결과가 아직 없는 작업의 위치를 수집한다.
  // 매개변수:
  // - 없음.
  // 반환값: List<int>: 앞면 사진이 있지만 결과가 없는 작업 인덱스 목록.
  List<int> get _pendingDraftIndexes => [
    for (var index = 0; index < _drafts.length; index += 1)
      if (_drafts[index].hasFrontImage && _drafts[index].result == null) index,
  ];

  // 함수이름: _canConfirmAll
  // 함수역할: 이미 저장된 작업을 제외하고 모든 사진에 결과·후보·사용자 선택이 준비됐는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get _canConfirmAll {
    if (_isBatchSaved || !_allDraftsReady) {
      return false;
    }
    // 함수이름: _canConfirmAll.every callback
    // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 대해 `result != null && result.candidates.isNotEmpty && draft.selectedItemSeq != null` 조건으로 컬렉션 항목을 판별한다.
    // 매개변수:
    // - draft (콜백 계약에서 추론): 앞·뒷면 사진과 결과·선택을 보관한 알약 작업 초안.
    // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
    return _drafts.every((draft) {
      final result = draft.result;
      return result != null &&
          result.candidates.isNotEmpty &&
          draft.selectedItemSeq != null;
    });
  }

  // 함수이름: initState
  // 함수역할: 단일 알약 컨트롤러의 소유 여부를 정하고 주입 또는 기본 일괄 분석 컨트롤러를 연결한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    _ownsControl = widget.control == null;
    _control = widget.control ?? IdentifyPill();
    _batchControl =
        widget.batchControl ?? IdentifyPillBatch(singlePillControl: _control);
  }

  // Function Name: dispose
  // Description: Releases _control and detaches this screen from active updates.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void dispose() {
    if (_ownsControl) {
      _control.dispose();
    }
    super.dispose();
  }

  // Function Name: build
  // Description: Renders front and back pill photos, candidate selection, and medication saving from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for front and back pill photos, candidate selection, and medication saving.
  @override
  Widget build(BuildContext context) {
    final text = _PillIdentificationText(
      widget.userSetting.language,
      batchEnabled: _batchEnabled,
    );
    final textScale = widget.userSetting.contentTextScale;
    final pendingCount = _pendingDraftIndexes.length;
    // 함수이름: build.any callback
    // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 대해 `draft.result != null` 조건으로 컬렉션 항목을 판별한다.
    // 매개변수:
    // - draft (콜백 계약에서 추론): 앞·뒷면 사진과 결과·선택을 보관한 알약 작업 초안.
    // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
    final hasVisibleResults = _drafts.any((draft) => draft.result != null);
    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      appBar: AppBar(
        backgroundColor: MedBuddyColors.pageBackground,
        foregroundColor: MedBuddyColors.textStrong,
        elevation: 0,
        title: Text(
          text.title,
          style: TextStyle(
            fontSize: 20 * textScale,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SafetyNotice(text: text, textScale: textScale),
              const SizedBox(height: 22),
              Text(
                text.photoSectionTitle,
                style: TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 18 * textScale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text.photoSectionDescription,
                style: TextStyle(
                  color: MedBuddyColors.textMuted,
                  fontSize: 13 * textScale,
                  height: 1.45,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 16),
              if (_multiplePillSourceImage != null)
                _MultiplePillObservationPreview(
                  imageBytes: _multiplePillSourceImage!,
                  observations: _multiplePillObservations,
                  textScale: textScale,
                  description: text.multiplePhotoPreviewDescription,
                )
              else
                for (var index = 0; index < _drafts.length; index += 1) ...[
                  _buildPhotoDraft(index, text, textScale),
                  if (index < _drafts.length - 1) const Divider(height: 32),
                ],
              const SizedBox(height: 14),
              _buildAddPhotoActions(text, textScale),
              // 함수이름: build.any callback
              // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 대해 `draft.hasAnyImage` 조건으로 컬렉션 항목을 판별한다.
              // 매개변수:
              // - draft (콜백 계약에서 추론): 앞·뒷면 사진과 결과·선택을 보관한 알약 작업 초안.
              // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
              if (!_allDraftsReady && _drafts.any((draft) => draft.hasAnyImage))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    text.frontPhotoRequiredForEveryPill,
                    style: TextStyle(
                      color: const Color(0xFF9A6700),
                      fontSize: 12 * textScale,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 14),
                _ErrorNotice(message: _errorMessage),
              ],
              if (_multiplePillSourceImage == null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    key: const Key('identify-pill-button'),
                    onPressed: !_allDraftsReady || pendingCount == 0 || _isBusy
                        ? null
                        : _requestIdentification,
                    style: FilledButton.styleFrom(
                      backgroundColor: MedBuddyColors.primary,
                      disabledBackgroundColor: MedBuddyColors.outline,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _isAnalyzing
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(
                      _isAnalyzing
                          ? text.analysisProgress(
                              completedCount: _analysisCompletedCount,
                              totalCount: _analysisTotalCount,
                              isWaitingForRetry: _retryingRequestCount > 0,
                            )
                          : text.identifyPills(pendingCount),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17 * textScale,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ],
              if (_isAnalyzing && _retryingRequestCount > 0) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    text.retryWaitNotice(_retryAfter),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF8A6200),
                      fontSize: 12 * textScale,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              if (hasVisibleResults) ...[
                const SizedBox(height: 30),
                _buildAllResults(text, textScale),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 함수이름: _buildPhotoDraft
  // 함수역할: 알약 한 개의 앞·뒷면 사진 입력과 개별 오류 상태를 표시한다.
  // 매개변수:
  // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
  // - text (_PillIdentificationText): 해당 화면 구역의 언어별 표시 문구.
  // - textScale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 쓰는 위젯 트리.
  Widget _buildPhotoDraft(
    int index,
    _PillIdentificationText text,
    double textScale,
  ) {
    final draft = _drafts[index];
    final frontSlotKey = index == 0
        ? const Key('pill-front-image-slot')
        : Key('pill-front-image-slot-$index');
    final backSlotKey = index == 0
        ? const Key('pill-back-image-slot')
        : Key('pill-back-image-slot-$index');
    final frontRemoveKey = index == 0
        ? const Key('remove-pill-front-image-button')
        : Key('remove-pill-front-image-button-$index');
    final backRemoveKey = index == 0
        ? const Key('remove-pill-back-image-button')
        : Key('remove-pill-back-image-button-$index');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                text.pillPhotoTitle(index + 1),
                style: TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 15 * textScale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (draft.result != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  text.comparisonComplete,
                  style: TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 12 * textScale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (_drafts.length > 1)
              IconButton(
                key: Key('remove-pill-photo-set-$index'),
                tooltip: text.removePillPhotoSet(index + 1),
                // 함수이름: _buildPhotoDraft.onPressed callback
                // 함수역할: 처리 중이 아니고 작업이 둘 이상일 때 지정 사진 작업을 제거한다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onPressed: _isBusy ? null : () => _removePhotoDraft(index),
                icon: const Icon(Icons.delete_outline),
                color: MedBuddyColors.textMuted,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _PillImageSlot(
                key: frontSlotKey,
                label: text.frontPhoto,
                requiredLabel: text.requiredLabel,
                imageBytes: draft.frontImage,
                isLoading:
                    _isSelectingImage &&
                    _selectingDraftIndex == index &&
                    _selectingFront == true,
                removeButtonKey: frontRemoveKey,
                removeTooltip: text.removePhoto(text.frontPhoto),
                onRemove: draft.frontImage == null || _isBusy
                    ? null
                    // 함수이름: _buildPhotoDraft.onRemove callback
                    // 함수역할: 지정 앞·뒷면 사진과 그 사진에 의존한 분석·저장 상태를 지운다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    : () => _removeImage(index: index, isFront: true),
                onTap: _isBusy
                    ? null
                    // 함수이름: _buildPhotoDraft.onTap callback
                    // 함수역할: 사진 출처를 선택받아 대상 앞·뒷면을 교체하고 이전 다중 사진·분석 결과를 무효화한다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    : () => _selectImage(
                        draftIndex: index,
                        isFront: true,
                        text: text,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PillImageSlot(
                key: backSlotKey,
                label: text.backPhoto,
                requiredLabel: text.optionalLabel,
                imageBytes: draft.backImage,
                isLoading:
                    _isSelectingImage &&
                    _selectingDraftIndex == index &&
                    _selectingFront == false,
                removeButtonKey: backRemoveKey,
                removeTooltip: text.removePhoto(text.backPhoto),
                onRemove: draft.backImage == null || _isBusy
                    ? null
                    // 함수이름: _buildPhotoDraft.onRemove callback
                    // 함수역할: 지정 앞·뒷면 사진과 그 사진에 의존한 분석·저장 상태를 지운다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    : () => _removeImage(index: index, isFront: false),
                onTap: _isBusy
                    ? null
                    // 함수이름: _buildPhotoDraft.onTap callback
                    // 함수역할: 사진 출처를 선택받아 대상 앞·뒷면을 교체하고 이전 다중 사진·분석 결과를 무효화한다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    : () => _selectImage(
                        draftIndex: index,
                        isFront: false,
                        text: text,
                      ),
              ),
            ),
          ],
        ),
        if (draft.errorMessage.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ErrorNotice(message: draft.errorMessage),
        ],
      ],
    );
  }

  // Function Name: _buildAddPhotoActions
  // Description: Builds photo-set and gallery batch-add controls based on experiment availability, busy state, and capacity.
  // Parameters:
  // - text (_PillIdentificationText): Localized labels used by this section.
  // - textScale (double): Content text scale reflecting user accessibility settings.
  // Returns: Widget tree for front and back pill photos, candidate selection, and medication saving.
  Widget _buildAddPhotoActions(_PillIdentificationText text, double textScale) {
    if (!_batchEnabled) {
      return const SizedBox.shrink();
    }
    // 함수이름: _buildAddPhotoActions.where callback
    // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 대해 `draft.hasFrontImage` 조건으로 컬렉션 항목을 판별한다.
    // 매개변수:
    // - draft (콜백 계약에서 추론): 앞·뒷면 사진과 결과·선택을 보관한 알약 작업 초안.
    // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
    final occupiedCount = _drafts.where((draft) => draft.hasFrontImage).length;
    final canAddPhotoSet =
        !_isBusy &&
        (_multiplePillSourceImage != null ||
            _drafts.length < IdentifyPillBatch.maxBatchSize);
    final canAddGalleryImages =
        !_isBusy && occupiedCount < IdentifyPillBatch.maxBatchSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('identify-multiple-pills-from-one-photo-button'),
          onPressed: _isBusy
              ? null
              : _multiplePillSourceImage != null &&
                    _multiplePillObservations.isEmpty
              // Function Name: _buildAddPhotoActions.onPressed callback
              // Description: Replaces drafts with one source photo, then expands detected observations into per-pill candidate drafts.
              // Parameters:
              // - None.
              // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
              ? () => _analyzeMultiplePillPhoto(_multiplePillSourceImage!, text)
              // Function Name: _buildAddPhotoActions.onPressed callback
              // Description: Selects a photo containing multiple pills and sends it to multi-observation analysis.
              // Parameters:
              // - None.
              // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
              : () => _selectMultiplePillPhoto(text),
          icon: _isAnalyzing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.center_focus_strong_outlined),
          label: Text(
            _multiplePillSourceImage == null
                ? text.identifyMultipleFromOnePhoto
                : _multiplePillObservations.isEmpty
                ? text.retryMultiplePillPhoto
                : text.retakeMultiplePillPhoto,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14 * textScale,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('add-pill-photo-set-button'),
          onPressed: canAddPhotoSet ? _addPhotoDraft : null,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(
            text.addAnotherPill,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14 * textScale,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          key: const Key('add-multiple-pill-images-button'),
          onPressed: canAddGalleryImages
              // 함수이름: _buildAddPhotoActions.onPressed callback
              // 함수역할: 남은 일괄 용량만큼 갤러리 사진을 받아 빈 작업부터 앞면 사진으로 채운다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              ? () => _selectMultipleFrontImages(text)
              : null,
          icon: _isSelectingImage && _selectingDraftIndex == null
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.photo_library_outlined),
          label: Text(
            text.addMultipleFromGallery,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14 * textScale,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          text.batchLimitNotice(IdentifyPillBatch.maxBatchSize),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MedBuddyColors.textSubtle,
            fontSize: 11 * textScale,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  // 함수이름: _buildAllResults
  // 함수역할: 분석이 끝난 사진별 결과와 전체 선택 확정 동작을 함께 표시한다.
  // 매개변수:
  // - text (_PillIdentificationText): 해당 화면 구역의 언어별 표시 문구.
  // - textScale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 쓰는 위젯 트리.
  Widget _buildAllResults(_PillIdentificationText text, double textScale) {
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
          _buildRefinementActions(resultIndexes[position], text, textScale),
          _buildResultForDraft(resultIndexes[position], text, textScale),
          if (position < resultIndexes.length - 1) const Divider(height: 34),
        ],
        if (resultIndexes.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('confirm-pill-candidate-button'),
              onPressed: !_canConfirmAll || _isBusy
                  ? null
                  // 함수이름: _buildAllResults.onPressed callback
                  // 함수역할: 모든 사진의 선택을 모아 중복 처리 방식을 확인한 뒤 일정 검토·저장 또는 선택 안내를 진행한다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                  : () => _confirmCandidates(text),
              style: OutlinedButton.styleFrom(
                foregroundColor: MedBuddyColors.primaryDark,
                side: const BorderSide(
                  color: MedBuddyColors.primary,
                  width: 1.5,
                ),
                minimumSize: const Size.fromHeight(54),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isBatchSaved
                        ? Icons.check_circle_outline
                        : Icons.verified_outlined,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _isBatchSaved
                          ? text.savedComplete
                          : text.confirmSelections(_drafts.length),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16 * textScale,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // 함수이름: _buildRefinementActions
  // 함수역할: 번호별 영역 재분석과 같은 알약의 뒷면 추가를 제공한다.
  // 매개변수: index는 알약 위치, text는 번역, textScale은 글씨 배율이다.
  // 반환값: 결과를 보존하는 재분석 버튼과 해당 알약의 진행·오류 표시.
  Widget _buildRefinementActions(
    int index,
    _PillIdentificationText text,
    double textScale,
  ) {
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
                label: Text(
                  text.refineRegion(index + 1),
                  style: TextStyle(fontSize: 13 * textScale),
                ),
                // 함수이름: 영역 재분석 콜백
                // 함수역할: 이 번호의 영역만 재분석한다. 매개변수: 없음. 반환값: 완료 Future.
                onPressed: _isBusy || _isBatchSaved
                    ? null
                    : () => _refineDraft(index, text, addBack: false),
              ),
            OutlinedButton.icon(
              key: Key('refine-pill-back-$index'),
              icon: const Icon(Icons.cameraswitch_outlined),
              label: Text(
                text.addBack(index + 1),
                style: TextStyle(fontSize: 13 * textScale),
              ),
              // 함수이름: 뒷면 추가 콜백
              // 함수역할: 동일 알약 여부를 확인받고 앞·뒷면을 비교한다. 매개변수: 없음. 반환값: 완료 Future.
              onPressed: _isBusy || _isBatchSaved
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

  // 함수이름: _refineDraft
  // 함수역할: 원본 영역 또는 사용자가 대응시킨 뒷면으로 한 알약만 다시 분석한다.
  // 매개변수: index는 알약 위치, text는 번역, addBack은 뒷면 추가 여부이다.
  // 반환값: 완료 Future. 취소·실패 시 기존 결과와 다른 알약의 선택을 유지한다.
  Future<void> _refineDraft(
    int index,
    _PillIdentificationText text, {
    required bool addBack,
  }) async {
    if (_isBusy || _isBatchSaved) return;
    final draft = _drafts[index];
    setState(() {
      _isSelectingImage = true;
      _selectingDraftIndex = index;
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
            title: Text(text.addBack(index + 1)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.memory(front, height: 140, fit: BoxFit.contain),
                  const SizedBox(height: 12),
                  Text(text.samePillBackNotice),
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
                label: Text(text.gallery),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(text.camera),
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
          _selectingDraftIndex = null;
        });
      }
    }
  }

  // 함수이름: _buildResultForDraft
  // 함수역할: 사진별 후보 부재·낮은 신뢰도·후보 선택·재시도 상태를 표시한다.
  // 매개변수:
  // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
  // - text (_PillIdentificationText): 해당 화면 구역의 언어별 표시 문구.
  // - textScale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 쓰는 위젯 트리.
  Widget _buildResultForDraft(
    int index,
    _PillIdentificationText text,
    double textScale,
  ) {
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
          textScale: textScale,
          // 함수이름: _buildResultForDraft.onRetry callback
          // 함수역할: 다중 알약 원본은 바로 재분석하고 개별 사진은 결과를 비워 재시도를 준비한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onRetry: actionsEnabled ? () => _prepareRetry(index) : null,
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
          Text(
            text.candidateTitleForPill(index + 1, result.candidates.length),
            style: TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 19 * textScale,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text.candidateDescription,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 13 * textScale,
              height: 1.4,
              letterSpacing: 0,
            ),
          ),
          if (!result.isConfident ||
              result.hasMoreCandidates ||
              result.observedFeatures.qualityIssues.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ConfidenceNotice(
              key: index == 0
                  ? const Key('pill-confidence-warning')
                  : Key('pill-confidence-warning-$index'),
              message: text.lowConfidenceNotice,
            ),
          ],
          const SizedBox(height: 14),
          if (result.hasMoreCandidates) ...[
            Text(
              text.tooManyCandidates,
              style: TextStyle(fontSize: 13 * textScale),
            ),
            const SizedBox(height: 12),
          ],
          for (final candidate in result.candidates.take(
            draft.visibleCandidateCount,
          )) ...[
            _PillCandidateCard(
              candidate: candidate,
              needsMoreEvidence:
                  !result.isConfident ||
                  result.hasMoreCandidates ||
                  result.observedFeatures.qualityIssues.isNotEmpty,
              selected: candidate.itemSeq == draft.selectedItemSeq,
              duplicateCount: candidate.itemSeq == draft.selectedItemSeq
                  ? _selectedCandidateCount(candidate)
                  : 1,
              text: text,
              textScale: textScale,
              onTap: actionsEnabled
                  // 함수이름: _buildResultForDraft.setState callback
                  // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `draft.selectedItemSeq = candidate.itemSeq; _isBatchSaved = false`로 갱신한다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                  // 함수이름: _buildResultForDraft.onTap callback
                  // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에서 캡처된 작업 `setState(() {draft.selectedItemSeq = candidate.itemSeq; _isBatchSaved = false;})`을 실행한다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                  ? () => setState(() {
                      draft.selectedItemSeq = candidate.itemSeq;
                      _isBatchSaved = false;
                    })
                  : null,
            ),
            const SizedBox(height: 10),
          ],
          if (draft.visibleCandidateCount < result.candidates.length)
            TextButton.icon(
              key: Key('more-pill-candidates-$index'),
              icon: const Icon(Icons.expand_more),
              label: Text(
                text.moreCandidates,
                style: TextStyle(fontSize: 14 * textScale),
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

  // Function Name: _selectImage
  // Description: Replaces the target front or back photo from the chosen source and invalidates prior multi-photo and analysis state.
  // Parameters:
  // - draftIndex (int): Zero-based position of the target medication, photo, or row.
  // - isFront (bool): Whether the required front photo rather than the back photo is targeted.
  // - text (_PillIdentificationText): Localized labels used by this section.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _selectImage({
    required int draftIndex,
    required bool isFront,
    required _PillIdentificationText text,
  }) async {
    if (_isBusy || draftIndex < 0 || draftIndex >= _drafts.length) {
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      // Function Name: _selectImage.builder callback
      // Description: Composes front and back pill photos, candidate selection, and medication saving with EdgeInsets.fromLTRB, SizedBox for the active layout.
      // Parameters:
      // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
      // Returns: Widget subtree for the described layout or fallback.
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ImageSourceOption(
                icon: Icons.photo_camera_outlined,
                title: text.camera,
                // Function Name: _selectImage.onTap callback
                // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context, ImageSource.camera)`.
                // Parameters:
                // - None.
                // Returns: No callback payload; any selection is delivered through the route result.
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              const SizedBox(height: 8),
              _ImageSourceOption(
                icon: Icons.photo_library_outlined,
                title: text.gallery,
                // Function Name: _selectImage.onTap callback
                // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context, ImageSource.gallery)`.
                // Parameters:
                // - None.
                // Returns: No callback payload; any selection is delivered through the route result.
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || source == null) {
      return;
    }
    // 함수이름: _selectImage.setState callback
    // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_isSelectingImage = true; _selectingDraftIndex = draftIndex; _selectingFront = isFront`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _isSelectingImage = true;
      _selectingDraftIndex = draftIndex;
      _selectingFront = isFront;
    });

    try {
      final imageBytes = await _control.requestPillImage(source);
      if (imageBytes == null || !mounted || draftIndex >= _drafts.length) {
        return;
      }
      // Function Name: _selectImage.setState callback
      // Description: Updates the local input or request state for front and back pill photos, candidate selection, and medication saving: `draft.frontImage = imageBytes; draft.backImage = imageBytes; _isBatchSaved = false`.
      // Parameters:
      // - None.
      // Returns: No payload; applies the captured state changes.
      setState(() {
        if (_multiplePillSourceImage != null) {
          _drafts
            ..clear()
            ..add(_PillPhotoDraft());
        }
        _clearMultiplePillPhoto();
        final draft = _drafts[draftIndex];
        if (isFront) {
          draft.frontImage = imageBytes;
        } else {
          draft.backImage = imageBytes;
        }
        draft.clearResult();
        _isBatchSaved = false;
        _errorMessage = '';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      // Function Name: _selectImage.setState callback
      // Description: Updates the local input or request state for front and back pill photos, candidate selection, and medication saving: `_errorMessage = _stateErrorMessage(error, text.imageSelectionFailed)`.
      // Parameters:
      // - None.
      // Returns: No payload; applies the captured state changes.
      setState(() {
        _errorMessage = _stateErrorMessage(error, text.imageSelectionFailed);
      });
    } finally {
      if (mounted) {
        // 함수이름: _selectImage.setState callback
        // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_isSelectingImage = false; _selectingDraftIndex = null; _selectingFront = null`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() {
          _isSelectingImage = false;
          _selectingDraftIndex = null;
          _selectingFront = null;
        });
      }
    }
  }

  // Function Name: _selectMultipleFrontImages
  // Description: Loads gallery photos up to remaining batch capacity, filling empty drafts first.
  // Parameters:
  // - text (_PillIdentificationText): Localized labels used by this section.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _selectMultipleFrontImages(_PillIdentificationText text) async {
    if (!_batchEnabled || _isBusy) {
      return;
    }
    final replacingMultiplePhoto = _multiplePillSourceImage != null;
    final occupiedCount = replacingMultiplePhoto
        ? 0
        // Function Name: _selectMultipleFrontImages.where callback
        // Description: Checks the collection condition `draft.hasFrontImage` for front and back pill photos, candidate selection, and medication saving.
        // Parameters:
        // - draft (inferred by callback contract): Pill draft containing front/back photos, result, and selection.
        // Returns: Boolean predicate result for the supplied item.
        : _drafts.where((draft) => draft.hasFrontImage).length;
    final remainingCapacity = IdentifyPillBatch.maxBatchSize - occupiedCount;
    if (remainingCapacity <= 0) {
      // Function Name: _selectMultipleFrontImages.setState callback
      // Description: Updates the local input or request state for front and back pill photos, candidate selection, and medication saving: `_errorMessage = text.batchLimitReached(IdentifyPillBatch.maxBatchSize)`.
      // Parameters:
      // - None.
      // Returns: No payload; applies the captured state changes.
      setState(() {
        _clearMultiplePillPhoto();
        _errorMessage = text.batchLimitReached(IdentifyPillBatch.maxBatchSize);
      });
      return;
    }

    // 함수이름: _selectMultipleFrontImages.setState callback
    // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_isSelectingImage = true; _selectingDraftIndex = null; _selectingFront = true`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _isSelectingImage = true;
      _selectingDraftIndex = null;
      _selectingFront = true;
    });
    try {
      final images = await _control.requestMultiplePillImagesFromGallery(
        limit: remainingCapacity,
      );
      if (!mounted || images.isEmpty) {
        return;
      }
      // Function Name: _selectMultipleFrontImages.setState callback
      // Description: Updates the local input or request state for front and back pill photos, candidate selection, and medication saving: `emptyDraft = draft; target.frontImage = image; _isBatchSaved = false`.
      // Parameters:
      // - None.
      // Returns: No payload; applies the captured state changes.
      setState(() {
        if (replacingMultiplePhoto) {
          _drafts
            ..clear()
            ..add(_PillPhotoDraft());
          _clearMultiplePillPhoto();
        }
        for (final image in images) {
          _PillPhotoDraft? emptyDraft;
          for (final draft in _drafts) {
            if (!draft.hasAnyImage) {
              emptyDraft = draft;
              break;
            }
          }
          final target = emptyDraft ?? _PillPhotoDraft();
          if (emptyDraft == null) {
            _drafts.add(target);
          }
          target.frontImage = image;
          target.clearResult();
        }
        _isBatchSaved = false;
        _errorMessage = '';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      // Function Name: _selectMultipleFrontImages.setState callback
      // Description: Updates the local input or request state for front and back pill photos, candidate selection, and medication saving: `_errorMessage = _stateErrorMessage(error, text.imageSelectionFailed)`.
      // Parameters:
      // - None.
      // Returns: No payload; applies the captured state changes.
      setState(() {
        _errorMessage = _stateErrorMessage(error, text.imageSelectionFailed);
      });
    } finally {
      if (mounted) {
        // 함수이름: _selectMultipleFrontImages.setState callback
        // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_isSelectingImage = false; _selectingDraftIndex = null; _selectingFront = null`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() {
          _isSelectingImage = false;
          _selectingDraftIndex = null;
          _selectingFront = null;
        });
      }
    }
  }

  // Function Name: _addPhotoDraft
  // Description: Adds a photo draft within batch feature and capacity limits, clearing prior multi-pill-photo state.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  void _addPhotoDraft() {
    if (!_batchEnabled ||
        _isBusy ||
        (_multiplePillSourceImage == null &&
            _drafts.length >= IdentifyPillBatch.maxBatchSize)) {
      return;
    }
    // Function Name: _addPhotoDraft.setState callback
    // Description: Updates the local input or request state for front and back pill photos, candidate selection, and medication saving: `_isBatchSaved = false; _errorMessage = ''`.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
    setState(() {
      if (_multiplePillSourceImage != null) {
        _drafts
          ..clear()
          ..add(_PillPhotoDraft());
      }
      _clearMultiplePillPhoto();
      _drafts.add(_PillPhotoDraft());
      _isBatchSaved = false;
      _errorMessage = '';
    });
  }

  // 함수이름: _removePhotoDraft
  // 함수역할: 처리 중이 아니고 작업이 둘 이상일 때 지정 사진 작업을 제거한다.
  // 매개변수:
  // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _removePhotoDraft(int index) {
    if (_isBusy || _drafts.length <= 1) {
      return;
    }
    // 함수이름: _removePhotoDraft.setState callback
    // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_isBatchSaved = false; _errorMessage = ''`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _drafts.removeAt(index);
      _isBatchSaved = false;
      _errorMessage = '';
    });
  }

  // 함수이름: _requestIdentification
  // 함수역할: 앞면 사진이 준비된 미분석 작업을 일괄 처리하고 진행·재시도·개별 실패 결과를 반영한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _requestIdentification() async {
    final pendingIndexes = _pendingDraftIndexes;
    if (!_allDraftsReady || pendingIndexes.isEmpty) {
      return;
    }
    final text = _PillIdentificationText(
      widget.userSetting.language,
      batchEnabled: _batchEnabled,
    );
    // 함수이름: _requestIdentification.setState callback
    // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_isAnalyzing = true; _isBatchSaved = false; _errorMessage = ''`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _isAnalyzing = true;
      _isBatchSaved = false;
      _errorMessage = '';
      _analysisCompletedCount = 0;
      _analysisTotalCount = pendingIndexes.length;
      _retryingRequestCount = 0;
      _retryAfter = null;
      for (final index in pendingIndexes) {
        _drafts[index].errorMessage = '';
      }
    });

    try {
      final outcomes = await _batchControl.requestBatchIdentification(
        [
          for (final index in pendingIndexes)
            PillImagePair(
              frontImage: _drafts[index].frontImage!,
              backImage: _drafts[index].backImage,
            ),
        ],
        // 함수이름: _requestIdentification.onProgress callback
        // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에서 캡처된 작업 `setState(() {_analysisCompletedCount = progress.completedCount; _analysisTotalCount = progress.totalCount; _retryingRequestCount = progress.re...`을 실행한다.
        // 매개변수:
        // - progress (콜백 계약에서 추론): 일괄 분석의 완료·전체·재시도 개수와 재시도 대기 정보.
        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          // 함수이름: _requestIdentification.setState callback
          // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_analysisCompletedCount = progress.completedCount; _analysisTotalCount = progress.totalCount; _retryingRequestCount = progress.retryingRequestCount`로 갱신한다.
          // 매개변수:
          // - 없음.
          // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
          setState(() {
            _analysisCompletedCount = progress.completedCount;
            _analysisTotalCount = progress.totalCount;
            _retryingRequestCount = progress.retryingRequestCount;
            _retryAfter = progress.retryAfter ?? _retryAfter;
          });
        },
      );
      if (!mounted) {
        return;
      }
      // 함수이름: _requestIdentification.setState callback
      // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `draft.result = result; draft.selectedItemSeq = null; draft.errorMessage = ''`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        for (final outcome in outcomes) {
          final draft = _drafts[pendingIndexes[outcome.index]];
          final result = outcome.result;
          if (result != null) {
            draft.result = result;
            draft.selectedItemSeq = null;
            draft.errorMessage = '';
          } else {
            draft.result = null;
            draft.selectedItemSeq = null;
            draft.errorMessage = _stateErrorMessage(
              outcome.error ?? StateError('Unknown pill batch failure.'),
              text.requestFailed,
            );
          }
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      // 함수이름: _requestIdentification.setState callback
      // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_errorMessage = _stateErrorMessage(error, text.requestFailed)`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _errorMessage = _stateErrorMessage(error, text.requestFailed);
      });
    } finally {
      if (mounted) {
        // 함수이름: _requestIdentification.setState callback
        // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_isAnalyzing = false; _retryingRequestCount = 0; _retryAfter = null`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() {
          _isAnalyzing = false;
          _retryingRequestCount = 0;
          _retryAfter = null;
        });
      }
    }
  }

  // Function Name: _selectMultiplePillPhoto
  // Description: Selects a photo containing multiple pills and sends it to multi-observation analysis.
  // Parameters:
  // - text (_PillIdentificationText): Localized labels used by this section.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _selectMultiplePillPhoto(_PillIdentificationText text) async {
    if (!_batchEnabled || _isBusy) {
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      // Function Name: _selectMultiplePillPhoto.builder callback
      // Description: Composes front and back pill photos, candidate selection, and medication saving with EdgeInsets.fromLTRB, SizedBox for the active layout.
      // Parameters:
      // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
      // Returns: Widget subtree for the described layout or fallback.
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ImageSourceOption(
                icon: Icons.photo_camera_outlined,
                title: text.camera,
                // Function Name: _selectMultiplePillPhoto.onTap callback
                // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context, ImageSource.camera)`.
                // Parameters:
                // - None.
                // Returns: No callback payload; any selection is delivered through the route result.
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              const SizedBox(height: 8),
              _ImageSourceOption(
                icon: Icons.photo_library_outlined,
                title: text.gallery,
                // Function Name: _selectMultiplePillPhoto.onTap callback
                // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context, ImageSource.gallery)`.
                // Parameters:
                // - None.
                // Returns: No callback payload; any selection is delivered through the route result.
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
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

  // Function Name: _analyzeMultiplePillPhoto
  // Description: Replaces drafts with one source photo, then expands detected observations into per-pill candidate drafts.
  // Parameters:
  // - image (Uint8List): Camera frame or image bytes used for analysis or preview.
  // - text (_PillIdentificationText): Localized labels used by this section.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _analyzeMultiplePillPhoto(
    Uint8List image,
    _PillIdentificationText text,
  ) async {
    // Function Name: _analyzeMultiplePillPhoto.setState callback
    // Description: Updates the local input or request state for front and back pill photos, candidate selection, and medication saving: `_isAnalyzing = true; _analysisCompletedCount = 0; _analysisTotalCount = 1`.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
    setState(() {
      _isAnalyzing = true;
      _analysisCompletedCount = 0;
      _analysisTotalCount = 1;
      _isBatchSaved = false;
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
        _analysisCompletedCount = 1;
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

  // Function Name: _clearMultiplePillPhoto
  // Description: Clears the multi-pill source photo and detected observations.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  void _clearMultiplePillPhoto() {
    _multiplePillSourceImage = null;
    _multiplePillObservations = const [];
  }

  // 함수이름: _removeImage
  // 함수역할: 지정 앞·뒷면 사진과 그 사진에 의존한 분석·저장 상태를 지운다.
  // 매개변수:
  // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
  // - isFront (bool): 뒷면 대신 필수 앞면 사진을 다룰지 여부.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _removeImage({required int index, required bool isFront}) {
    // 함수이름: _removeImage.setState callback
    // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `draft.frontImage = null; draft.backImage = null; _isBatchSaved = false`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      final draft = _drafts[index];
      if (isFront) {
        draft.frontImage = null;
      } else {
        draft.backImage = null;
      }
      draft.clearResult();
      _isBatchSaved = false;
      _errorMessage = '';
    });
  }

  // Function Name: _prepareRetry
  // Description: Immediately reanalyzes a multi-pill source or clears a single draft's result for retry.
  // Parameters:
  // - index (int): Zero-based position of the target medication, photo, or row.
  // Returns: None; updates state or performs the documented action.
  void _prepareRetry(int index) {
    final multipleImage = _multiplePillSourceImage;
    if (multipleImage != null) {
      final text = _PillIdentificationText(
        widget.userSetting.language,
        batchEnabled: _batchEnabled,
      );
      _analyzeMultiplePillPhoto(multipleImage, text);
      return;
    }
    // 함수이름: _prepareRetry.setState callback
    // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_isBatchSaved = false`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _drafts[index].clearResult();
      _isBatchSaved = false;
    });
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
  // 함수역할: 모든 사진의 선택을 모아 중복 처리 방식을 확인한 뒤 일정 검토·저장 또는 선택 안내를 진행한다.
  // 매개변수:
  // - text (_PillIdentificationText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _confirmCandidates(_PillIdentificationText text) async {
    final candidates = <PillIdentificationCandidate>[];
    for (final draft in _drafts) {
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

    final onSaveRequested = widget.onSaveRequested;
    final onBatchSaveRequested = widget.onBatchSaveRequested;
    if (onSaveRequested != null || onBatchSaveRequested != null) {
      await _reviewAndSaveCandidates(
        candidates: candidates,
        onSaveRequested: onSaveRequested,
        onBatchSaveRequested: onBatchSaveRequested,
        duplicateResolution: duplicateResolution,
        text: text,
      );
      return;
    }

    final confirmedCandidates =
        duplicateResolution == _DuplicatePillResolution.mergeMatchingSchedules
        ? _duplicateSelectionControl.uniqueCandidates(candidates)
        : candidates;

    // 저장 콜백이 없는 독립 실행 화면도 사용자가 선택한 중복 처리 방식을 반영한다.
    await showDialog<void>(
      context: context,
      // 함수이름: _confirmCandidates.builder callback
      // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context) => AlertDialog(
        title: Text(text.confirmedTitle),
        content: Text(
          confirmedCandidates.length == 1
              ? text.confirmedMessage(confirmedCandidates.first.itemName)
              : text.confirmedBatchMessage(
                  confirmedCandidates
                      // 함수이름: _confirmCandidates.map callback
                      // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 변환값을 `candidate.itemName` 규칙으로 계산한다.
                      // 매개변수:
                      // - candidate (콜백 계약에서 추론): 사용자가 확인하거나 저장할 식별 후보 약품.
                      // 반환값: 컬렉션 연산에 전달할 변환값.
                      .map((candidate) => candidate.itemName)
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            // Function Name: _confirmCandidates.onPressed callback
            // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context)`.
            // Parameters:
            // - None.
            // Returns: No callback payload; any selection is delivered through the route result.
            onPressed: () => Navigator.pop(context),
            child: Text(text.close),
          ),
        ],
      ),
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
        title: Text(text.duplicateSelectionTitle),
        content: Text(text.duplicateSelectionMessage(duplicatePhotoCount)),
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
            child: Text(text.keepDuplicateSchedulesSeparate),
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
            child: Text(text.mergeMatchingDuplicateSchedules),
          ),
        ],
      ),
    );
  }

  // 함수이름: _reviewAndSaveCandidates
  // 함수역할: 선택한 모든 후보에 안전한 임시 복약 기본값을 채워 한 화면에서 검토하게 한다. 확인된 일정들을 일괄 저장 콜백으로 전달하고 성공·중복·실패 건수를 안내한다.
  // 매개변수:
  // - candidates (List<PillIdentificationCandidate>): 선택·검토·저장할 식별 후보 약품 목록.
  // - onSaveRequested (IdentifiedPillSaveCallback?): 검증한 약품과 복약 정보를 저장할 콜백.
  // - onBatchSaveRequested (IdentifiedPillBatchSaveCallback?): 선택한 약품 또는 분석 결과를 일괄 저장할 콜백.
  // - duplicateResolution (_DuplicatePillResolution): 동일 약 사진의 일정을 병합하거나 유지하는 선택.
  // - text (_PillIdentificationText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _reviewAndSaveCandidates({
    required List<PillIdentificationCandidate> candidates,
    required IdentifiedPillSaveCallback? onSaveRequested,
    required IdentifiedPillBatchSaveCallback? onBatchSaveRequested,
    required _DuplicatePillResolution duplicateResolution,
    required _PillIdentificationText text,
  }) async {
    final reviewedSchedules = await showMedicationScheduleReview(
      context: context,
      initialSchedules: [
        for (final candidate in candidates)
          MedicationSchedule(
            medicationName: candidate.itemName,
            prescriptionDate: DateTime.now(),
            dosage: '1정',
            intakeTime: '1회',
            medicationTime: 1,
            scheduleSlotKeys: const [defaultMedicationScheduleSlotKey],
            imageUrl: candidate.imageUrl,
            nameConfidence: candidate.matchScore,
            nameCorrectionSource: 'pill_identification',
          ),
      ],
      userSetting: widget.userSetting,
      purpose: MedicationScheduleReviewPurpose.pillSave,
    );
    if (!mounted || reviewedSchedules == null) {
      return;
    }
    if (reviewedSchedules.length != candidates.length) {
      _showSnackBar(text.medicationSaveFailed);
      return;
    }

    final reviewedRequests = [
      for (var index = 0; index < candidates.length; index += 1)
        IdentifiedPillSaveRequest(
          candidate: candidates[index],
          medicationSchedule: reviewedSchedules[index],
        ),
    ];
    final requests =
        duplicateResolution == _DuplicatePillResolution.mergeMatchingSchedules
        ? _duplicateSelectionControl.mergeEquivalentRequests(reviewedRequests)
        : reviewedRequests;
    final mergedCount = reviewedRequests.length - requests.length;

    // 함수이름: _reviewAndSaveCandidates.setState callback
    // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_isSaving = true`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _isSaving = true);
    List<MedicationSaveResult> results;
    try {
      if (onBatchSaveRequested != null) {
        results = await onBatchSaveRequested(requests);
      } else {
        results = <MedicationSaveResult>[];
        for (final request in requests) {
          results.add(
            await onSaveRequested!(
              request.candidate,
              request.medicationSchedule,
            ),
          );
        }
      }
    } catch (_) {
      results = [
        for (var index = 0; index < requests.length; index += 1)
          MedicationSaveResult(
            status: MedicationSaveStatus.failed,
            message: text.medicationSaveFailed,
          ),
      ];
    } finally {
      if (mounted) {
        // 함수이름: _reviewAndSaveCandidates.setState callback
        // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_isSaving = false`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() => _isSaving = false);
      }
    }
    if (!mounted) {
      return;
    }

    final normalizedResults = results.length == requests.length
        ? results
        : [
            for (var index = 0; index < requests.length; index += 1)
              index < results.length
                  ? results[index]
                  : MedicationSaveResult(
                      status: MedicationSaveStatus.failed,
                      message: text.medicationSaveFailed,
                    ),
          ];
    final savedCount = normalizedResults
        // 함수이름: _reviewAndSaveCandidates.where callback
        // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 대해 `result.status == MedicationSaveStatus.saved` 조건으로 컬렉션 항목을 판별한다.
        // 매개변수:
        // - result (콜백 계약에서 추론): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
        // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
        .where((result) => result.status == MedicationSaveStatus.saved)
        .length;
    final duplicateCount = normalizedResults
        // 함수이름: _reviewAndSaveCandidates.where callback
        // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 대해 `result.status == MedicationSaveStatus.duplicate` 조건으로 컬렉션 항목을 판별한다.
        // 매개변수:
        // - result (콜백 계약에서 추론): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
        // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
        .where((result) => result.status == MedicationSaveStatus.duplicate)
        .length;
    final failedCount = normalizedResults
        // 함수이름: _reviewAndSaveCandidates.where callback
        // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장에 대해 `result.status == MedicationSaveStatus.failed` 조건으로 컬렉션 항목을 판별한다.
        // 매개변수:
        // - result (콜백 계약에서 추론): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
        // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
        .where((result) => result.status == MedicationSaveStatus.failed)
        .length;
    // 함수이름: _reviewAndSaveCandidates.setState callback
    // 함수역할: 알약 앞·뒷면 촬영과 후보 선택 후 복약 저장의 입력·요청 상태를 `_isBatchSaved = failedCount == 0`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _isBatchSaved = failedCount == 0;
    });

    final resultMessage = normalizedResults.length == 1
        ? switch (normalizedResults.first.status) {
            MedicationSaveStatus.saved => text.medicationSaved,
            MedicationSaveStatus.duplicate => text.medicationAlreadySaved,
            MedicationSaveStatus.failed =>
              normalizedResults.first.message.trim().isEmpty
                  ? text.medicationSaveFailed
                  : normalizedResults.first.message.trim(),
          }
        : text.batchSaveSummary(
            savedCount: savedCount,
            duplicateCount: duplicateCount,
            failedCount: failedCount,
          );
    _showSnackBar(text.withMergedDuplicateSummary(resultMessage, mergedCount));
  }

  // 함수이름: _showSnackBar
  // 함수역할: 기존 Snackbar를 교체하여 알약 분석·저장 결과 문구를 표시한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
    final text = _PillIdentificationText(
      widget.userSetting.language,
      batchEnabled: _batchEnabled,
    );
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

// Class Name: _MultiplePillObservationPreview
// Role: Represents identified regions and explanation over a multi-pill photo.
// Responsibilities:
// - Composes identified regions and explanation over a multi-pill photo using the display values and actions supplied by its parent.
// Attributes:
// - imageBytes (Uint8List): Camera frame or image bytes used for analysis or preview.
// - observations (List<MultiplePillObservation>): Pill positions and characteristics detected in the photo.
// - textScale (double): Content text scale reflecting user accessibility settings.
// - description (String): Supporting explanation or account detail below the primary label.
class _MultiplePillObservationPreview extends StatelessWidget {
  final Uint8List imageBytes;
  final List<MultiplePillObservation> observations;
  final double textScale;
  final String description;

  // Function Name: _MultiplePillObservationPreview
  // Description: Initializes identified regions and explanation over a multi-pill photo with the supplied configuration.
  // Parameters:
  // - imageBytes (Uint8List): Camera frame or image bytes used for analysis or preview.
  // - observations (List<MultiplePillObservation>): Pill positions and characteristics detected in the photo.
  // - textScale (double): Content text scale reflecting user accessibility settings.
  // - description (String): Supporting explanation or account detail below the primary label.
  // Returns: Initialized _MultiplePillObservationPreview instance.
  const _MultiplePillObservationPreview({
    required this.imageBytes,
    required this.observations,
    required this.textScale,
    required this.description,
  });

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
      label: description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Image.memory(
                  imageBytes,
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  gaplessPlayback: true,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _MultiplePillBoxPainter(observations),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 12 * textScale,
              height: 1.4,
            ),
          ),
        ],
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
            fontWeight: FontWeight.w800,
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

// Class Name: _SafetyNotice
// Role: Represents the safety limitations of identifying pills from appearance.
// Responsibilities:
// - Composes the safety limitations of identifying pills from appearance using the display values and actions supplied by its parent.
// Attributes:
// - textScale (double): Content text scale reflecting user accessibility settings.
class _SafetyNotice extends StatelessWidget {
  final _PillIdentificationText text;
  final double textScale;

  // Function Name: _SafetyNotice
  // Description: Initializes the safety limitations of identifying pills from appearance with the supplied configuration.
  // Parameters:
  // - text (_PillIdentificationText): Localized labels used by this section.
  // - textScale (double): Content text scale reflecting user accessibility settings.
  // Returns: Initialized _SafetyNotice instance.
  const _SafetyNotice({required this.text, required this.textScale});

  // Function Name: build
  // Description: Renders the safety limitations of identifying pills from appearance from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the safety limitations of identifying pills from appearance.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF0C36A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF9A6700), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text.safetyNotice,
              style: TextStyle(
                color: const Color(0xFF6B4B00),
                fontSize: 13 * textScale,
                height: 1.45,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Class Name: _PillImageSlot
// Role: Represents front or back pill-photo selection, loading, and removal.
// Responsibilities:
// - Composes front or back pill-photo selection, loading, and removal using the display values and actions supplied by its parent.
// Attributes:
// - label (String): Wording identifying a field, choice, or action.
// - requiredLabel (String): Wording identifying a field, choice, or action.
// - imageBytes (Uint8List?): Camera frame or image bytes used for analysis or preview.
// - isLoading (bool): Whether to show the in-progress state.
class _PillImageSlot extends StatelessWidget {
  final String label;
  final String requiredLabel;
  final Uint8List? imageBytes;
  final bool isLoading;
  final Key removeButtonKey;
  final String removeTooltip;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  // Function Name: _PillImageSlot
  // Description: Initializes front or back pill-photo selection, loading, and removal with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - label (String): Wording identifying a field, choice, or action.
  // - requiredLabel (String): Wording identifying a field, choice, or action.
  // - imageBytes (Uint8List?): Camera frame or image bytes used for analysis or preview.
  // - isLoading (bool): Whether to show the in-progress state.
  // - removeButtonKey (Key): Widget identity of the photo removal button.
  // - removeTooltip (String): Tooltip or accessibility wording describing an icon action.
  // - onRemove (VoidCallback?): Callback removing a photo or attachment selection.
  // - onTap (VoidCallback?): Callback executing the item's documented primary action.
  // Returns: Initialized _PillImageSlot instance.
  const _PillImageSlot({
    super.key,
    required this.label,
    required this.requiredLabel,
    required this.imageBytes,
    required this.isLoading,
    required this.removeButtonKey,
    required this.removeTooltip,
    required this.onRemove,
    required this.onTap,
  });

  // Function Name: build
  // Description: Renders front or back pill-photo selection, loading, and removal from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for front or back pill-photo selection, loading, and removal.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 174,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: imageBytes == null
                  ? MedBuddyColors.outline
                  : MedBuddyColors.primary,
              width: imageBytes == null ? 1.4 : 2,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MedBuddyColors.textStrong,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                        Text(
                          requiredLabel,
                          style: const TextStyle(
                            color: MedBuddyColors.textSubtle,
                            fontSize: 11,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (imageBytes != null)
                    SizedBox.square(
                      dimension: 48,
                      child: IconButton(
                        key: removeButtonKey,
                        tooltip: removeTooltip,
                        padding: EdgeInsets.zero,
                        iconSize: 19,
                        color: MedBuddyColors.textMuted,
                        onPressed: onRemove,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageBytes == null)
                        const ColoredBox(
                          color: MedBuddyColors.surfaceSubtle,
                          child: Center(
                            child: Icon(
                              Icons.add_a_photo_outlined,
                              color: MedBuddyColors.primary,
                              size: 34,
                            ),
                          ),
                        )
                      else
                        Image.memory(
                          imageBytes!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          cacheWidth: 900,
                        ),
                      if (isLoading)
                        const ColoredBox(
                          color: Color(0xB3FFFFFF),
                          child: Center(
                            child: CircularProgressIndicator(
                              key: Key('pill-image-loading-indicator'),
                              strokeWidth: 2.4,
                              color: MedBuddyColors.primary,
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
      ),
    );
  }
}

// 클래스명: _PillCandidateCard
// 역할: 후보 약품 정보·선택 상태·중복 사진 수를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 후보 약품 정보·선택 상태·중복 사진 수 위젯을 구성한다.
// 속성:
// - candidate (PillIdentificationCandidate): 사용자가 확인하거나 저장할 식별 후보 약품.
// - selected (bool): 현재 선택 집합에 포함되는지 여부.
// - duplicateCount (int): 중복으로 감지되거나 병합한 항목 수.
// - textScale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _PillCandidateCard extends StatelessWidget {
  final PillIdentificationCandidate candidate;
  final bool needsMoreEvidence;
  final bool selected;
  final int duplicateCount;
  final _PillIdentificationText text;
  final double textScale;
  final VoidCallback? onTap;

  // 함수이름: _PillCandidateCard
  // 함수역할: 후보 약품 정보·선택 상태·중복 사진 수에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - candidate (PillIdentificationCandidate): 사용자가 확인하거나 저장할 식별 후보 약품.
  // - selected (bool): 현재 선택 집합에 포함되는지 여부.
  // - duplicateCount (int): 중복으로 감지되거나 병합한 항목 수.
  // - text (_PillIdentificationText): 해당 화면 구역의 언어별 표시 문구.
  // - textScale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - onTap (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _PillCandidateCard 인스턴스.
  const _PillCandidateCard({
    required this.candidate,
    required this.needsMoreEvidence,
    required this.selected,
    required this.duplicateCount,
    required this.text,
    required this.textScale,
    required this.onTap,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 후보 약품 정보·선택 상태·중복 사진 수 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 후보 약품 정보·선택 상태·중복 사진 수에 쓰는 위젯 트리.
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
    return Semantics(
      container: true,
      selected: selected,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? MedBuddyColors.primary
                    : MedBuddyColors.divider,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CandidateImage(url: candidate.imageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.itemName,
                        style: TextStyle(
                          color: MedBuddyColors.textStrong,
                          fontSize: 15 * textScale,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      if (duplicateCount > 1) ...[
                        const SizedBox(height: 6),
                        Container(
                          key: Key('duplicate-pill-badge-${candidate.itemSeq}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3D6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            text.sameMedicinePhotoCount(duplicateCount),
                            style: TextStyle(
                              color: const Color(0xFF8A5A00),
                              fontSize: 11 * textScale,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                      if (candidate.manufacturer.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          candidate.manufacturer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MedBuddyColors.textSubtle,
                            fontSize: 12 * textScale,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '${needsMoreEvidence ? text.needsConfirmation : text.comparisonCandidate}'
                        '${imprint.isEmpty ? '' : '\n${text.imprintLabel}: $imprint'}',
                        style: TextStyle(
                          color: MedBuddyColors.primaryDark,
                          fontSize: 12 * textScale,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? MedBuddyColors.primary
                      : MedBuddyColors.textLight,
                  semanticLabel: selected ? text.selected : text.notSelected,
                ),
              ],
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
// - url (String): Medication image network URL used after validation.
class _CandidateImage extends StatelessWidget {
  final String url;

  // Function Name: _CandidateImage
  // Description: Initializes a candidate's safe network image and unavailable-image fallback with the supplied configuration.
  // Parameters:
  // - url (String): Medication image network URL used after validation.
  // Returns: Initialized _CandidateImage instance.
  const _CandidateImage({required this.url});

  // Function Name: build
  // Description: Renders a candidate's safe network image and unavailable-image fallback from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a candidate's safe network image and unavailable-image fallback.
  @override
  Widget build(BuildContext context) {
    final normalizedUrl = safeMedicationImageUrl(url);
    const placeholder = ColoredBox(
      color: MedBuddyColors.surfaceSubtle,
      child: Center(
        child: Icon(Icons.medication_outlined, color: MedBuddyColors.textLight),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox.square(
        dimension: 76,
        child: normalizedUrl.isEmpty
            ? placeholder
            : Image.network(
                normalizedUrl,
                fit: BoxFit.contain,
                cacheWidth: 228,
                cacheHeight: 228,
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
  }
}

// Class Name: _ImageSourceOption
// Role: Represents a camera or gallery source choice for pill photos.
// Responsibilities:
// - Composes a camera or gallery source choice for pill photos using the display values and actions supplied by its parent.
// Attributes:
// - icon (IconData): Icon shown in normal or selected state.
// - title (String): Heading shown for the screen, section, or item.
// - onTap (VoidCallback): Callback executing the item's documented primary action.
class _ImageSourceOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  // Function Name: _ImageSourceOption
  // Description: Initializes a camera or gallery source choice for pill photos with the supplied configuration.
  // Parameters:
  // - icon (IconData): Icon shown in normal or selected state.
  // - title (String): Heading shown for the screen, section, or item.
  // - onTap (VoidCallback): Callback executing the item's documented primary action.
  // Returns: Initialized _ImageSourceOption instance.
  const _ImageSourceOption({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  // Function Name: build
  // Description: Renders a camera or gallery source choice for pill photos from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a camera or gallery source choice for pill photos.
  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      tileColor: MedBuddyColors.surfaceSubtle,
      leading: Icon(icon, color: MedBuddyColors.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
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
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0F1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message,
          style: const TextStyle(color: Color(0xFFB42318), height: 1.4),
        ),
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
          color: const Color(0xFFFFF8E7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFF0C36A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFF9A6700),
              size: 21,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF6B4B00),
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

// 클래스명: _EmptyResult
// 역할: 후보 부재 안내와 사진 변경 후 재시도를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 후보 부재 안내와 사진 변경 후 재시도 위젯을 구성한다.
// 속성:
// - textScale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
// - onRetry (VoidCallback?): 실패하거나 오래된 화면 데이터를 다시 조회할 콜백.
class _EmptyResult extends StatelessWidget {
  final _PillIdentificationText text;
  final double textScale;
  final VoidCallback? onRetry;

  // 함수이름: _EmptyResult
  // 함수역할: 후보 부재 안내와 사진 변경 후 재시도에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_PillIdentificationText): 해당 화면 구역의 언어별 표시 문구.
  // - textScale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - onRetry (VoidCallback?): 실패하거나 오래된 화면 데이터를 다시 조회할 콜백.
  // 반환값: 입력 설정이 반영된 _EmptyResult 인스턴스.
  const _EmptyResult({
    required this.text,
    required this.textScale,
    this.onRetry,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 후보 부재 안내와 사진 변경 후 재시도 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 후보 부재 안내와 사진 변경 후 재시도에 쓰는 위젯 트리.
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
            Text(
              text.noCandidates,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 14 * textScale,
                height: 1.4,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(text.retryComparison),
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
// - batchEnabled (bool): Whether multi-pill photo identification is enabled.
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
  // 함수이름: needsConfirmation
  // 함수역할: 확정 확률 대신 추가 확인 상태를 표시한다. 매개변수: 없음. 반환값: 상태.
  String get needsConfirmation =>
      isEnglish ? 'More evidence needed' : '추가 확인 필요';
  // 함수이름: comparisonCandidate
  // 함수역할: 확정되지 않은 비교 후보임을 표시한다. 매개변수: 없음. 반환값: 상태.
  String get comparisonCandidate =>
      isEnglish ? 'Candidate for comparison' : '비교 후보';
  // 함수이름: imprintLabel
  // 함수역할: 참고 각인 표시명을 번역한다. 매개변수: 없음. 반환값: 표시명.
  String get imprintLabel => isEnglish ? 'Catalog imprint' : '제품 각인';
  final String language;
  final bool batchEnabled;

  // 함수이름: _PillIdentificationText
  // 함수역할: 알약 사진 식별, 후보 비교 및 중복 조정 후 일정 저장에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // - batchEnabled (bool): 여러 알약 사진 식별을 사용할지 여부.
  // 반환값: 입력 설정이 반영된 _PillIdentificationText 인스턴스.
  const _PillIdentificationText(this.language, {required this.batchEnabled});

  // Function Name: isEnglish
  // Description: Checks whether the language code is exactly en.
  // Parameters:
  // - None.
  // Returns: True when the documented condition holds; false otherwise.
  bool get isEnglish => language == 'en';
  // Function Name: title
  // Description: Provides localized wording for "Identify a Pill" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get title => isEnglish ? 'Identify a Pill' : '알약 식별';
  // Function Name: safetyNotice
  // Description: Provides localized wording for "Photos are analyzed by an external AI and are not stored by MedBuddy. Matching only suggests candidates; verify the package or ..." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get safetyNotice => isEnglish
      ? 'Photos are analyzed by an external AI and are not stored by MedBuddy. Matching only suggests candidates; verify the package or ask a pharmacist.'
      : '사진은 외부 AI로 분석되며 MedBuddy에 저장되지 않습니다. 비교 결과는 후보일 뿐이므로 포장 정보 또는 약사에게 확인하세요.';
  // Function Name: photoSectionTitle
  // Description: Provides localized wording for "Photograph one or more pills" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get photoSectionTitle {
    if (batchEnabled) {
      return isEnglish ? 'Photograph one or more pills' : '알약을 한 개 이상 촬영해주세요';
    }
    return isEnglish ? 'Add a pill photo' : '알약 사진을 추가해주세요';
  }

  // Function Name: photoSectionDescription
  // Description: Provides localized wording for "For the fastest review, place up to 10 separated pills in one clear photo. You can still add separate front and back photos whe..." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get photoSectionDescription {
    if (batchEnabled) {
      return isEnglish
          ? 'For the fastest review, place up to 10 separated pills in one clear photo. You can still add separate front and back photos when closer inspection is needed.'
          : '가장 빠르게 확인하려면 서로 겹치지 않은 알약을 최대 10개까지 한 장에 선명하게 촬영하세요. 자세한 비교가 필요하면 알약별 앞뒷면 사진도 추가할 수 있습니다.';
    }
    return isEnglish
        ? 'Keep one pill in focus with its outline visible. Adding its reverse side improves matching.'
        : '알약 한 알의 윤곽이 보이도록 선명하게 촬영하세요. 뒷면 사진을 추가하면 정확도가 높아집니다.';
  }

  // 함수이름: pillPhotoTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "알약 $number 사진" 문구를 제공한다.
  // 매개변수:
  // - number (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String pillPhotoTitle(int number) =>
      isEnglish ? 'Pill $number photo' : '알약 $number 사진';
  // 함수이름: comparisonComplete
  // 함수역할: 현재 언어와 입력값에 맞춰 "비교 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get comparisonComplete => isEnglish ? 'Compared' : '비교 완료';
  // 함수이름: removePillPhotoSet
  // 함수역할: 현재 언어와 입력값에 맞춰 "알약 $number 사진 묶음 삭제" 문구를 제공한다.
  // 매개변수:
  // - number (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String removePillPhotoSet(int number) =>
      isEnglish ? 'Remove pill $number photo set' : '알약 $number 사진 묶음 삭제';
  // 함수이름: addAnotherPill
  // 함수역할: 현재 언어와 입력값에 맞춰 "알약 한 개 더 추가" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get addAnotherPill => isEnglish ? 'Add another pill' : '알약 한 개 더 추가';
  // 함수이름: addMultipleFromGallery
  // 함수역할: 현재 언어와 입력값에 맞춰 "갤러리에서 여러 알약 사진 추가" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get addMultipleFromGallery =>
      isEnglish ? 'Add multiple pill photos from gallery' : '갤러리에서 여러 알약 사진 추가';
  // Function Name: identifyMultipleFromOnePhoto
  // Description: Provides localized wording for "Find every pill in one photo" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get identifyMultipleFromOnePhoto =>
      isEnglish ? 'Find every pill in one photo' : '한 장에서 모든 알약 찾기';
  // Function Name: retakeMultiplePillPhoto
  // Description: Provides localized wording for "Retake the group photo" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get retakeMultiplePillPhoto =>
      isEnglish ? 'Retake the group photo' : '여러 알약 사진 다시 촬영';
  // Function Name: retryMultiplePillPhoto
  // Description: Provides localized wording for "Analyze this photo again" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get retryMultiplePillPhoto =>
      isEnglish ? 'Analyze this photo again' : '이 사진 다시 분석';
  // Function Name: multiplePhotoPreviewDescription
  // Description: Provides localized wording for "Detected pills are numbered on the photo. Review the candidate list for every number before saving." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get multiplePhotoPreviewDescription => isEnglish
      ? 'Detected pills are numbered on the photo. Review the candidate list for every number before saving.'
      : '사진에서 찾은 알약에 번호를 표시했습니다. 저장하기 전에 각 번호의 후보를 모두 확인해주세요.';
  // 함수이름: batchLimitNotice
  // 함수역할: 현재 언어와 입력값에 맞춰 "한 번에 최대 $limit개까지 가능하며, 알약마다 앞면 사진이 한 장씩 필요합니다." 문구를 제공한다.
  // 매개변수:
  // - limit (int): 허용할 최대 항목 수 또는 문자열 길이.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String batchLimitNotice(int limit) => isEnglish
      ? 'Up to $limit pills per batch. Use one front photo for each pill.'
      : '한 번에 최대 $limit개까지 가능하며, 알약마다 앞면 사진이 한 장씩 필요합니다.';
  // 함수이름: batchLimitReached
  // 함수역할: 현재 언어와 입력값에 맞춰 "알약은 한 번에 최대 $limit개까지 비교할 수 있습니다." 문구를 제공한다.
  // 매개변수:
  // - limit (int): 허용할 최대 항목 수 또는 문자열 길이.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String batchLimitReached(int limit) => isEnglish
      ? 'You can compare up to $limit pills at once.'
      : '알약은 한 번에 최대 $limit개까지 비교할 수 있습니다.';
  // 함수이름: frontPhotoRequiredForEveryPill
  // 함수역할: 현재 언어와 입력값에 맞춰 "비교를 시작하려면 모든 알약에 앞면 사진을 추가해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get frontPhotoRequiredForEveryPill {
    if (batchEnabled) {
      return isEnglish
          ? 'Add a front photo for every pill before starting the comparison.'
          : '비교를 시작하려면 모든 알약에 앞면 사진을 추가해주세요.';
    }
    return isEnglish
        ? 'Add a front photo before starting the comparison.'
        : '비교를 시작하려면 알약 앞면 사진을 추가해주세요.';
  }

  // Function Name: frontPhoto
  // Description: Provides localized wording for "Front" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get frontPhoto => isEnglish ? 'Front' : '앞면';
  // Function Name: backPhoto
  // Description: Provides localized wording for "Back" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get backPhoto => isEnglish ? 'Back' : '뒷면';
  // Function Name: requiredLabel
  // Description: Provides localized wording for "Required" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get requiredLabel => isEnglish ? 'Required' : '필수';
  // Function Name: optionalLabel
  // Description: Provides localized wording for "Optional" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get optionalLabel => isEnglish ? 'Optional' : '선택';
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
  // 함수이름: identifyPills
  // 함수역할: 현재 언어와 입력값에 맞춰 "Find candidates for $normalizedCount pill${normalizedCount == 1 ?" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String identifyPills(int count) {
    final normalizedCount = count < 1 ? 1 : count;
    return isEnglish
        ? 'Find candidates for $normalizedCount pill${normalizedCount == 1 ? '' : 's'}'
        : '알약 $normalizedCount개 후보 찾기';
  }

  // 함수이름: analyzingPills
  // 함수역할: 현재 언어와 입력값에 맞춰 "Comparing $normalizedCount pill${normalizedCount == 1 ?" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String analyzingPills(int count) {
    final normalizedCount = count < 1 ? 1 : count;
    return isEnglish
        ? 'Comparing $normalizedCount pill${normalizedCount == 1 ? '' : 's'}...'
        : '알약 $normalizedCount개 비교 중...';
  }

  // 함수이름: analysisProgress
  // 함수역할: 현재 언어와 입력값에 맞춰 "자동 재시도 대기 중 · $completedCount/$safeTotal 완료" 문구를 제공한다.
  // 매개변수:
  // - completedCount (int): 완료한 복약 횟수.
  // - totalCount (int): 예정된 전체 복약 횟수 또는 처리 항목 수.
  // - isWaitingForRetry (bool): 자동 재시도 대기 단계인지 여부.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String analysisProgress({
    required int completedCount,
    required int totalCount,
    required bool isWaitingForRetry,
  }) {
    final safeTotal = totalCount < 1 ? 1 : totalCount;
    if (isWaitingForRetry) {
      return isEnglish
          ? 'Waiting to retry · $completedCount/$safeTotal completed'
          : '자동 재시도 대기 중 · $completedCount/$safeTotal 완료';
    }
    return isEnglish
        ? 'Comparing pills · $completedCount/$safeTotal completed'
        : '알약 비교 중 · $completedCount/$safeTotal 완료';
  }

  // 함수이름: retryWaitNotice
  // 함수역할: 현재 언어와 입력값에 맞춰 "요청이 많아 잠시 기다린 뒤 실패 항목만 자동으로 다시 시도합니다." 문구를 제공한다.
  // 매개변수:
  // - retryAfter (Duration?): 재시도 전에 기다려야 할 시간.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String retryWaitNotice(Duration? retryAfter) {
    final seconds = retryAfter?.inSeconds;
    if (seconds == null || seconds < 1) {
      return isEnglish
          ? 'Request traffic is high. Failed items will retry automatically.'
          : '요청이 많아 잠시 기다린 뒤 실패 항목만 자동으로 다시 시도합니다.';
    }
    return isEnglish
        ? 'Retrying failed items automatically in up to $seconds seconds.'
        : '최대 $seconds초 뒤 실패 항목만 자동으로 다시 시도합니다.';
  }

  // Function Name: candidateTitle
  // Description: Provides localized wording for "$count possible matches" using the current language and message inputs.
  // Parameters:
  // - count (int): Item count or ordinal number used in wording or a list.
  // Returns: The formatted display text or identifier described above.
  String candidateTitle(int count) =>
      isEnglish ? '$count possible matches' : '가능성이 있는 후보 $count개';
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
  // Function Name: removePhoto
  // Description: Provides localized wording for "Remove $label photo" using the current language and message inputs.
  // Parameters:
  // - label (String): Wording identifying a field, choice, or action.
  // Returns: The formatted display text or identifier described above.
  String removePhoto(String label) =>
      isEnglish ? 'Remove $label photo' : '$label 사진 삭제';
  // Function Name: candidateDescription
  // Description: Provides localized wording for "Select the closest product and verify every printed detail." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get candidateDescription => isEnglish
      ? 'Select the closest product and verify every printed detail.'
      : '가장 가까운 제품을 선택한 뒤 각인과 제품 정보를 직접 대조하세요.';
  // Function Name: lowConfidenceNotice
  // Description: Provides localized wording for "These matches are uncertain or the photo needs extra care. Compare both sides and every imprint before confirming." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get lowConfidenceNotice => isEnglish
      ? 'These matches are uncertain or the photo needs extra care. Compare both sides and every imprint before confirming.'
      : '후보 일치도가 낮거나 사진 품질에 주의가 필요합니다. 앞뒷면과 각인 정보를 직접 비교한 뒤 선택하세요.';
  // Function Name: similarity
  // Description: Provides localized wording for "Attribute match" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get similarity => isEnglish ? 'Attribute match' : '속성 일치도';
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
      ? count == 1
            ? 'Confirm selected candidate'
            : 'Review and save $count selected pills'
      : count == 1
      ? '선택한 후보 확인'
      : '선택한 알약 $count개 검토 후 저장';
  // 함수이름: savedComplete
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get savedComplete => isEnglish ? 'Saved' : '저장 완료';
  // Function Name: confirmedTitle
  // Description: Provides localized wording for "Candidate selected" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get confirmedTitle => isEnglish ? 'Candidate selected' : '후보 선택 완료';
  // Function Name: confirmedMessage
  // Description: Provides localized wording for "$name was selected as a possible match. This is not a diagnosis; verify it with the package or a pharmacist." using the current language and message inputs.
  // Parameters:
  // - name (String): Medication or account name shown to the user.
  // Returns: The formatted display text or identifier described above.
  String confirmedMessage(String name) => isEnglish
      ? '$name was selected as a possible match. This is not a diagnosis; verify it with the package or a pharmacist.'
      : '$name을(를) 가능한 후보로 선택했습니다. 확정 결과가 아니므로 포장 정보 또는 약사에게 확인하세요.';
  // 함수이름: confirmedBatchMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 ")}을(를) 가능한 후보로 선택했습니다. 확정 결과가 아니므로 각 포장 정보 또는 약사에게 확인하세요." 문구를 제공한다.
  // 매개변수:
  // - names (List<String>): 요약·전송 문구에 포함할 약품 이름 목록.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String confirmedBatchMessage(List<String> names) => isEnglish
      ? '${names.join(', ')} were selected as possible matches. These are not confirmed results; verify each package or ask a pharmacist.'
      : '${names.join(', ')}을(를) 가능한 후보로 선택했습니다. 확정 결과가 아니므로 각 포장 정보 또는 약사에게 확인하세요.';
  // 함수이름: medicationSaved
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 정보를 저장했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationSaved =>
      isEnglish ? 'Medication plan saved.' : '복약 정보를 저장했습니다.';
  // 함수이름: medicationAlreadySaved
  // 함수역할: 현재 언어와 입력값에 맞춰 "같은 복약 정보가 이미 저장되어 있습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationAlreadySaved => isEnglish
      ? 'The same medication plan is already saved.'
      : '같은 복약 정보가 이미 저장되어 있습니다.';
  // 함수이름: medicationSaveFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 정보를 저장하지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationSaveFailed =>
      isEnglish ? 'Could not save the medication plan.' : '복약 정보를 저장하지 못했습니다.';
  // 함수이름: batchSaveSummary
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장 $savedCount개, 기존 정보 $duplicateCount개, 실패 $failedCount개입니다." 문구를 제공한다.
  // 매개변수:
  // - savedCount (int): 저장에 성공한 항목 수.
  // - duplicateCount (int): 중복으로 감지되거나 병합한 항목 수.
  // - failedCount (int): 저장 또는 처리에 실패한 항목 수.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String batchSaveSummary({
    required int savedCount,
    required int duplicateCount,
    required int failedCount,
  }) => isEnglish
      ? 'Saved $savedCount, already saved $duplicateCount, failed $failedCount.'
      : '저장 $savedCount개, 기존 정보 $duplicateCount개, 실패 $failedCount개입니다.';
  // 함수이름: withMergedDuplicateSummary
  // 함수역할: 현재 언어와 입력값에 맞춰 "동일한 복약 일정 $mergedCount개를 하나로 묶었습니다. $resultMessage" 문구를 제공한다.
  // 매개변수:
  // - resultMessage (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // - mergedCount (int): 중복으로 감지되거나 병합한 항목 수.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String withMergedDuplicateSummary(String resultMessage, int mergedCount) {
    if (mergedCount < 1) {
      return resultMessage;
    }
    return isEnglish
        ? 'Merged $mergedCount identical schedule${mergedCount == 1 ? '' : 's'}. $resultMessage'
        : '동일한 복약 일정 $mergedCount개를 하나로 묶었습니다. $resultMessage';
  }

  // Function Name: close
  // Description: Provides localized wording for "Close" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get close => isEnglish ? 'Close' : '닫기';
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
