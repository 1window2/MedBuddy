import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'medication_photo_source_sheet.dart';

import '../entities/user_setting_entity.dart';
import '../widgets/medbuddy_option_sheet.dart';

// 파일명: medication_capture_options_ui_boundary.dart
// 역할: 약 정보 분석 작업과 처방전 이미지 출처 선택을 제공한다.

// 클래스명: MedicationCaptureTask
// 역할: 처방전 분석·알약 식별·직접 입력 작업 구분을 담당한다.
// 주요 책임:
// - 처방전·한 장의 여러 알약·개별 알약·직접 입력을 구분한다.
enum MedicationCaptureTask {
  prescription,
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
// 함수역할: 처방전 분석, 낱알약 식별, 직접 등록 중 수행할 작업을 선택하는 공통 하단 시트를 표시한다.
// 매개변수:
// - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// 반환값: Future<MedicationCaptureTask?>: 선택한 분석·직접 입력 작업; 취소 시 null.
Future<MedicationCaptureTask?> showMedicationCaptureTaskOptions({
  required BuildContext context,
  required UserSetting userSetting,
}) {
  final text = _MedicationCaptureText(userSetting.language);
  var choosingPillMode = false;

  return showModalBottomSheet<MedicationCaptureTask>(
    context: context,
    isScrollControlled: true,
    // 함수이름: showMedicationCaptureTaskOptions.builder callback
    // 함수역할: 약 정보 분석 작업과 처방전 이미지 출처 선택에 SizedBox을 적용해 현재 배치를 구성한다.
    // 매개변수:
    // - sheetContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
    // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
    builder: (sheetContext) {
      return StatefulBuilder(
        // 함수역할: 같은 시트 안에서 작업 선택과 알약 촬영 방식 선택을 전환한다.
        // 매개변수: sheetContext, setSheetState. 반환값: 현재 단계의 선택지.
        builder: (sheetContext, setSheetState) => PopScope<MedicationCaptureTask>(
          canPop: !choosingPillMode,
          // 함수역할: 시스템 뒤로 가기도 시트를 닫기 전에 이전 단계로 이동한다.
          // 매개변수: didPop, result. 반환값: 없음.
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && choosingPillMode) {
              setSheetState(() => choosingPillMode = false);
            }
          },
          child: MedBuddyOptionSheet(
            key: ValueKey(choosingPillMode),
            children: [
              if (choosingPillMode) ...[
                Row(
                  children: [
                    IconButton(
                      key: const Key('pill-mode-back-button'),
                      tooltip: MaterialLocalizations.of(
                        sheetContext,
                      ).backButtonTooltip,
                      onPressed: () =>
                          setSheetState(() => choosingPillMode = false),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        text.pillTask,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                MedBuddyOptionTile(
                  icon: Icons.center_focus_strong_outlined,
                  title: text.isEnglish
                      ? 'Find pills in one photo'
                      : '여러 알약 한 번에 찾기',
                  subtitle: text.isEnglish
                      ? 'Compare pills placed together in one photo.'
                      : '한 사진 속 여러 알약을 구분해 후보를 확인해요.',
                  scale: 1,
                  onTap: () => Navigator.pop(
                    sheetContext,
                    MedicationCaptureTask.multiplePills,
                  ),
                ),
                const SizedBox(height: 10),
                MedBuddyOptionTile(
                  icon: Icons.medication_outlined,
                  title: text.isEnglish
                      ? 'Find pills individually'
                      : '알약 하나씩 찾기',
                  subtitle: text.isEnglish
                      ? 'Compare front and back photos of each pill.'
                      : '알약의 앞·뒷면을 촬영해 후보를 확인해요.',
                  scale: 1,
                  onTap: () => Navigator.pop(
                    sheetContext,
                    MedicationCaptureTask.individualPills,
                  ),
                ),
              ] else ...[
                MedBuddyOptionTile(
                  icon: Icons.photo_camera_outlined,
                  title: text.prescriptionTask,
                  subtitle: text.prescriptionTaskSubtitle,
                  scale: 1,
                  // 함수이름: showMedicationCaptureTaskOptions.onTap callback
                  // 함수역할: `Navigator.pop(sheetContext, MedicationCaptureTask.prescription)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                      MedicationCaptureTask.prescription,
                    );
                  },
                ),
                const SizedBox(height: 10),
                MedBuddyOptionTile(
                  icon: Icons.medication_outlined,
                  title: text.pillTask,
                  subtitle: text.pillTaskSubtitle,
                  scale: 1,
                  // 함수이름: showMedicationCaptureTaskOptions.onTap callback
                  // 함수역할: 시트를 겹치지 않고 알약 촬영 방식 두 가지를 표시한다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                  onTap: () {
                    setSheetState(() => choosingPillMode = true);
                  },
                ),
                const SizedBox(height: 10),
                MedBuddyOptionTile(
                  icon: Icons.edit_note_rounded,
                  title: text.manualTask,
                  subtitle: text.manualTaskSubtitle,
                  scale: 1,
                  // 함수이름: showMedicationCaptureTaskOptions.onTap callback
                  // 함수역할: `Navigator.pop(sheetContext, MedicationCaptureTask.manual)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                  onTap: () {
                    Navigator.pop(sheetContext, MedicationCaptureTask.manual);
                  },
                ),
              ],
            ],
          ),
        ),
      );
    },
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
      isEnglish ? 'Analyze a prescription' : '처방전 분석';
  // 함수이름: prescriptionTaskSubtitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전에서 약 이름과 복약 일정을 확인합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get prescriptionTaskSubtitle => isEnglish
      ? 'Extract medication names and schedules.'
      : '처방전에서 약 이름과 복약 일정을 확인합니다.';
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
