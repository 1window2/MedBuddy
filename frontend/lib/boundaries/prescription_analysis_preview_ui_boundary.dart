import 'package:flutter/material.dart';

import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: prescription_analysis_preview_ui_boundary.dart
// 역할: UC-1 OCR 결과를 사용자에게 먼저 확인시키는 분석 예비 화면을 구성한다.

// 클래스명: PrescriptionAnalysisPreviewUI
// 역할: 처방전에서 인식된 약 목록과 복약 횟수를 페이지 단위로 보여준다.
// 주요 책임:
// - OCR 결과가 여러 개인 경우 PageView로 나누어 보여준다.
// - 사용자가 인식 결과를 확인한 뒤 실제 약품 상세 분석을 시작하게 한다.
// - 분석 전에 뒤로가기를 통해 촬영 단계로 돌아갈 수 있게 한다.
class PrescriptionAnalysisPreviewUI extends StatefulWidget {
  final List<MedicationSchedule> medicationScheduleList;
  final String recognitionNotice;
  final UserSetting userSetting;
  final VoidCallback onBackRequested;
  final VoidCallback onAnalysisRequested;

  const PrescriptionAnalysisPreviewUI({
    super.key,
    required this.medicationScheduleList,
    this.recognitionNotice = '',
    required this.userSetting,
    required this.onBackRequested,
    required this.onAnalysisRequested,
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFEFFFF8), Colors.white],
            ),
          ),
          child: Column(
            children: [
              _TopBackButton(
                tooltip: text.back,
                onBackRequested: widget.onBackRequested,
              ),
              Expanded(
                child: Center(
                  child: Container(
                    width: 328,
                    padding: const EdgeInsets.fromLTRB(31, 32, 31, 30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFD1D5DC),
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
                        SizedBox(
                          height: hasNameCorrection ? 238 : 206,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: pageCount,
                            onPageChanged: (index) {
                              setState(() => _currentPageIndex = index);
                            },
                            itemBuilder: (context, pageIndex) {
                              return _PreviewMedicationPage(
                                medicationScheduleList: _pageItems(pageIndex),
                                previewText: text,
                                userSetting: widget.userSetting,
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
                        const SizedBox(height: 36),
                        SizedBox(
                          width: double.infinity,
                          height: 64,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: MedBuddyColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: MedBuddyRadii.card,
                              ),
                              textStyle: TextStyle(
                                fontSize: 19 * scale,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                            ),
                            onPressed: widget.onAnalysisRequested,
                            child: Text(text.analyze),
                          ),
                        ),
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

  void _animateToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }
}

class _RecognitionNoticeBanner extends StatelessWidget {
  final String message;
  final double scale;

  const _RecognitionNoticeBanner({
    required this.message,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF5D565)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: const Color(0xFFB7791F),
            size: 16 * scale,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: const Color(0xFF8A5A12),
                fontSize: 12 * scale,
                fontWeight: FontWeight.w700,
                height: 1.25,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBackButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onBackRequested;

  const _TopBackButton({
    required this.tooltip,
    required this.onBackRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(31, 37, 31, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onBackRequested,
          icon: const Icon(
            Icons.chevron_left,
            color: MedBuddyColors.textMuted,
            size: 31,
          ),
        ),
      ),
    );
  }
}

class _PreviewMedicationPage extends StatelessWidget {
  final List<MedicationSchedule> medicationScheduleList;
  final _PreviewText previewText;
  final UserSetting userSetting;

  const _PreviewMedicationPage({
    required this.medicationScheduleList,
    required this.previewText,
    required this.userSetting,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int index = 0; index < medicationScheduleList.length; index++) ...[
          _PreviewMedicationRow(
            schedule: medicationScheduleList[index],
            previewText: previewText,
            userSetting: userSetting,
          ),
          if (index != medicationScheduleList.length - 1)
            const Divider(height: 22),
        ],
      ],
    );
  }
}

class _PreviewMedicationRow extends StatelessWidget {
  final MedicationSchedule schedule;
  final _PreviewText previewText;
  final UserSetting userSetting;

  const _PreviewMedicationRow({
    required this.schedule,
    required this.previewText,
    required this.userSetting,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;
    final frequency = schedule.intakeTime.trim().isEmpty
        ? previewText.noInformation
        : schedule.intakeTime.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      schedule.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if (schedule.hasNameCorrection) ...[
                    const SizedBox(width: 6),
                    _CorrectionBadge(
                      label: previewText.corrected,
                      scale: scale,
                    ),
                  ],
                ],
              ),
              if (schedule.hasNameCorrection) ...[
                const SizedBox(height: 3),
                Text(
                  previewText.correctedFrom(schedule.rawMedicationName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MedBuddyColors.textLight,
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        Text(
          frequency,
          style: TextStyle(
            color: MedBuddyColors.textMuted,
            fontSize: 18 * scale,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _CorrectionBadge extends StatelessWidget {
  final String label;
  final double scale;

  const _CorrectionBadge({
    required this.label,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F7F1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: MedBuddyColors.primaryDark,
          fontSize: 10 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _PreviewDot extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _PreviewDot({
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: active ? MedBuddyColors.primary : const Color(0xFFD1D5DC),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _PreviewText {
  final String language;

  const _PreviewText(this.language);

  bool get isEnglish => language == 'en';

  String get back => isEnglish ? 'Back' : '뒤로가기';
  String get analyze => isEnglish ? 'Analyze' : '분석하기';
  String get noInformation => isEnglish ? 'No info' : '정보 없음';
  String get corrected => isEnglish ? 'Corrected' : '보정';

  String correctedFrom(String rawName) {
    return isEnglish ? 'OCR: $rawName' : 'OCR 원문: $rawName';
  }

  String title(DateTime date) {
    if (isEnglish) {
      return '${date.month}/${date.day} Prescription';
    }

    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[date.weekday - 1];
    return '${date.month}/${date.day} ($weekday) 처방 내역';
  }

  String moreCount(int count) {
    return isEnglish ? '+$count more' : '+$count개 더 있음';
  }
}
