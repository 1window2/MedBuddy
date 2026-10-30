// 파일명: prescription_analysis_preview_ui_boundary.dart
// 역할: OCR 결과 검토와 약별 복약 정보 수정·추가를 제공한다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities/json_value_reader.dart';
import '../entities/medication_dose_rhythm.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/medication_schedule_limits.dart';
import '../entities/medication_slot_label.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_match_review_entity.dart';
import '../entities/prescription_flow_entity.dart';
import 'medication_candidate_dialog.dart';
import '../entities/recognized_text_region_entity.dart';
import '../entities/user_setting_entity.dart';
import '../widgets/medbuddy_confirm_dialog.dart';
import '../widgets/expandable_medication_section.dart';
import '../widgets/medbuddy_notice.dart';
import '../widgets/medication_dosing_mode_selector.dart';
import '../widgets/medication_entry_fields.dart';
import '../widgets/pinned_analysis_summary.dart';
import '../widgets/responsive_card_header.dart';
import '../theme/medbuddy_theme.dart';

part 'prescription_preview_image_widgets.dart';
part 'prescription_preview_medication_widgets.dart';
part 'prescription_lookup_summary_widgets.dart';

// 타입명: MedicationScheduleChangedCallback
// 역할: 수정된 OCR 복약 일정과 원본 목록 인덱스를 상위 상태에 전달한다.
// 함수이름: MedicationScheduleChangedCallback
// 함수역할: 수정된 복약 일정과 원래 목록 위치를 호출 화면에 전달하는 계약이다.
// 매개변수:
// - scheduleIndex (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
// - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
typedef MedicationScheduleChangedCallback =
    void Function(int scheduleIndex, MedicationSchedule medicationSchedule);

// 타입명: MedicationScheduleAddedCallback
// 역할: OCR에서 누락된 약을 사용자가 직접 입력한 뒤 상위 상태에 전달한다.
// 함수이름: MedicationScheduleAddedCallback
// 함수역할: 누락 약품을 위해 새로 만든 복약 일정을 호출 화면에 전달하는 계약이다.
// 매개변수:
// - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
typedef MedicationScheduleAddedCallback =
    void Function(MedicationSchedule medicationSchedule);

// 파일명: prescription_analysis_preview_ui_boundary.dart
// 역할: UC-1 OCR 결과를 사용자에게 먼저 확인시키는 분석 예비 화면을 구성한다.

// 클래스명: PrescriptionAnalysisPreviewUI
// 역할: 약별 세로 카드에서 복약 정보 검토·수정·후보 선택과 분석 재개를 담당한다.
// 주요 책임:
// - OCR 결과의 약별 정보를 가로 넘김 없이 세로로 비교하게 한다.
// - 사용자가 각 항목을 눌러 잘못 인식된 값을 바로 수정하게 한다.
// - OCR 누락 약은 같은 입력 형식으로 직접 추가하게 한다.
// - 미확인 약은 같은 카드의 후보 확인 버튼과 확인 상태로 구분한다.
// - 분석 전에 뒤로가기를 통해 촬영 단계로 돌아갈 수 있게 한다.
// 속성:
// - medicationScheduleList (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
// - recognizedTextRegions (List<RecognizedTextRegion>): 이미지 좌표에 표시할 정규화 OCR 영역.
// - previewImagePath (String): 사진 미리보기 또는 확대에 사용할 로컬 파일 경로.
// - recognitionNotice (String): OCR 결과 또는 인식 한계에 대한 안내.
class PrescriptionAnalysisPreviewUI extends StatefulWidget {
  final List<MedicationSchedule> medicationScheduleList;
  final List<RecognizedTextRegion> recognizedTextRegions;
  final String previewImagePath;
  final String recognitionNotice;
  final UserSetting userSetting;
  final VoidCallback onBackRequested;
  final VoidCallback onAnalysisRequested;
  final MedicationScheduleChangedCallback onMedicationScheduleChanged;
  final MedicationScheduleAddedCallback? onMedicationScheduleAdded;
  final Set<int> verifiedScheduleIndexes;
  final bool isMedicationLookupReview;
  final VoidCallback? onVerifiedOnlyContinueRequested;
  final Map<int, MedicationMatchReview> matchReviews;
  final Map<int, MedicationLookupStatus> lookupStatuses;
  final void Function(int, MedicationDetail)? onCandidateConfirmed;

