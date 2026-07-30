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
// 역할: 처방전에서 인식된 약 목록과 복약 횟수를 페이지 단위로 보여준다.
// 주요 책임:
// - OCR 결과가 여러 개인 경우 PageView로 나누어 보여준다.
// - 신뢰도가 낮거나 잘못 인식된 OCR 결과를 사용자가 직접 수정하게 한다.
// - 사용자가 인식 결과를 확인한 뒤 실제 약품 상세 분석을 시작하게 한다.
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
  static const int _itemsPerPage = 4;

  final PageController _pageController = PageController();
  int _currentPageIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _PreviewText(widget.userSetting.language);
    final scale = widget.userSetting.contentTextScale;
    final pageCount = _pageCount;
    final recognitionNotice = widget.recognitionNotice.trim();
    final hasNameCorrection = widget.medicationScheduleList.any(
      (schedule) => schedule.hasNameCorrection,
    );
    final systemTextScale = MediaQuery.textScalerOf(context).scale(18) / 18;
    final effectiveTextScale = scale * systemTextScale;
    final medicationPageHeight = _resolveMedicationPageHeight(
      hasNameCorrection: hasNameCorrection,
      effectiveTextScale: effectiveTextScale,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _AnalysisBottomBar(
        label: text.analyze,
        scale: scale,
        onPressed: widget.onAnalysisRequested,
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
                        SizedBox(
                          height: medicationPageHeight,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: pageCount,
                            onPageChanged: (index) {
                              setState(() => _currentPageIndex = index);
                            },
                            itemBuilder: (context, pageIndex) {
                              return _PreviewMedicationPage(
                                medicationScheduleList: _pageItems(pageIndex),
                                firstScheduleIndex: pageIndex * _itemsPerPage,
                                previewText: text,
                                userSetting: widget.userSetting,
                                onEditRequested: _showMedicationEditor,
                              );
                            },
                          ),
                        ),
                        if (_remainingCount > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            text.moreCount(_remainingCount),
                            style: TextStyle(
                              color: MedBuddyColors.textLight,
                              fontSize: 13 * scale,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (int index = 0; index < pageCount; index++)
                              _PreviewDot(
                                active: index == _currentPageIndex,
                                onTap: () => _animateToPage(index),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
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

  int get _pageCount {
    final count = (widget.medicationScheduleList.length / _itemsPerPage).ceil();
    return count <= 0 ? 1 : count;
  }

  int get _remainingCount {
    final shownCount = (_currentPageIndex + 1) * _itemsPerPage;
    final remainingCount = widget.medicationScheduleList.length - shownCount;
    return remainingCount > 0 ? remainingCount : 0;
  }

  List<MedicationSchedule> _pageItems(int pageIndex) {
    final start = pageIndex * _itemsPerPage;
    final end = (start + _itemsPerPage).clamp(
      0,
      widget.medicationScheduleList.length,
    );
    if (start >= widget.medicationScheduleList.length) {
      return const [];
    }
    return widget.medicationScheduleList.sublist(start, end);
  }

  // 함수이름: _resolveMedicationPageHeight
  // 함수역할:
  // - 수정 버튼, 신뢰도 배지, OCR 원문을 포함한 최대 네 행의 필요 높이를 계산한다.
  // - 글자 크기가 커진 경우에도 PageView 내부가 넘치지 않도록 여유 높이를 반영한다.
  // 매개변수:
  // - hasNameCorrection: OCR 원문을 추가로 표시할 항목이 있는지 여부
  // - effectiveTextScale: 앱 설정과 시스템 접근성 설정을 합친 글자 배율
  // 반환값:
  // - OCR 결과 PageView에 적용할 높이
  double _resolveMedicationPageHeight({
    required bool hasNameCorrection,
    required double effectiveTextScale,
  }) {
    final medicationCount = widget.medicationScheduleList.length;
    final visibleRowCount = medicationCount <= 0
        ? 1
        : medicationCount > _itemsPerPage
        ? _itemsPerPage
        : medicationCount;
    final rowHeight = hasNameCorrection ? 52.0 : 44.0;
    final dividerHeight = (visibleRowCount - 1) * 22.0;
    final requiredHeight = visibleRowCount * rowHeight + dividerHeight;
    final minimumHeight = hasNameCorrection ? 238.0 : 206.0;
    final baseHeight = requiredHeight > minimumHeight
        ? requiredHeight
        : minimumHeight;
    final appliedScale = effectiveTextScale > 1 ? effectiveTextScale : 1.0;
    return baseHeight * appliedScale + 24;
  }

  void _animateToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  // 함수이름: _showMedicationEditor
  // 함수역할:
  // - 선택한 OCR 인식 결과를 수정하는 대화상자를 연다.
  // - 수정이 완료되면 목록의 실제 인덱스와 변경값을 상위 상태로 전달한다.
  // 매개변수:
  // - scheduleIndex: 전체 OCR 결과 목록에서 수정할 항목의 인덱스
  // - medicationSchedule: 대화상자에 표시할 현재 OCR 인식 결과
  // 반환값:
  // - 없음
  Future<void> _showMedicationEditor(
    int scheduleIndex,
    MedicationSchedule medicationSchedule,
  ) async {
    final updatedSchedule = await showDialog<MedicationSchedule>(
      context: context,
      builder: (context) => _MedicationScheduleEditDialog(
        medicationSchedule: medicationSchedule,
        previewText: _PreviewText(widget.userSetting.language),
        userSetting: widget.userSetting,
      ),
    );
    if (!mounted || updatedSchedule == null) {
      return;
    }

    widget.onMedicationScheduleChanged(scheduleIndex, updatedSchedule);
  }
}
