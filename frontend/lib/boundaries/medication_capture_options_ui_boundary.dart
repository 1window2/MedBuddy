import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'medication_photo_source_sheet.dart';

import '../entities/user_setting_entity.dart';
import '../widgets/medbuddy_page_header.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/keep_words_text.dart';

// 파일명: medication_capture_options_ui_boundary.dart
// 역할: 약 등록 화면(약봉투·처방전, 사진으로 복용 기록, 낱알약 식별, 직접 등록)과 사진 출처·촬영 방식 선택을 제공한다.

// 클래스명: MedicationCaptureTask
// 역할: 약 등록 화면에서 고르는 작업.
// 주요 책임: 낱알약 식별(한 장에 한 알 또는 여러 알)·직접 등록·사진으로 복용 기록을 구분한다.
// 속성: pills/manual/photoDose: 작업 값. 처방전 출처는 별도 열거형을 사용한다.
enum MedicationCaptureTask { pills, manual, photoDose }

// 클래스명: PillCaptureMode
// 역할: 알약 사진 입력 방식 구분.
// 주요 책임: 한 사진의 여러 알약과 알약별 앞뒷면 촬영 흐름을 구별한다.
// 속성: singlePhoto/individualPhotos: 입력 모드.
enum PillCaptureMode { singlePhoto, individualPhotos }

// 클래스명: PrescriptionImageSource
// 역할: 처방전 사진을 가져올 출처.
// 주요 책임: 가이드 카메라 촬영과 갤러리 선택 흐름을 구분한다.
// 속성: camera/gallery: 출처 값.
enum PrescriptionImageSource { camera, gallery }

