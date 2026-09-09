import 'package:flutter/material.dart';

import '../entities/analyzed_medication_entity.dart';
import '../entities/prescription_flow_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: prescription_analysis_status_ui_boundary.dart
// 역할: 처방 분석 성공 요약과 실패 단계별 복구 동작을 제공한다.

// Class Name: PrescriptionAnalysisSuccessUI
// Role: Represents analyzed-medication count, maximum treatment days, and results navigation.
// Responsibilities:
// - Summarizes the analyzed medication count and longest treatment duration.
// - Provides navigation to the result list.
// Attributes:
// - analyzedMedicationList (List<AnalyzedMedication>): Prescription analysis results containing medication details and schedules.
// - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
// - onResultRequested (VoidCallback): Callback opening completed analysis results.
class PrescriptionAnalysisSuccessUI extends StatelessWidget {
  final List<AnalyzedMedication> analyzedMedicationList;
  final UserSetting userSetting;
  final VoidCallback onResultRequested;

  // 함수이름: PrescriptionAnalysisSuccessUI
  // 함수역할: 분석 약품 수·최대 복용일 요약과 결과 진입에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - analyzedMedicationList (List<AnalyzedMedication>): 약 상세와 일정을 함께 가진 처방 분석 결과 목록.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - onResultRequested (VoidCallback): 완료된 분석 결과 목록을 여는 콜백.
  // 반환값: 입력 설정이 반영된 PrescriptionAnalysisSuccessUI 인스턴스.
  const PrescriptionAnalysisSuccessUI({
    super.key,
    required this.analyzedMedicationList,
    required this.userSetting,
    required this.onResultRequested,
  });

