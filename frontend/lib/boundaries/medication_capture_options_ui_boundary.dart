import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'medication_photo_source_sheet.dart';

import '../entities/user_setting_entity.dart';
import '../widgets/medbuddy_option_sheet.dart';
import '../widgets/medbuddy_page_header.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: medication_capture_options_ui_boundary.dart
// 역할: 약 정보 분석 작업과 처방전 이미지 출처 선택을 제공한다.

// 클래스명: MedicationCaptureTask
// 역할: 처방전 분석·알약 식별·직접 입력 작업 구분을 담당한다.
// 주요 책임:
// - 처방전·한 장의 여러 알약·개별 알약·직접 입력을 구분한다.
enum MedicationCaptureTask {
  multiplePills,
  individualPills,
  manual,
}

// 열거형명: PillCaptureMode
// 역할: 알약 화면에서 한 장의 여러 알약과 알약별 앞뒷면 입력 방식을 구분한다.
enum PillCaptureMode { singlePhoto, individualPhotos }

// 클래스명: PrescriptionImageSource
// 역할: 처방전의 카메라·갤러리 입력 출처를 담당한다.
// 주요 책임:
// - 처방전의 카메라·갤러리 입력 출처에서 지원하는 선택지를 열거하고 구분한다: camera, gallery.
enum PrescriptionImageSource { camera, gallery }

// 함수이름: showMedicationCaptureTaskOptions
// 함수역할: 약봉투·처방전, 낱알약 식별, 직접 등록 중 하나를 고르는 약 등록 화면을 연다.
// 매개변수:
// - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - onTaskSelected: 등록 화면을 유지한 채 고른 낱알약·직접 등록 작업을 시작한다.
// - onSourceSelected: 등록 화면을 유지한 채 고른 사진 출처로 처방전 인식을 시작한다.
// 반환값: 등록 화면이 닫히면 완료되는 Future<void>.
Future<void> showMedicationCaptureTaskOptions({
  required BuildContext context,
  required UserSetting userSetting,
  required Future<void> Function(BuildContext, MedicationCaptureTask)
  onTaskSelected,
  required Future<void> Function(BuildContext, PrescriptionImageSource)
  onSourceSelected,
}) {
  final text = _MedicationCaptureText(userSetting.language);
  var opening = false;
  // 선택 창이나 다음 화면을 여는 동안 다른 항목을 함께 열지 않는다.
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
        body: Column(
          children: [
            MedBuddyPageHeader(
              title: text.isEnglish ? 'Add medication' : '약 등록',
              subtitle: text.isEnglish
                  ? 'Choose how to add your medication.'
                  : '약을 등록할 방법을 선택합니다.',
              onBackRequested: () => Navigator.pop(pageContext),
            ),
            Expanded(
              child: MedBuddyOptionSheet(
                showHandle: false,
                children: [
                  MedBuddyOptionTile(
                    icon: Icons.document_scanner_outlined,
                    title: text.prescriptionTask,
                    subtitle: text.prescriptionTaskSubtitle,
                    onTap: () => open(() async {
                      final source = await showPrescriptionImageSourceOptions(
                        context: pageContext,
                        userSetting: userSetting,
                      );
                      if (!pageContext.mounted || source == null) return;
                      await onSourceSelected(pageContext, source);
                    }),
                  ),
                  const SizedBox(height: 10),
                  MedBuddyOptionTile(
                    icon: Icons.image_search_outlined,
                    title: text.pillTask,
                    subtitle: text.pillTaskSubtitle,
                    onTap: () => open(() async {
                      final task = await showPillCaptureModeOptions(
                        pageContext,
                        text.isEnglish,
                      );
                      if (!pageContext.mounted || task == null) return;
                      await onTaskSelected(pageContext, task);
                    }),
                  ),
                  const SizedBox(height: 10),
                  MedBuddyOptionTile(
                    icon: Icons.add_circle_outline,
                    title: text.manualTask,
                    subtitle: text.manualTaskSubtitle,
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
          ],
        ),
      ),
    ),
  );
}

Future<MedicationCaptureTask?> showPillCaptureModeOptions(
  BuildContext context,
  bool isEnglish,
) {
  var selected = false;
  return showModalBottomSheet<MedicationCaptureTask>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MedBuddyColors.surface,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (task, icon, label) in [
              (
                MedicationCaptureTask.multiplePills,
                Icons.center_focus_strong_outlined,
                isEnglish ? 'Find pills in one photo' : '여러 알약 한 번에 찾기',
              ),
              (
                MedicationCaptureTask.individualPills,
                Icons.medication_outlined,
                isEnglish ? 'Find pills individually' : '알약 하나씩 찾기',
              ),
            ]) ...[
              ListTile(
                minTileHeight: 56,
                leading: Icon(icon, color: MedBuddyColors.primaryDark),
                title: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    letterSpacing: 0,
                  ),
                ),
                onTap: () {
                  if (selected ||
                      ModalRoute.of(sheetContext)?.isCurrent != true) {
                    return;
                  }
                  selected = true;
                  Navigator.pop(sheetContext, task);
                },
              ),
              if (task == MedicationCaptureTask.multiplePills)
                const Divider(height: 1, color: MedBuddyColors.divider),
            ],
          ],
        ),
      ),
    ),
  );
}

// 함수이름: showPrescriptionImageSourceOptions
// 함수역할: 처방전 분석에 사용할 카메라 또는 갤러리 이미지 출처를 선택하게 한다.
// 매개변수:
// - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// 반환값: Future<PrescriptionImageSource?>: 선택한 카메라·갤러리 출처; 취소 시 null.
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
// 역할: 약 정보 분석 작업과 처방전 이미지 출처 선택에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 약 정보 분석 작업과 처방전 이미지 출처 선택에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _MedicationCaptureText {
  final String language;

  // 함수이름: _MedicationCaptureText
  // 함수역할: 약 정보 분석 작업과 처방전 이미지 출처 선택에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _MedicationCaptureText 인스턴스.
  const _MedicationCaptureText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 공통 언어 판정으로 언어 코드가 영어인지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => isEnglishLanguage(language);

  // 함수이름: prescriptionTask
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전 분석" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get prescriptionTask =>
      isEnglish ? 'Prescription or medication envelope' : '약봉투·처방전 등록';
  // 함수이름: prescriptionTaskSubtitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전에서 약 이름과 복약 일정을 확인합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get prescriptionTaskSubtitle => isEnglish
      ? 'Review medication names and schedules printed on your document.'
      : '약 이름과 복용 일정이 적힌 내용을 사진으로 확인합니다.';
  // 함수이름: pillTask
  // 함수역할: 현재 언어와 입력값에 맞춰 "낱알약 식별" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get pillTask => isEnglish ? 'Identify a loose pill' : '낱알약 식별';
  // 함수이름: pillTaskSubtitle
  // 함수역할: 한 알 또는 여러 알약의 후보를 비교하는 기본 식별 기능을 안내한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get pillTaskSubtitle => isEnglish
      ? 'Compare one or more photographed pills with MFDS product candidates.'
      : '알약을 한 개 또는 여러 개 촬영해 식약처 제품 후보와 비교합니다.';

  // 함수이름: manualTask
  // 함수역할: 현재 언어와 입력값에 맞춰 "직접 등록" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get manualTask => isEnglish ? 'Add manually' : '직접 등록';
  // 함수이름: manualTaskSubtitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "사진이 없어도 약 이름과 복용 일정을 직접 입력합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get manualTaskSubtitle => isEnglish
      ? 'Enter a medication name and schedule without a photo.'
      : '사진이 없어도 약 이름과 복용 일정을 직접 입력합니다.';
}