// 함수이름: showMedicationCaptureTaskOptions
// 함수역할: 약봉투·처방전, (홈에서 열 때) 사진으로 복용 기록, 낱알약 식별, 직접 등록 중 하나를 고르는 약 등록 화면을 연다.
// 매개변수:
// - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
// - userSetting (UserSetting): 언어 설정.
// - onTaskSelected: 등록 화면을 유지한 채 고른 작업을 시작한다.
// - onSourceSelected: 등록 화면을 유지한 채 고른 사진 출처로 처방전 인식을 시작한다.
// - includePhotoDose (bool): 사진으로 복용 기록을 보일지. 약 관리·건강 관리 추천에서 열면 숨긴다.
// 반환값: 등록 화면이 닫히면 완료되는 Future<void>.
Future<void> showMedicationCaptureTaskOptions({
  required BuildContext context,
  required UserSetting userSetting,
  required Future<void> Function(BuildContext, MedicationCaptureTask)
  onTaskSelected,
  required Future<void> Function(BuildContext, PrescriptionImageSource)
  onSourceSelected,
  bool includePhotoDose = false,
}) {
  final text = _MedicationCaptureText(userSetting.language);
  var opening = false;
  // Function Name: open
  // Description: Serializes registration choices while a picker or destination is open and releases the lock even if the action fails.
  // Parameters: action (Future<void> Function()): selected workflow.
  // Returns: Future<void>; repeated requests are ignored and action failures propagate.
  Future<void> open(Future<void> Function() action) async {
    if (opening) return;
    opening = true;
    try {
      await action();
    } finally {
      opening = false;
    }
  }

  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (pageContext) => Scaffold(
        key: const Key('medication-registration-page'),
        backgroundColor: MedBuddyColors.pageBackground,
        body: Column(
          children: [
            MedBuddyPageHeader(
              title: text.isEnglish ? 'Add medication' : '약 등록',
              subtitle: includePhotoDose
                  ? (text.isEnglish
                        ? 'Add a medicine, or record a dose from a photo.'
                        : '약을 등록하거나 사진으로 복용을 기록해요.')
                  : (text.isEnglish
                        ? 'Choose how to add your medication.'
                        : '약을 등록할 방법을 고르세요.'),
              onBackRequested: () => Navigator.pop(pageContext),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MedicationTaskTile(
                        key: const ValueKey('registrationPrescriptionTile'),
                        icon: Icons.document_scanner_outlined,
                        title: text.prescriptionTask,
                        semanticsHint: text.prescriptionTaskSubtitle,
                        onTap: () => open(() async {
                          final source =
                              await showPrescriptionImageSourceOptions(
                                context: pageContext,
                                userSetting: userSetting,
                              );
                          if (!pageContext.mounted || source == null) return;
                          await onSourceSelected(pageContext, source);
                        }),
                      ),
                      if (includePhotoDose) ...[
                        const SizedBox(height: 12),
                        MedicationTaskTile(
                          key: const ValueKey('registrationPhotoDoseTile'),
                          icon: Icons.photo_camera_rounded,
                          badgeIcon: Icons.check_rounded,
                          title: text.photoDoseTask,
                          semanticsHint: text.photoDoseTaskSubtitle,
                          emphasized: true,
                          onTap: () => open(
                            () => onTaskSelected(
                              pageContext,
                              MedicationCaptureTask.photoDose,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      MedicationTaskTile(
                        key: const ValueKey('registrationPillTile'),
                        icon: Icons.image_search_outlined,
                        title: text.pillTask,
                        semanticsHint: text.pillTaskSubtitle,
                        onTap: () => open(
                          () => onTaskSelected(
                            pageContext,
                            MedicationCaptureTask.pills,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      MedicationTaskTile(
                        key: const ValueKey('registrationManualTile'),
                        icon: Icons.edit_note_rounded,
                        title: text.manualTask,
                        semanticsHint: text.manualTaskSubtitle,
                        onTap: () => open(
                          () => onTaskSelected(
                            pageContext,
                            MedicationCaptureTask.manual,
                          ),
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

// 클래스명: MedicationTaskTile
// 역할: 약 등록 화면의 큰 작업 버튼. 큰 아이콘과 이름만 보이고 설명은 화면 읽기용으로 둔다.
// 주요 책임: 기록 작업(사진으로 복용 기록)은 꽉 찬 초록, 등록 작업은 흰 바탕으로 구분한다.
// 속성: icon·badgeIcon: 아이콘과 작은 덧표시; title: 이름; semanticsHint: 설명; emphasized: 초록 채움; onTap: 동작.
class MedicationTaskTile extends StatelessWidget {
  final IconData icon;
  final IconData? badgeIcon;
  final String title;
  final String semanticsHint;
  final bool emphasized;
  final VoidCallback onTap;

  const MedicationTaskTile({
    super.key,
    required this.icon,
    required this.title,
    required this.semanticsHint,
    required this.onTap,
    this.badgeIcon,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = emphasized ? Colors.white : MedBuddyColors.textStrong;
    final accent = emphasized ? Colors.white : MedBuddyColors.primary;
    return Semantics(
      button: true,
      hint: semanticsHint,
      child: Material(
        color: emphasized ? MedBuddyColors.primary : MedBuddyColors.surface,
        borderRadius: MedBuddyRadii.largeCard,
        child: InkWell(
          onTap: onTap,
          borderRadius: MedBuddyRadii.largeCard,
          child: Container(
            constraints: const BoxConstraints(minHeight: 104),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: MedBuddyRadii.largeCard,
              border: Border.all(
                color: emphasized
                    ? MedBuddyColors.primary
                    : MedBuddyColors.cardBorder,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: emphasized
                              ? Colors.white.withValues(alpha: 0.18)
                              : MedBuddyColors.successSurface,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Icon(icon, color: accent, size: 44),
                      ),
                      if (badgeIcon != null)
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: emphasized
                                  ? Colors.white
                                  : MedBuddyColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              badgeIcon,
                              size: 21,
                              color: emphasized
                                  ? MedBuddyColors.primary
                                  : Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: KeepWordsText(
                    title,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: accent, size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 함수이름: showPrescriptionImageSourceOptions
// 함수역할: 공통 사진 출처 선택을 처방전 인식용 출처로 바꾼다.
// 매개변수:
// - context (BuildContext): 시트를 열 위치.
// - userSetting (UserSetting): 언어 설정.
// 반환값: 고른 출처. 닫으면 null.
Future<PrescriptionImageSource?> showPrescriptionImageSourceOptions({
  required BuildContext context,
  required UserSetting userSetting,
}) async {
  final source = await showMedicationPhotoSourceOptions(
    context: context,
    language: userSetting.language,
  );
  return switch (source) {
    ImageSource.camera => PrescriptionImageSource.camera,
    ImageSource.gallery => PrescriptionImageSource.gallery,
    null => null,
  };
}

// 클래스명: _MedicationCaptureText
// 역할: 약 등록 화면의 한국어·영어 문구.
// 속성: language (String): 표시 언어 코드.
class _MedicationCaptureText {
  final String language;

  const _MedicationCaptureText(this.language);

  // Function Name: isEnglish
  // Description: Uses the shared English-language rule for medication-input choices.
  // Parameters: None.
  // Returns: True for an English language code.
  bool get isEnglish => isEnglishLanguage(language);

  // 함수이름: prescriptionTask
  // 함수역할: "약봉투·처방전 등록" 문구를 제공한다. 매개변수: 없음. 반환값: 문구.
  String get prescriptionTask =>
      isEnglish ? 'Prescription or medication envelope' : '약봉투·처방전 등록';
  // 함수이름: prescriptionTaskSubtitle
  // 함수역할: 화면 읽기용 설명. 매개변수: 없음. 반환값: 문구.
  String get prescriptionTaskSubtitle => isEnglish
      ? 'Review medication names and schedules printed on your document.'
      : '약 이름과 복용 일정이 적힌 내용을 사진으로 확인합니다.';
  // 함수이름: photoDoseTask
  // 함수역할: "사진으로 복용 기록" 문구를 제공한다. 매개변수: 없음. 반환값: 문구.
  String get photoDoseTask =>
      isEnglish ? 'Record a dose from a photo' : '사진으로 복용 기록';
  // 함수이름: photoDoseTaskSubtitle
  // 함수역할: 화면 읽기용 설명. 매개변수: 없음. 반환값: 문구.
  String get photoDoseTaskSubtitle => isEnglish
      ? 'Photograph the pills in your hand before taking them to record the dose.'
      : '먹기 전에 손에 든 약을 찍으면 복용을 기록합니다.';
  // 함수이름: pillTask
  // 함수역할: "낱알약 식별" 문구를 제공한다. 매개변수: 없음. 반환값: 문구.
  String get pillTask => isEnglish ? 'Identify a loose pill' : '낱알약 식별';
  // 함수이름: pillTaskSubtitle
  // 함수역할: 화면 읽기용 설명. 매개변수: 없음. 반환값: 문구.
  String get pillTaskSubtitle => isEnglish
      ? 'Compare one or more photographed pills with MFDS product candidates.'
      : '알약을 한 개 또는 여러 개 촬영해 식약처 제품 후보와 비교합니다.';
  // 함수이름: manualTask
  // 함수역할: "직접 등록" 문구를 제공한다. 매개변수: 없음. 반환값: 문구.
  String get manualTask => isEnglish ? 'Add manually' : '직접 등록';
  // 함수이름: manualTaskSubtitle
  // 함수역할: 화면 읽기용 설명. 매개변수: 없음. 반환값: 문구.
  String get manualTaskSubtitle => isEnglish
      ? 'Enter a medication name and schedule without a photo.'
      : '사진이 없어도 약 이름과 복용 일정을 직접 입력합니다.';
}
