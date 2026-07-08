import 'package:flutter/material.dart';

import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_view_model.dart';

// 파일명: prescription_analysis_progress_ui_boundary.dart
// 역할: 처방전 분석 중 현재 처리 단계를 보여주는 화면을 구성한다.

// 클래스명: PrescriptionAnalysisProgressUI
// 역할: OCR 인식, 약물 정보 분석, 복약 일정 생성 중 어느 단계인지 사용자에게 안내한다.
// 주요 책임:
// - ViewModel의 분석 단계 상태를 시각적 진행 상태로 표현한다.
// - 분석 중 사용자가 뒤로갈 수 있는 동선을 제공한다.
class PrescriptionAnalysisProgressUI extends StatelessWidget {
  final AnalysisProgressStep activeStep;
  final UserSetting userSetting;
  final VoidCallback onBackRequested;

  const PrescriptionAnalysisProgressUI({
    super.key,
    required this.activeStep,
    required this.userSetting,
    required this.onBackRequested,
  });

  @override
  Widget build(BuildContext context) {
    final text = _ProgressText(userSetting.language);
    final scale = userSetting.contentTextScale;

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
              Padding(
                padding: const EdgeInsets.fromLTRB(31, 37, 31, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: text.back,
                    onPressed: onBackRequested,
                    icon: const Icon(
                      Icons.chevron_left,
                      color: MedBuddyColors.textMuted,
                      size: 31,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Container(
                    width: 328,
                    padding: const EdgeInsets.fromLTRB(42, 45, 42, 45),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: MedBuddyShadows.card,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          text.title,
                          style: TextStyle(
                            color: MedBuddyColors.textStrong,
                            fontSize: 28 * scale,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 42),
                        const SizedBox(
                          width: 112,
                          height: 112,
                          child: CircularProgressIndicator(
                            color: MedBuddyColors.primary,
                            backgroundColor: Color(0xFFA4F4CF),
                            strokeWidth: 8,
                          ),
                        ),
                        const SizedBox(height: 42),
                        _ProgressStepLabel(
                          label: text.recognizing,
                          active: activeStep ==
                              AnalysisProgressStep.prescriptionRecognition,
                          scale: scale,
                        ),
                        const SizedBox(height: 14),
                        _ProgressStepLabel(
                          label: text.analyzingMedication,
                          active: activeStep ==
                              AnalysisProgressStep.medicationAnalysis,
                          scale: scale,
                        ),
                        const SizedBox(height: 14),
                        _ProgressStepLabel(
                          label: text.generatingSchedule,
                          active: activeStep ==
                              AnalysisProgressStep.scheduleGeneration,
                          scale: scale,
                        ),
                        const SizedBox(height: 30),
                        ClipRRect(
                          borderRadius: MedBuddyRadii.pill,
                          child: LinearProgressIndicator(
                            minHeight: 12,
                            value: _progressValue,
                            color: MedBuddyColors.primary,
                            backgroundColor: const Color(0xFFE5E7EB),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          text.wait,
                          style: TextStyle(
                            color: MedBuddyColors.textMuted,
                            fontSize: 14 * scale,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
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

  double get _progressValue {
    return switch (activeStep) {
      AnalysisProgressStep.prescriptionRecognition => 0.33,
      AnalysisProgressStep.medicationAnalysis => 0.66,
      AnalysisProgressStep.scheduleGeneration => 0.92,
    };
  }
}

class _ProgressStepLabel extends StatelessWidget {
  final String label;
  final bool active;
  final double scale;

  const _ProgressStepLabel({
    required this.label,
    required this.active,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: active ? MedBuddyColors.primary : MedBuddyColors.textLight,
        fontSize: 16 * scale,
        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}

class _ProgressText {
  final String language;

  const _ProgressText(this.language);

  bool get isEnglish => language == 'en';

  String get back => isEnglish ? 'Back' : '뒤로가기';
  String get title => isEnglish ? 'Analyzing' : '분석중';
  String get recognizing =>
      isEnglish ? 'Recognizing prescription...' : '처방전 인식 중...';
  String get analyzingMedication =>
      isEnglish ? 'Analyzing medication info...' : '약물 정보 분석 중...';
  String get generatingSchedule =>
      isEnglish ? 'Creating medication schedule...' : '복용 일정 생성 중...';
  String get wait => isEnglish ? 'Please wait a moment' : '잠시만 기다려주세요';
}
