// 파일명: prescription_analysis_preview_ui_boundary.dart
// 역할: 기기 내 OCR 결과, 개인정보 마스킹과 약명 보정 화면을 제공한다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities/medication_schedule_entity.dart';
import '../entities/recognized_text_region_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

part 'prescription_preview_image_widgets.dart';
part 'prescription_preview_medication_widgets.dart';

// 타입명: MedicationScheduleChangedCallback
// 역할: 수정된 OCR 복약 일정과 원본 목록 인덱스를 상위 상태에 전달한다.
typedef MedicationScheduleChangedCallback =
    void Function(int scheduleIndex, MedicationSchedule medicationSchedule);

// 타입명: MedicationScheduleAddedCallback
// 역할: OCR에서 누락된 약을 사용자가 직접 입력한 뒤 상위 상태에 전달한다.
typedef MedicationScheduleAddedCallback =
    void Function(MedicationSchedule medicationSchedule);

// 파일명: prescription_analysis_preview_ui_boundary.dart
// 역할: UC-1 OCR 결과를 사용자에게 먼저 확인시키는 분석 예비 화면을 구성한다.

// 클래스명: PrescriptionAnalysisPreviewUI
// 역할: 처방전에서 인식된 약별 복약 정보를 하나의 수정 가능한 표로 보여준다.
// 주요 책임:
// - OCR 결과의 모든 항목을 가로 스크롤 표로 비교하게 한다.
// - 사용자가 표의 각 셀을 눌러 잘못 인식된 값을 바로 수정하게 한다.
// - OCR 누락 약은 같은 입력 형식으로 직접 추가하게 한다.
// - 상세조회에 실패한 약은 확인된 약과 구분해 같은 표에서 다시 검토하게 한다.
// - 분석 전에 뒤로가기를 통해 촬영 단계로 돌아갈 수 있게 한다.
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
  });

  @override
  State<PrescriptionAnalysisPreviewUI> createState() =>
      _PrescriptionAnalysisPreviewUIState();
}

