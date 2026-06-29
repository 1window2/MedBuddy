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
  final UserSetting userSetting;
  final VoidCallback onBackRequested;
  final VoidCallback onAnalysisRequested;

  const PrescriptionAnalysisPreviewUI({
    super.key,
    required this.medicationScheduleList,
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
                        const SizedBox(height: 26),
                        SizedBox(
                          height: 206,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: pageCount,
                            onPageChanged: (index) {
                              setState(() => _currentPageIndex = index);
                            },
                            itemBuilder: (context, pageIndex) {
                              return _PreviewMedicationPage(
                                medicationScheduleList: _pageItems(pageIndex),
                                emptyText: text.noInformation,
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
  final String emptyText;
  final UserSetting userSetting;

  const _PreviewMedicationPage({
    required this.medicationScheduleList,
    required this.emptyText,
    required this.userSetting,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int index = 0; index < medicationScheduleList.length; index++) ...[
          _PreviewMedicationRow(
            schedule: medicationScheduleList[index],
            emptyText: emptyText,
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
  final String emptyText;
  final UserSetting userSetting;

  const _PreviewMedicationRow({
    required this.schedule,
    required this.emptyText,
    required this.userSetting,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;
    final frequency = schedule.intakeTime.trim().isEmpty
        ? emptyText
        : schedule.intakeTime.trim();

    return Row(
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