  // Function Name: build
  // Description: Renders analyzed-medication count, maximum treatment days, and results navigation from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for analyzed-medication count, maximum treatment days, and results navigation.
  @override
  Widget build(BuildContext context) {
    final text = _StatusText(userSetting.language);
    final scale = userSetting.contentTextScale;
    final maxMedicationDays = _readMaxMedicationDays();

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
          child: Center(
            child: Container(
              width: 328,
              padding: const EdgeInsets.fromLTRB(42, 34, 42, 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: MedBuddyShadows.card,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text.successTitle,
                    style: TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 28 * scale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 36),
                  Container(
                    width: 168,
                    height: 168,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0FDF4),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 98,
                        height: 98,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00B875),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_outline,
                          color: Colors.white,
                          size: 62,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 34),
                  Text(
                    text.successMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 18 * scale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 13),
                  Text(
                    text.successDescription,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MedBuddyColors.textLight,
                      fontSize: 14 * scale,
                      height: 1.55,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: _SuccessMetric(
                          value: '${analyzedMedicationList.length}',
                          label: text.recognizedMedication,
                          scale: scale,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _SuccessMetric(
                          value: maxMedicationDays <= 0
                              ? '-'
                              : text.days(maxMedicationDays),
                          label: text.medicationPeriod,
                          scale: scale,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 63,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: MedBuddyColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: MedBuddyRadii.card,
                        ),
                        textStyle: TextStyle(
                          fontSize: 18 * scale,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      onPressed: onResultRequested,
                      child: Text(text.checkResult),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 함수이름: _readMaxMedicationDays
  // 함수역할: 분석된 약 중 가장 긴 복용일수를 찾고 목록이 비면 0을 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값: int: 분석 항목 중 가장 긴 복용 기간; 항목이 없으면 0.
  int _readMaxMedicationDays() {
    // 함수이름: _readMaxMedicationDays.fold callback
    // 함수역할: 분석 약품 수·최대 복용일 요약과 결과 진입의 누적값을 `nextValue > maxValue ? nextValue : maxValue` 규칙으로 계산한다.
    // 매개변수:
    // - maxValue (콜백 계약에서 추론): 누적 합계 또는 지금까지의 최대값.
    // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
    // 반환값: 컬렉션 연산에 전달할 누적값.
    return analyzedMedicationList.fold<int>(0, (maxValue, item) {
      final nextValue = item.schedule.medicationTime;
      return nextValue > maxValue ? nextValue : maxValue;
    });
  }
}

// 클래스명: PrescriptionAnalysisFailureUI
// 역할: 실패 단계에 맞춘 재분석·재촬영·재선택 명령을 담당한다.
// 주요 책임:
// - 실패 메시지를 화면에 표시한다.
// - 실패 단계에 맞는 재분석 또는 이미지 재선택 복구 동작을 제공한다.
// 속성:
// - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - failureStep (AnalysisProgressStep): 현재 진행 중이거나 실패한 처방 분석 단계.
// - onAnalysisRetryRequested (VoidCallback?): 검토한 복약 정보의 분석을 시작하거나 다시 요청할 콜백.
class PrescriptionAnalysisFailureUI extends StatelessWidget {
  final String message;
  final UserSetting userSetting;
  final AnalysisProgressStep failureStep;
  final VoidCallback? onAnalysisRetryRequested;
  final VoidCallback? onOcrReviewRequested;
  final VoidCallback onCameraRetryRequested;
  final VoidCallback onGalleryRetryRequested;
  final VoidCallback onHomeRequested;

  // 함수이름: PrescriptionAnalysisFailureUI
  // 함수역할: 실패 단계에 맞춘 재분석·재촬영·재선택 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - failureStep (AnalysisProgressStep): 현재 진행 중이거나 실패한 처방 분석 단계.
  // - onAnalysisRetryRequested (VoidCallback?): 검토한 복약 정보의 분석을 시작하거나 다시 요청할 콜백.
  // - onOcrReviewRequested (VoidCallback?): 인식된 약품 표 검토 단계로 돌아갈 콜백.
  // - onCameraRetryRequested (VoidCallback): 가이드 카메라를 통한 처방전 재촬영·입력을 요청할 콜백.
  // - onGalleryRetryRequested (VoidCallback): 갤러리에서 처방전 사진을 선택할 콜백.
  // - onHomeRequested (VoidCallback): 홈 화면으로 이동할 콜백.
  // 반환값: 입력 설정이 반영된 PrescriptionAnalysisFailureUI 인스턴스.
  const PrescriptionAnalysisFailureUI({
    super.key,
    required this.message,
    required this.userSetting,
    required this.failureStep,
    this.onAnalysisRetryRequested,
    this.onOcrReviewRequested,
    required this.onCameraRetryRequested,
    required this.onGalleryRetryRequested,
    required this.onHomeRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 실패 단계에 맞춘 재분석·재촬영·재선택 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 실패 단계에 맞춘 재분석·재촬영·재선택 명령에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final text = _StatusText(userSetting.language);
    final scale = userSetting.contentTextScale;
    final isMedicationAnalysisFailure =
        failureStep != AnalysisProgressStep.prescriptionRecognition;
    final canRetryAnalysis = onAnalysisRetryRequested != null;

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
              colors: [Color(0xFFFFF1F2), Colors.white],
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Center(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: MedBuddyShadows.card,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      text.failureTitle,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 28 * scale,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF1F2D),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cancel_outlined,
                        color: Colors.white,
                        size: 56,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      text.failureMessage(isMedicationAnalysisFailure),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message.trim().isEmpty
                          ? text.failureDescription(isMedicationAnalysisFailure)
                          : message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: MedBuddyColors.textLight,
                        fontSize: 14 * scale,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    if (!isMedicationAnalysisFailure) ...[
                      const SizedBox(height: 28),
                      _FailureReasonPanel(text: text, scale: scale),
                    ],
                    const SizedBox(height: 28),
                    if (onAnalysisRetryRequested case final retryCallback?) ...[
                      _buildActionButton(
                        key: const Key('prescription-analysis-retry-button'),
                        isPrimary: true,
                        onPressed: retryCallback,
                        icon: Icons.refresh,
                        label: text.analysisRetry,
                        scale: scale,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (onOcrReviewRequested case final reviewCallback?) ...[
                      _buildActionButton(
                        key: const Key('prescription-ocr-review-button'),
                        isPrimary: false,
                        onPressed: reviewCallback,
                        icon: Icons.fact_check_outlined,
                        label: text.ocrReview,
                        scale: scale,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildActionButton(
                      key: const Key('prescription-camera-retry-button'),
                      isPrimary: !canRetryAnalysis,
                      onPressed: onCameraRetryRequested,
                      icon: Icons.photo_camera_outlined,
                      label: text.cameraRetry,
                      scale: scale,
                    ),
                    const SizedBox(height: 12),
                    _buildActionButton(
                      key: const Key('prescription-gallery-retry-button'),
                      isPrimary: false,
                      onPressed: onGalleryRetryRequested,
                      icon: Icons.photo_library_outlined,
                      label: text.galleryRetry,
                      scale: scale,
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: double.infinity,
                        minHeight: 56,
                      ),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 14,
                          ),
                          foregroundColor: MedBuddyColors.textStrong,
                          side: const BorderSide(color: MedBuddyColors.outline),
                          shape: RoundedRectangleBorder(
                            borderRadius: MedBuddyRadii.card,
                          ),
                          textStyle: TextStyle(
                            fontSize: 17 * scale,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        onPressed: onHomeRequested,
                        child: Text(text.home, textAlign: TextAlign.center),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 함수이름: _buildActionButton
  // 함수역할: 아이콘 간격과 좌우 여백을 줄이고, 매우 큰 글씨에서는 높이를 늘려 복구 명령을 모두 표시한다.
  // 매개변수:
  // - key (Key): 복구 버튼 식별 키.
  // - isPrimary (bool): 주요 명령 강조 여부.
  // - onPressed (VoidCallback): 선택한 복구 동작.
  // - icon (IconData): 명령을 나타내는 아이콘.
  // - label (String): 생략 없이 표시할 명령 이름.
  // - scale (double): 사용자 글씨 배율.
  // 반환값: 최소 터치 높이를 보장하는 복구 버튼.
  Widget _buildActionButton({
    required Key key,
    required bool isPrimary,
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required double scale,
  }) {
    final shape = RoundedRectangleBorder(borderRadius: MedBuddyRadii.card);
    final textStyle = TextStyle(
      fontSize: 17 * scale,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 6),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: double.infinity,
        minHeight: 56,
      ),
      child: isPrimary
          ? FilledButton(
              key: key,
              style: FilledButton.styleFrom(
                backgroundColor: MedBuddyColors.primary,
                foregroundColor: Colors.white,
                shape: shape,
                textStyle: textStyle,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 14,
                ),
              ),
              onPressed: onPressed,
              child: content,
            )
          : OutlinedButton(
              key: key,
              style: OutlinedButton.styleFrom(
                foregroundColor: MedBuddyColors.primaryDark,
                side: const BorderSide(
                  color: MedBuddyColors.primary,
                  width: 1.5,
                ),
                shape: shape,
                textStyle: textStyle,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 14,
                ),
              ),
              onPressed: onPressed,
              child: content,
            ),
    );
  }
}

// Class Name: _SuccessMetric
// Role: Represents a numeric metric and label in the analysis-success summary.
// Responsibilities:
// - Composes a numeric metric and label in the analysis-success summary using the display values and actions supplied by its parent.
// Attributes:
// - value (String): Input to validate, normalize, display, or pass through a selection callback.
// - label (String): Wording identifying a field, choice, or action.
// - scale (double): Content text scale reflecting user accessibility settings.
class _SuccessMetric extends StatelessWidget {
  final String value;
  final String label;
  final double scale;

  // 함수이름: _SuccessMetric
  // 함수역할: 분석 성공 요약의 수치와 라벨에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _SuccessMetric 인스턴스.
  const _SuccessMetric({
    required this.value,
    required this.label,
    required this.scale,
  });

  // Function Name: build
  // Description: Renders a numeric metric and label in the analysis-success summary from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a numeric metric and label in the analysis-success summary.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 17),
      decoration: BoxDecoration(
        color: MedBuddyColors.successSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MedBuddyColors.primary,
              fontSize: 26 * scale,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 13 * scale,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _FailureReasonPanel
// 역할: 처방 분석 실패의 가능한 원인 목록을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 처방 분석 실패의 가능한 원인 목록 위젯을 구성한다.
// 속성:
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _FailureReasonPanel extends StatelessWidget {
  final _StatusText text;
  final double scale;

  // 함수이름: _FailureReasonPanel
  // 함수역할: 처방 분석 실패의 가능한 원인 목록에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_StatusText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _FailureReasonPanel 인스턴스.
  const _FailureReasonPanel({required this.text, required this.scale});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 처방 분석 실패의 가능한 원인 목록 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 처방 분석 실패의 가능한 원인 목록에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.failureReasons,
            style: TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 14 * scale,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 13),
          for (final reason in text.reasonItems) ...[
            _FailureReasonItem(reason: reason, scale: scale),
            if (reason != text.reasonItems.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

// 클래스명: _FailureReasonItem
// 역할: 분석 실패 원인 한 항목을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 분석 실패 원인 한 항목 위젯을 구성한다.
// 속성:
// - reason (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _FailureReasonItem extends StatelessWidget {
  final String reason;
  final double scale;

  // 함수이름: _FailureReasonItem
  // 함수역할: 분석 실패 원인 한 항목에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - reason (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _FailureReasonItem 인스턴스.
  const _FailureReasonItem({required this.reason, required this.scale});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 분석 실패 원인 한 항목 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 분석 실패 원인 한 항목에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '•',
          style: TextStyle(color: Color(0xFFFF1F2D), fontSize: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            reason,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 12 * scale,
              height: 1.35,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

// 클래스명: _StatusText
// 역할: 처방 분석 성공 요약과 실패 단계별 복구 동작에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 처방 분석 성공 요약과 실패 단계별 복구 동작에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _StatusText {
  final String language;

  // 함수이름: _StatusText
  // 함수역할: 처방 분석 성공 요약과 실패 단계별 복구 동작에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _StatusText 인스턴스.
  const _StatusText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드가 en과 정확히 일치하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language == 'en';

  // 함수이름: successTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "분석 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get successTitle => isEnglish ? 'Complete' : '분석 완료';
  // 함수이름: successMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전 분석이 완료되었습니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get successMessage =>
      isEnglish ? 'Prescription analysis is complete' : '처방전 분석이 완료되었습니다';
  // 함수이름: successDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "약물 정보와 복용 일정을\n확인하실 수 있습니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get successDescription => isEnglish
      ? 'You can review medication info\nand the medication schedule'
      : '약물 정보와 복용 일정을\n확인하실 수 있습니다';
  // 함수이름: recognizedMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "인식된 약물" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get recognizedMedication => isEnglish ? 'Medications' : '인식된 약물';
  // 함수이름: medicationPeriod
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 기간" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationPeriod => isEnglish ? 'Period' : '복용 기간';
  // 함수이름: checkResult
  // 함수역할: 현재 언어와 입력값에 맞춰 "결과 확인하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get checkResult => isEnglish ? 'View Results' : '결과 확인하기';
  // 함수이름: days
  // 함수역할: 현재 언어와 입력값에 맞춰 "$days일" 문구를 제공한다.
  // 매개변수:
  // - days (int): 복용 기간의 일수 또는 이를 표현한 원본 문구.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String days(int days) => isEnglish ? '${days}d' : '$days일';

  // 함수이름: failureTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "분석 실패" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get failureTitle => isEnglish ? 'Analysis Failed' : '분석 실패';
  // Function Name: failureMessage
  // Description: Provides localized wording for "Medication analysis failed" using the current language and message inputs.
  // Parameters:
  // - medicationAnalysisFailure (bool): Whether failure occurred during medication analysis after OCR.
  // Returns: The formatted display text or identifier described above.
  String failureMessage(bool medicationAnalysisFailure) {
    if (medicationAnalysisFailure) {
      return isEnglish ? 'Medication analysis failed' : '약물 정보 분석에 실패했습니다';
    }
    return isEnglish ? 'Prescription recognition failed' : '처방전 인식에 실패했습니다';
  }

  // Function Name: failureDescription
  // Description: Provides localized wording for "Please retry the recognized medication analysis" using the current language and message inputs.
  // Parameters:
  // - medicationAnalysisFailure (bool): Whether failure occurred during medication analysis after OCR.
  // Returns: The formatted display text or identifier described above.
  String failureDescription(bool medicationAnalysisFailure) {
    if (medicationAnalysisFailure) {
      return isEnglish
          ? 'Please retry the recognized medication analysis'
          : '인식된 약물 정보를 다시 분석해주세요';
    }
    return isEnglish
        ? 'Please retake the photo clearly'
        : '처방전이 잘 보이도록\n다시 촬영해주세요';
  }

  // 함수이름: failureReasons
  // 함수역할: 현재 언어와 입력값에 맞춰 "인식 실패 원인" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get failureReasons => isEnglish ? 'Possible reasons' : '인식 실패 원인';
  // 함수이름: reasonItems
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전이 흐릿하거나 가려진 경우" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: List<String>: 정리·선택된 표시 문구 또는 복약 시간대 키 목록.
  List<String> get reasonItems {
    if (isEnglish) {
      return const [
        'The prescription is blurry or covered',
        'Lighting is too dark or reflective',
        'The prescription is folded or damaged',
      ];
    }

    return const [
      '처방전이 흐릿하거나 가려진 경우',
      '조명이 어둡거나 반사가 심한 경우',
      '처방전이 구겨지거나 손상된 경우',
    ];
  }

  // 함수이름: analysisRetry
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 정보 조회만 다시 시도" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get analysisRetry =>
      isEnglish ? 'Retry medication lookup' : '약 정보 조회만 다시 시도';
  // 함수이름: ocrReview
  // 함수역할: 현재 언어와 입력값에 맞춰 "OCR 결과 다시 확인" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get ocrReview => isEnglish ? 'Review OCR results' : 'OCR 결과 다시 확인';
  // 함수이름: cameraRetry
  // 함수역할: 현재 언어와 입력값에 맞춰 "다른 사진 촬영하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get cameraRetry => isEnglish ? 'Retake Photo' : '다른 사진 촬영하기';
  // Function Name: galleryRetry
  // Description: Provides localized wording for "Choose Another Image" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get galleryRetry => isEnglish ? 'Choose Another Image' : '이미지 다시 선택하기';
  // 함수이름: home
  // 함수역할: 현재 언어와 입력값에 맞춰 "홈으로 돌아가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get home => isEnglish ? 'Back to Home' : '홈으로 돌아가기';
}