  // 함수이름: PrescriptionAnalysisPreviewUI
  // 함수역할: OCR 복약 표 검토·수정·추가와 분석 재개에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - medicationScheduleList (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
  // - recognizedTextRegions (List<RecognizedTextRegion>): 이미지 좌표에 표시할 정규화 OCR 영역.
  // - previewImagePath (String): 사진 미리보기 또는 확대에 사용할 로컬 파일 경로.
  // - recognitionNotice (String): OCR 결과 또는 인식 한계에 대한 안내.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - onBackRequested (VoidCallback): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
  // - onAnalysisRequested (VoidCallback): 검토한 복약 정보의 분석을 시작하거나 다시 요청할 콜백.
  // - onMedicationScheduleChanged (MedicationScheduleChangedCallback): 수정한 일정과 인덱스를 호출 화면에 반영할 콜백.
  // - onMedicationScheduleAdded (MedicationScheduleAddedCallback?): 새로 입력한 약품 일정을 추가할 콜백.
  // - verifiedScheduleIndexes (Set<int>): 약품 상세 조회로 검증된 일정 인덱스 집합.
  // - isMedicationLookupReview (bool): 약품 상세 조회 실패 항목을 다시 검토하는지 여부.
  // - onVerifiedOnlyContinueRequested (VoidCallback?): 확인된 약품만으로 분석 또는 저장을 이어갈 콜백.
  // 반환값: 입력 설정이 반영된 PrescriptionAnalysisPreviewUI 인스턴스.
  const PrescriptionAnalysisPreviewUI({
    super.key,
    required this.medicationScheduleList,
    this.recognizedTextRegions = const [],
    this.previewImagePath = '',
    this.recognitionNotice = '',
    required this.userSetting,
    required this.onBackRequested,
    required this.onAnalysisRequested,
    required this.onMedicationScheduleChanged,
    this.onMedicationScheduleAdded,
    this.verifiedScheduleIndexes = const {},
    this.isMedicationLookupReview = false,
    this.onVerifiedOnlyContinueRequested,
    this.matchReviews = const {},
    this.lookupStatuses = const {},
    this.onCandidateConfirmed,
  });

  // 함수이름: createState
  // 함수역할: OCR 복약 표 검토·수정·추가와 분석 재개의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _PrescriptionAnalysisPreviewUIState 인스턴스.
  @override
  State<PrescriptionAnalysisPreviewUI> createState() =>
      _PrescriptionAnalysisPreviewUIState();
}

