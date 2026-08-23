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

// 파일명: prescription_analysis_preview_ui_boundary.dart
// 역할: UC-1 OCR 결과를 사용자에게 먼저 확인시키는 분석 예비 화면을 구성한다.

// 클래스명: PrescriptionAnalysisPreviewUI
// 역할: 처방전에서 인식된 약별 복약 정보를 하나의 수정 가능한 표로 보여준다.
// 주요 책임:
// - OCR 결과의 모든 항목을 가로 스크롤 표로 비교하게 한다.
// - 사용자가 표의 각 셀을 눌러 잘못 인식된 값을 바로 수정하게 한다.
// - 별도의 중복 검토 화면 없이 현재 표의 값으로 실제 약품 분석을 시작한다.
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
        label: hasReviewRequired
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
                        if (recognitionNotice.isNotEmpty) ...[
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
                        _PreviewMedicationTable(
                          medicationScheduleList: widget.medicationScheduleList,
                          previewText: text,
                          userSetting: widget.userSetting,
                          scrollController: _tableScrollController,
                          onEditRequested: _showMedicationEditor,
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