class _PrescriptionAnalysisPreviewUIState
    extends State<PrescriptionAnalysisPreviewUI> {
  final ScrollController _tableScrollController = ScrollController();
  bool _isAnalysisRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTableScrollHint();
    });
  }

  @override
  void dispose() {
    _tableScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _PreviewText(widget.userSetting.language);
    final scale = widget.userSetting.contentTextScale;
    final recognitionNotice = widget.recognitionNotice.trim();
    final hasReviewRequired = widget.medicationScheduleList.any(
      (schedule) => schedule.isNameReviewRequired,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _AnalysisBottomBar(
        label: widget.isMedicationLookupReview
            ? text.retryUnverifiedMedications
            : hasReviewRequired
            ? text.reviewBeforeAnalyze
            : text.confirmAndAnalyze,
        scale: scale,
        onPressed: _isAnalysisRequested ? null : _requestAnalysis,
      ),
      body: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [MedBuddyColors.analysisBackground, Colors.white],
            ),
          ),
          child: Column(
            children: [
              _TopBackButton(
                tooltip: text.back,
                onBackRequested: widget.onBackRequested,
              ),
              Expanded(
                child: _ScrollableCenteredCard(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(31, 32, 31, 30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: MedBuddyColors.outline,
                        width: 2,
                      ),
                      boxShadow: MedBuddyShadows.card,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          text.title(DateTime.now()),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: MedBuddyColors.textStrong,
                            fontSize: 26 * scale,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        if (widget.isMedicationLookupReview) ...[
                          const SizedBox(height: 14),
                          _MedicationLookupReviewBanner(
                            message: text.lookupReviewGuide(
                              widget.medicationScheduleList.length -
                                  widget.verifiedScheduleIndexes.length,
                            ),
                            scale: scale,
                          ),
                          const SizedBox(height: 20),
                        ] else if (recognitionNotice.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _RecognitionNoticeBanner(
                            message: recognitionNotice,
                            scale: scale,
                          ),
                          const SizedBox(height: 20),
                        ] else
                          const SizedBox(height: 26),
                        if (widget.previewImagePath.trim().isNotEmpty) ...[
                          _RecognizedTextRegionPreview(
                            imagePath: widget.previewImagePath,
                            regions: widget.recognizedTextRegions,
                            previewText: text,
                            scale: scale,
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
                        _PreviewMedicationTable(
                          medicationScheduleList: widget.medicationScheduleList,
                          previewText: text,
                          userSetting: widget.userSetting,
                          scrollController: _tableScrollController,
                          onEditRequested: _showMedicationEditor,
                          verifiedScheduleIndexes:
                              widget.verifiedScheduleIndexes,
                        ),
                        if (widget.isMedicationLookupReview &&
                            widget.verifiedScheduleIndexes.isNotEmpty &&
                            widget.onVerifiedOnlyContinueRequested != null) ...[
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              key: const Key(
                                'continue-with-verified-medications',
                              ),
                              onPressed: _confirmVerifiedOnlyContinue,
                              child: Text(text.continueWithVerifiedOnly),
                            ),
                          ),
                        ],
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

  // 함수이름: _showMedicationEditor
  // 함수역할:
  // - 선택한 표 셀의 OCR 인식 결과를 수정하는 대화상자를 연다.
  // - 누른 셀에 해당하는 입력란으로 바로 이동해 중복 검토 화면 없이 수정하게 한다.
  // - 수정이 완료되면 목록의 실제 인덱스와 변경값을 상위 상태로 전달한다.
  // 매개변수:
  // - scheduleIndex: 전체 OCR 결과 목록에서 수정할 항목의 인덱스
  // - medicationSchedule: 대화상자에 표시할 현재 OCR 인식 결과
  // - initialField: 처음 입력 초점을 둘 표 열
  // 반환값:
  // - 없음
  Future<void> _showMedicationEditor(
    int scheduleIndex,
    MedicationSchedule medicationSchedule,
    _MedicationScheduleEditField initialField,
  ) async {
    final updatedSchedule = await showDialog<MedicationSchedule>(
      context: context,
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

  // 함수명: _showMedicationCreator
  // 함수역할:
  // - OCR에서 빠진 약을 기존 수정 대화상자와 같은 형식으로 직접 입력하게 한다.
  // - 첫 처방 항목의 날짜와 복용 기간을 기본값으로 사용하되 저장 전 모두 수정할 수 있다.
  Future<void> _showMedicationCreator() async {
    final referenceSchedule = widget.medicationScheduleList.isEmpty
        ? null
        : widget.medicationScheduleList.first;
    final defaultSchedule = MedicationSchedule(
      medicationName: '',
      prescriptionDate: referenceSchedule?.prescriptionDate ?? DateTime.now(),
      prescriptionBatchId: referenceSchedule?.prescriptionBatchId ?? '',
      dosage: '1',
      intakeTime: '1',
      medicationTime: referenceSchedule?.medicationTime ?? 1,
      scheduleSlotKeys: const [defaultMedicationScheduleSlotKey],
      nameConfidence: 1,
      nameCorrectionSource: 'manual_add',
    );
    final addedSchedule = await showDialog<MedicationSchedule>(
      context: context,
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

  // 함수명: _confirmVerifiedOnlyContinue
  // 함수역할:
  // - 미확인 약이 결과에서 제외된다는 사실을 사용자가 확인한 경우에만 다음 단계로 진행한다.
  Future<void> _confirmVerifiedOnlyContinue() async {
    final text = _PreviewText(widget.userSetting.language);
    final unverifiedCount =
        widget.medicationScheduleList.length -
        widget.verifiedScheduleIndexes.length;
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.continueWithVerifiedTitle),
        content: Text(text.continueWithVerifiedWarning(unverifiedCount)),
        actions: [
          TextButton(
            key: const Key('cancel-verified-only-continue'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(text.cancel),
          ),
          FilledButton(
            key: const Key('confirm-verified-only-continue'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(text.continueLabel),
          ),
        ],
      ),
    );
    if (shouldContinue == true && mounted) {
      widget.onVerifiedOnlyContinueRequested?.call();
    }
  }

  // 함수명: _showTableScrollHint
  // 역할:
  // - OCR 표가 처음 표시될 때 가로로 더 볼 수 있다는 안내를 잠시 노출한다.
  void _showTableScrollHint() {
    if (!mounted || widget.medicationScheduleList.isEmpty) {
      return;
    }
    final text = _PreviewText(widget.userSetting.language);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        key: const Key('ocr-table-scroll-hint'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(Icons.swipe_left_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(text.tableScrollHint)),
          ],
        ),
      ),
    );
  }

  // 함수명: _requestAnalysis
  // 역할:
  // - 현재 표에서 확인한 OCR 값을 그대로 사용해 상세 분석을 시작한다.
  // - 빠른 연속 입력으로 같은 분석이 중복 요청되지 않게 막는다.
  void _requestAnalysis() {
    if (_isAnalysisRequested) {
      return;
    }
    setState(() => _isAnalysisRequested = true);
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    widget.onAnalysisRequested();
  }
}

// 클래스명: _MedicationLookupReviewBanner
// 역할: API에서 확인하지 못한 약을 수정하고 다시 조회해야 한다는 안내를 강조한다.
class _MedicationLookupReviewBanner extends StatelessWidget {
  final String message;
  final double scale;

  const _MedicationLookupReviewBanner({
    required this.message,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('medication-lookup-review-banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E5),
        border: Border.all(color: const Color(0xFFF0CC69)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: const Color(0xFF9A6700),
            size: 21 * scale,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 12 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
