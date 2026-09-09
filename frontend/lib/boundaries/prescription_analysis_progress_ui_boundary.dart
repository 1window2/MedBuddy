import 'package:flutter/material.dart';

import '../entities/prescription_flow_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: prescription_analysis_progress_ui_boundary.dart
// 역할: OCR 및 약물 분석의 현재 진행 단계를 제공한다.

// 클래스명: PrescriptionAnalysisProgressUI
// 역할: OCR 인식과 약품 분석의 활성 단계를 담당한다.
// 주요 책임:
// - ViewModel의 분석 단계 상태를 시각적 진행 상태로 표현한다.
// - 분석 중 사용자가 뒤로갈 수 있는 동선을 제공한다.
// 속성:
// - activeStep (AnalysisProgressStep): 현재 진행 중이거나 실패한 처방 분석 단계.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - onBackRequested (VoidCallback): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
class PrescriptionAnalysisProgressUI extends StatelessWidget {
  final AnalysisProgressStep activeStep;
  final UserSetting userSetting;
  final VoidCallback onBackRequested;

  // 함수이름: PrescriptionAnalysisProgressUI
  // 함수역할: OCR 인식과 약품 분석의 활성 단계에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - activeStep (AnalysisProgressStep): 현재 진행 중이거나 실패한 처방 분석 단계.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - onBackRequested (VoidCallback): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
  // 반환값: 입력 설정이 반영된 PrescriptionAnalysisProgressUI 인스턴스.
  const PrescriptionAnalysisProgressUI({
    super.key,
    required this.activeStep,
    required this.userSetting,
    required this.onBackRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 OCR 인식과 약품 분석의 활성 단계 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: OCR 인식과 약품 분석의 활성 단계에 쓰는 위젯 트리.
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
              colors: [MedBuddyColors.analysisBackground, Colors.white],
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
                child: LayoutBuilder(
                  // 함수이름: build.builder callback
                  // 함수역할: OCR 인식과 약품 분석의 활성 단계에 EdgeInsets.symmetric, EdgeInsets.fromLTRB, SizedBox을 적용해 현재 배치를 구성한다.
                  // 매개변수:
                  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
                  // - constraints (BoxConstraints): 부모 레이아웃이 허용한 너비·높이 범위.
                  // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                  builder: (context, constraints) {
                    final minimumContentHeight = constraints.maxHeight > 48
                        ? constraints.maxHeight - 48
                        : 0.0;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: minimumContentHeight,
                        ),
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
                                    backgroundColor:
                                        MedBuddyColors.successBorder,
                                    strokeWidth: 8,
                                  ),
                                ),
                                const SizedBox(height: 42),
                                _ProgressStepLabel(
                                  label: text.recognizing,
                                  active:
                                      activeStep ==
                                      AnalysisProgressStep
                                          .prescriptionRecognition,
                                  scale: scale,
                                ),
                                const SizedBox(height: 14),
                                _ProgressStepLabel(
                                  label: text.analyzingMedication,
                                  active:
                                      activeStep ==
                                      AnalysisProgressStep.medicationAnalysis,
                                  scale: scale,
                                ),
                                const SizedBox(height: 30),
                                ClipRRect(
                                  borderRadius: MedBuddyRadii.pill,
                                  child: LinearProgressIndicator(
                                    minHeight: 12,
                                    value: _progressValue,
                                    color: MedBuddyColors.primary,
                                    backgroundColor: MedBuddyColors.divider,
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
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 함수이름: _progressValue
  // 함수역할: 인식 단계는 0.5, 약품 분석 단계는 0.85의 안내 진행률로 표시한다.
  // 매개변수:
  // - 없음.
  // 반환값: double: 현재 분석 단계의 안내용 진행률.
  double get _progressValue {
    return switch (activeStep) {
      AnalysisProgressStep.prescriptionRecognition => 0.5,
      AnalysisProgressStep.medicationAnalysis => 0.85,
    };
  }
}

// 클래스명: _ProgressStepLabel
// 역할: 분석 단계 이름과 활성 강조를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 분석 단계 이름과 활성 강조 위젯을 구성한다.
// 속성:
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - active (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _ProgressStepLabel extends StatelessWidget {
  final String label;
  final bool active;
  final double scale;

  // 함수이름: _ProgressStepLabel
  // 함수역할: 분석 단계 이름과 활성 강조에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - active (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _ProgressStepLabel 인스턴스.
  const _ProgressStepLabel({
    required this.label,
    required this.active,
    required this.scale,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 분석 단계 이름과 활성 강조 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 분석 단계 이름과 활성 강조에 쓰는 위젯 트리.
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

// 클래스명: _ProgressText
// 역할: OCR 및 약물 분석의 현재 진행 단계에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - OCR 및 약물 분석의 현재 진행 단계에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _ProgressText {
  final String language;

  // 함수이름: _ProgressText
  // 함수역할: OCR 및 약물 분석의 현재 진행 단계에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _ProgressText 인스턴스.
  const _ProgressText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드가 en과 정확히 일치하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language == 'en';

  // 함수이름: back
  // 함수역할: 현재 언어와 입력값에 맞춰 "뒤로가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get back => isEnglish ? 'Back' : '뒤로가기';
  // 함수이름: title
  // 함수역할: 현재 언어와 입력값에 맞춰 "분석중" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get title => isEnglish ? 'Analyzing' : '분석중';
  // 함수이름: recognizing
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전 인식 중..." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get recognizing =>
      isEnglish ? 'Recognizing prescription...' : '처방전 인식 중...';
  // 함수이름: analyzingMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "약물 정보 분석 중..." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get analyzingMedication =>
      isEnglish ? 'Analyzing medication info...' : '약물 정보 분석 중...';
  // 함수이름: wait
  // 함수역할: 현재 언어와 입력값에 맞춰 "잠시만 기다려주세요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get wait => isEnglish ? 'Please wait a moment' : '잠시만 기다려주세요';
}