// Class Name: _PrescriptionAnalysisPreviewUIState
// Role: Manages state for OCR schedule-table review, editing, addition, and analysis continuation.
// Responsibilities:
// - Adds medication missed by OCR using the existing editor layout, prefills editable date, batch, and duration defaults from the first prescription, and forwards the confirmed addition.
class _PrescriptionAnalysisPreviewUIState
    extends State<PrescriptionAnalysisPreviewUI> {
  bool _isAnalysisRequested = false;
  bool _isVerifiedOnlyConfirmationOpen = false;

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 OCR 복약 표 검토·수정·추가와 분석 재개 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: OCR 복약 표 검토·수정·추가와 분석 재개에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final text = _PreviewText(widget.userSetting.language);
    final recognitionNotice = widget.recognitionNotice.trim();
    // 요약 개수와 약 카드가 같은 행별 조회 상태를 쓰도록 한 번만 정한다.
    // 조회 이력이 없는 행은 카드에서 결과를 단정하지 않고, 요약에서는 아직 조회할 약으로 센다.
    final rowLookupStatuses = <MedicationLookupStatus?>[
      for (var index = 0; index < widget.medicationScheduleList.length; index++)
        widget.verifiedScheduleIndexes.contains(index)
            ? MedicationLookupStatus.verified
            : widget.lookupStatuses[index] ??
                  (widget.matchReviews[index]?.candidates.isNotEmpty == true
                      ? MedicationLookupStatus.candidates
                      : null),
    ];
    final lookupCounts = <MedicationLookupStatus, int>{};
    for (final status in rowLookupStatuses) {
      lookupCounts.update(
        status ?? MedicationLookupStatus.pending,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final allVerified =
        widget.isMedicationLookupReview &&
        widget.medicationScheduleList.isNotEmpty &&
        widget.verifiedScheduleIndexes.length ==
            widget.medicationScheduleList.length;
    final hasReviewRequired = widget.medicationScheduleList.any(
      // 함수이름: build.any callback
      // 함수역할: OCR 복약 표 검토·수정·추가와 분석 재개에 대해 `schedule.isNameReviewRequired` 조건으로 컬렉션 항목을 판별한다.
      // 매개변수:
      // - schedule (콜백 계약에서 추론): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
      // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
      (schedule) => schedule.isNameReviewRequired,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _AnalysisBottomBar(
        label: allVerified
            ? (text.isEnglish ? 'View results' : '결과 보기')
            : widget.isMedicationLookupReview
            ? text.retryUnverifiedMedications
            : hasReviewRequired
            ? text.reviewBeforeAnalyze
            : text.confirmAndAnalyze,
        onPressed: _isAnalysisRequested ? null : _requestAnalysis,
        continueLabel: widget.isMedicationLookupReview && !allVerified
            ? text.continueWithVerifiedOnly
            : null,
        onContinue:
            !_isAnalysisRequested &&
                !_isVerifiedOnlyConfirmationOpen &&
                widget.verifiedScheduleIndexes.isNotEmpty &&
                widget.onVerifiedOnlyContinueRequested != null
            ? _confirmVerifiedOnlyContinue
            : null,
      ),
      body: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          color: MedBuddyColors.pageBackground,
          child: Column(
            children: [
              PrescriptionFlowBackButton(
                tooltip: text.back,
                onBackRequested: widget.onBackRequested,
              ),
              Expanded(
                child: _PrescriptionReviewLayout(
                  title: text.title(DateTime.now()),
                  isEnglish: text.isEnglish,
                  showSummary: widget.isMedicationLookupReview,
                  counts: lookupCounts,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (recognitionNotice.isNotEmpty) ...[
                          _RecognitionNoticeBanner(message: recognitionNotice),
                          const SizedBox(height: 12),
                        ],
                        if (widget.previewImagePath.trim().isNotEmpty) ...[
                          _RecognizedTextRegionPreview(
                            imagePath: widget.previewImagePath,
                            regions: widget.recognizedTextRegions,
                            previewText: text,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (widget.onMedicationScheduleAdded != null) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              key: const Key('ocr-add-medication-button'),
                              onPressed: _showMedicationCreator,
                              icon: const Icon(Icons.add_rounded),
                              label: Text(text.addMissingMedication),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        _PreviewMedicationList(
                          medicationScheduleList: widget.medicationScheduleList,
                          previewText: text,
                          userSetting: widget.userSetting,
                          onEditRequested: _showMedicationEditor,
                          verifiedScheduleIndexes:
                              widget.verifiedScheduleIndexes,
                          isMedicationLookupReview:
                              widget.isMedicationLookupReview,
                          matchReviews: widget.matchReviews,
                          lookupStatuses: rowLookupStatuses,
                          onCandidateRequested:
                              widget.onCandidateConfirmed == null
                              ? null
                              : _showMedicationCandidates,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMedicationCandidates(
    int index,
    MedicationMatchReview review,
  ) async {
    final schedule = widget.medicationScheduleList[index];
    final selected = await showDialog<MedicationDetail>(
      context: context,
      builder: (context) => MedicationCandidateDialog(
        originalName:
            schedule.rawMedicationName.isEmpty ||
                {
                  'user_edit',
                  'manual_add',
                  'user_selection',
                }.contains(schedule.nameCorrectionSource)
            ? schedule.medicationName
            : schedule.rawMedicationName,
        candidates: review.candidates,
        isEnglish: widget.userSetting.isEnglish,
      ),
    );
    if (!mounted ||
        selected == null ||
        !identical(widget.matchReviews[index], review)) {
      return;
    }
    widget.onCandidateConfirmed?.call(index, selected);
  }

  // 함수이름: _showMedicationEditor
  // 함수역할: 선택한 표 셀의 OCR 인식 결과를 수정하는 대화상자를 연다. 누른 셀에 해당하는 입력란으로 바로 이동해 중복 검토 화면 없이 수정하게 한다. 수정이 완료되면 목록의 실제 인덱스와 변경값을 상위 상태로 전달한다.
  // 매개변수:
  // - scheduleIndex (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
  // - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - initialField (_MedicationScheduleEditField): 편집 창에서 선택할 복약 정보 입력 항목.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showMedicationEditor(
    int scheduleIndex,
    MedicationSchedule medicationSchedule,
    _MedicationScheduleEditField initialField,
  ) async {
    final updatedSchedule = await showDialog<MedicationSchedule>(
      context: context,
      // 함수이름: _showMedicationEditor.builder callback
      // 함수역할: OCR 복약 표 검토·수정·추가와 분석 재개에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context) => _MedicationScheduleEditDialog(
        medicationSchedule: medicationSchedule,
        previewText: _PreviewText(widget.userSetting.language),
        userSetting: widget.userSetting,
        initialField: initialField,
      ),
    );
    if (!mounted || updatedSchedule == null) {
      return;
    }

    widget.onMedicationScheduleChanged(scheduleIndex, updatedSchedule);
  }

  // Function Name: _showMedicationCreator
  // Description: Adds medication missed by OCR using the existing editor layout, prefills editable date, batch, and duration defaults from the first prescription, and forwards the confirmed addition.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _showMedicationCreator() async {
    final referenceSchedule = widget.medicationScheduleList.isEmpty
        ? null
        : widget.medicationScheduleList.first;
    final defaultSchedule = MedicationSchedule(
      medicationName: '',
      prescriptionDate: referenceSchedule?.prescriptionDate ?? DateTime.now(),
      prescriptionBatchId: referenceSchedule?.prescriptionBatchId ?? '',
      dosage: '1',
      intakeTime: '1회',
      medicationTime: referenceSchedule?.medicationTime ?? 1,
      scheduleSlotKeys: const [defaultMedicationScheduleSlotKey],
      nameConfidence: 1,
      nameCorrectionSource: 'manual_add',
    );
    final addedSchedule = await showDialog<MedicationSchedule>(
      context: context,
      // 함수이름: _showMedicationCreator.builder callback
      // 함수역할: OCR 복약 표 검토·수정·추가와 분석 재개에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context) => _MedicationScheduleEditDialog(
        medicationSchedule: defaultSchedule,
        previewText: _PreviewText(widget.userSetting.language),
        userSetting: widget.userSetting,
        initialField: _MedicationScheduleEditField.medicationName,
        isNewSchedule: true,
      ),
    );
    if (!mounted || addedSchedule == null) {
      return;
    }
    widget.onMedicationScheduleAdded?.call(addedSchedule);
  }

  // 함수이름: _confirmVerifiedOnlyContinue
  // 함수역할: 미확인 약이 결과에서 제외된다는 사실을 사용자가 확인한 경우에만 다음 단계로 진행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _confirmVerifiedOnlyContinue() async {
    if (_isAnalysisRequested ||
        _isVerifiedOnlyConfirmationOpen ||
        widget.verifiedScheduleIndexes.isEmpty) {
      return;
    }
    setState(() => _isVerifiedOnlyConfirmationOpen = true);
    final text = _PreviewText(widget.userSetting.language);
    final unverifiedCount =
        widget.medicationScheduleList.length -
        widget.verifiedScheduleIndexes.length;
    try {
      final shouldContinue = await showMedBuddyConfirmDialog(
        context,
        title: text.continueWithVerifiedTitle,
        message: text.continueWithVerifiedWarning(unverifiedCount),
        cancelLabel: text.cancel,
        confirmLabel: text.continueLabel,
        cancelKey: const Key('cancel-verified-only-continue'),
        confirmKey: const Key('confirm-verified-only-continue'),
      );
      if (shouldContinue && mounted) {
        widget.onVerifiedOnlyContinueRequested?.call();
      }
    } finally {
      if (mounted) setState(() => _isVerifiedOnlyConfirmationOpen = false);
    }
  }

  // 함수이름: _requestAnalysis
  // 함수역할: 현재 표에서 확인한 OCR 값을 그대로 사용해 상세 분석을 시작한다. 빠른 연속 입력으로 같은 분석이 중복 요청되지 않게 막는다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _requestAnalysis() {
    if (_isAnalysisRequested || _isVerifiedOnlyConfirmationOpen) {
      return;
    }
    // 함수이름: _requestAnalysis.setState callback
    // 함수역할: OCR 복약 표 검토·수정·추가와 분석 재개의 입력·요청 상태를 `_isAnalysisRequested = true`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _isAnalysisRequested = true);
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    widget.onAnalysisRequested();
  }
}
