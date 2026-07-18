import 'package:flutter/material.dart';

import '../entities/analyzed_medication_entity.dart';
import '../entities/prescription_flow_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: prescription_analysis_status_ui_boundary.dart
// 역할: 처방전 분석 성공/실패 상태 화면을 구성한다.

// 클래스명: PrescriptionAnalysisSuccessUI
// 역할: 약품 상세 분석이 끝났음을 보여주고 결과 확인 화면으로 이동시킨다.
// 주요 책임:
// - 분석된 약 개수와 최대 복용 기간을 요약한다.
// - 사용자가 결과 목록 화면으로 이동할 수 있게 한다.
class PrescriptionAnalysisSuccessUI extends StatelessWidget {
  final List<AnalyzedMedication> analyzedMedicationList;
  final UserSetting userSetting;
  final VoidCallback onResultRequested;

  const PrescriptionAnalysisSuccessUI({
    super.key,
    required this.analyzedMedicationList,
    required this.userSetting,
    required this.onResultRequested,
  });

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

  int _readMaxMedicationDays() {
    return analyzedMedicationList.fold<int>(0, (maxValue, item) {
      final nextValue = item.schedule.medicationTime;
      return nextValue > maxValue ? nextValue : maxValue;
    });
  }
}

// 클래스명: PrescriptionAnalysisFailureUI
// 역할: 처방전 인식 또는 약품 정보 분석 실패 원인과 다음 행동을 안내한다.
// 주요 책임:
// - 실패 메시지를 화면에 표시한다.
// - 실패 단계에 맞는 재분석 또는 이미지 재선택 복구 동작을 제공한다.
class PrescriptionAnalysisFailureUI extends StatelessWidget {
  final String message;
  final UserSetting userSetting;
  final AnalysisProgressStep failureStep;
  final VoidCallback? onAnalysisRetryRequested;
  final VoidCallback onCameraRetryRequested;
  final VoidCallback onGalleryRetryRequested;
  final VoidCallback onHomeRequested;

  const PrescriptionAnalysisFailureUI({
    super.key,
    required this.message,
    required this.userSetting,
    required this.failureStep,
    this.onAnalysisRetryRequested,
    required this.onCameraRetryRequested,
    required this.onGalleryRetryRequested,
    required this.onHomeRequested,
  });

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
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Container(
                width: 328,
                padding: const EdgeInsets.fromLTRB(42, 44, 42, 42),
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
                    const SizedBox(height: 34),
                    Container(
                      width: 130,
                      height: 130,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF1F2D),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cancel_outlined,
                        color: Colors.white,
                        size: 72,
                      ),
                    ),
                    const SizedBox(height: 34),
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
                    SizedBox(
                      width: double.infinity,
                      height: 63,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
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
                        child: Text(text.home),
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

    return SizedBox(
      width: double.infinity,
      height: 63,
      child: isPrimary
          ? FilledButton.icon(
              key: key,
              style: FilledButton.styleFrom(
                backgroundColor: MedBuddyColors.primary,
                foregroundColor: Colors.white,
                shape: shape,
                textStyle: textStyle,
              ),
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            )
          : OutlinedButton.icon(
              key: key,
              style: OutlinedButton.styleFrom(
                foregroundColor: MedBuddyColors.primaryDark,
                side: const BorderSide(
                  color: MedBuddyColors.primary,
                  width: 1.5,
                ),
                shape: shape,
                textStyle: textStyle,
              ),
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }
}

class _SuccessMetric extends StatelessWidget {
  final String value;
  final String label;
  final double scale;

  const _SuccessMetric({
    required this.value,
    required this.label,
    required this.scale,
  });

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

class _FailureReasonPanel extends StatelessWidget {
  final _StatusText text;
  final double scale;

  const _FailureReasonPanel({
    required this.text,
    required this.scale,
  });

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

class _FailureReasonItem extends StatelessWidget {
  final String reason;
  final double scale;

  const _FailureReasonItem({
    required this.reason,
    required this.scale,
  });

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

class _StatusText {
  final String language;

  const _StatusText(this.language);

  bool get isEnglish => language == 'en';

  String get successTitle => isEnglish ? 'Complete' : '분석 완료';
  String get successMessage =>
      isEnglish ? 'Prescription analysis is complete' : '처방전 분석이 완료되었습니다';
  String get successDescription => isEnglish
      ? 'You can review medication info\nand the medication schedule'
      : '약물 정보와 복용 일정을\n확인하실 수 있습니다';
  String get recognizedMedication => isEnglish ? 'Medications' : '인식된 약물';
  String get medicationPeriod => isEnglish ? 'Period' : '복용 기간';
  String get checkResult => isEnglish ? 'View Results' : '결과 확인하기';
  String days(int days) => isEnglish ? '${days}d' : '$days일';

  String get failureTitle => isEnglish ? 'Analysis Failed' : '분석 실패';
  String failureMessage(bool medicationAnalysisFailure) {
    if (medicationAnalysisFailure) {
      return isEnglish ? 'Medication analysis failed' : '약물 정보 분석에 실패했습니다';
    }
    return isEnglish ? 'Prescription recognition failed' : '처방전 인식에 실패했습니다';
  }

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

  String get failureReasons => isEnglish ? 'Possible reasons' : '인식 실패 원인';
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

  String get analysisRetry => isEnglish ? 'Retry Analysis' : '분석 다시 시도하기';
  String get cameraRetry => isEnglish ? 'Retake Photo' : '다시 촬영하기';
  String get galleryRetry => isEnglish ? 'Choose Another Image' : '이미지 다시 선택하기';
  String get home => isEnglish ? 'Back to Home' : '홈으로 돌아가기';
}
