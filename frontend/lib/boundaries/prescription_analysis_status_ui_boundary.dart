import 'package:flutter/material.dart';

import '../entities/prescription_flow_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: prescription_analysis_status_ui_boundary.dart
// 역할: 처방 분석 실패 단계별 복구 동작을 제공한다.

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
    final isMedicationAnalysisFailure =
        failureStep != AnalysisProgressStep.prescriptionRecognition;
    final canRetryAnalysis = onAnalysisRetryRequested != null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          color: MedBuddyColors.pageBackground,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Center(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: MedBuddyRadii.card,
                  boxShadow: MedBuddyShadows.card,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      text.failureTitle,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        color: MedBuddyColors.danger,
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
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
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
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    if (!isMedicationAnalysisFailure) ...[
                      const SizedBox(height: 28),
                      _FailureReasonPanel(text: text),
                    ],
                    const SizedBox(height: 28),
                    if (onAnalysisRetryRequested case final retryCallback?) ...[
                      _buildActionButton(
                        key: const Key('prescription-analysis-retry-button'),
                        isPrimary: true,
                        onPressed: retryCallback,
                        icon: Icons.refresh,
                        label: text.analysisRetry,
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
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildActionButton(
                      key: const Key('prescription-camera-retry-button'),
                      isPrimary: !canRetryAnalysis,
                      onPressed: onCameraRetryRequested,
                      icon: Icons.photo_camera_outlined,
                      label: text.cameraRetry,
                    ),
                    const SizedBox(height: 12),
                    _buildActionButton(
                      key: const Key('prescription-gallery-retry-button'),
                      isPrimary: false,
                      onPressed: onGalleryRetryRequested,
                      icon: Icons.photo_library_outlined,
                      label: text.galleryRetry,
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
                          textStyle: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
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

  // Function Name: _buildActionButton
  // Description: Keeps recovery-action labels complete at large text sizes by reducing spacing and allowing additional button height.
  // Parameters: key: button identity; isPrimary: emphasis; onPressed: recovery action; icon: command symbol; label: full command text.
  // Returns: A recovery button retaining its minimum touch height.
  Widget _buildActionButton({
    required Key key,
    required bool isPrimary,
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) {
    final shape = RoundedRectangleBorder(borderRadius: MedBuddyRadii.card);
    final textStyle = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
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

// Class Name: _FailureReasonPanel
// Role: Possible prescription-analysis failure causes.
// Responsibilities: Presents localized reasons that can guide another capture attempt.
// Attributes: text (_StatusText): failure-reason copy.
class _FailureReasonPanel extends StatelessWidget {
  final _StatusText text;

  // Function Name: _FailureReasonPanel
  // Description: Supplies the localized set of possible failure reasons.
  // Parameters: text (_StatusText): failure guidance.
  // Returns: A _FailureReasonPanel.
  const _FailureReasonPanel({required this.text});

  // Function Name: build
  // Description: Lists possible causes of prescription-analysis failure.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: MedBuddyColors.dangerSurface,
        borderRadius: MedBuddyRadii.control,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.failureReasons,
            style: TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 13),
          for (final reason in text.reasonItems) ...[
            _FailureReasonItem(reason: reason),
            if (reason != text.reasonItems.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

// Class Name: _FailureReasonItem
// Role: One possible analysis-failure reason.
// Responsibilities: Displays a readable reason within the recovery guidance list.
// Attributes: reason (String): cause to explain.
class _FailureReasonItem extends StatelessWidget {
  final String reason;

  // Function Name: _FailureReasonItem
  // Description: Stores one possible reason for failed analysis.
  // Parameters: reason (String): failure cause.
  // Returns: A _FailureReasonItem.
  const _FailureReasonItem({required this.reason});

  // Function Name: build
  // Description: Displays one failure reason as a guidance-list item.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '•',
          style: TextStyle(color: MedBuddyColors.danger, fontSize: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            reason,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 12,
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
// 역할: 처방 분석 실패 단계별 복구 동작에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 처방 분석 실패 단계별 복구 동작에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _StatusText {
  final String language;

  // 함수이름: _StatusText
  // 함수역할: 처방 분석 실패 단계별 복구 동작에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _StatusText 인스턴스.
  const _StatusText(this.language);

  // Function Name: isEnglish
  // Description: Uses the shared English-language rule for analysis status and recovery copy.
  // Parameters: None.
  // Returns: True for an English language code.
  bool get isEnglish => isEnglishLanguage(language);

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
