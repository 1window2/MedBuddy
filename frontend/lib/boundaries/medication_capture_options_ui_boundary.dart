import 'package:flutter/material.dart';

import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: medication_capture_options_ui_boundary.dart
// 역할: 약 정보 분석 작업과 처방전 이미지 출처 선택을 제공한다.

// 클래스명: MedicationCaptureTask
// 역할: 처방전 분석·알약 식별·직접 입력 작업 구분을 담당한다.
// 주요 책임:
// - 처방전 분석·알약 식별·직접 입력 작업 구분에서 지원하는 선택지를 열거하고 구분한다: prescription, pill, manual.
enum MedicationCaptureTask { prescription, pill, manual }

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
  final text = _MedicationCaptureText(
    userSetting.language,
    multiPillIdentificationEnabled:
        userSetting.multiPillIdentificationLabEnabled,
  );

  return showModalBottomSheet<MedicationCaptureTask>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    // 함수이름: showMedicationCaptureTaskOptions.builder callback
    // 함수역할: 약 정보 분석 작업과 처방전 이미지 출처 선택에 SizedBox을 적용해 현재 배치를 구성한다.
    // 매개변수:
    // - sheetContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
    // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
    builder: (sheetContext) {
      return _MedicationCaptureOptionSheet(
        children: [
          _MedicationCaptureOption(
            icon: Icons.photo_camera_outlined,
            title: text.prescriptionTask,
            subtitle: text.prescriptionTaskSubtitle,
            userSetting: userSetting,
            // 함수이름: showMedicationCaptureTaskOptions.onTap callback
            // 함수역할: `Navigator.pop(sheetContext, MedicationCaptureTask.prescription)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onTap: () {
              Navigator.pop(sheetContext, MedicationCaptureTask.prescription);
            },
          ),
          const SizedBox(height: 10),
          _MedicationCaptureOption(
            icon: Icons.medication_outlined,
            title: text.pillTask,
            subtitle: text.pillTaskSubtitle,
            userSetting: userSetting,
            // 함수이름: showMedicationCaptureTaskOptions.onTap callback
            // 함수역할: `Navigator.pop(sheetContext, MedicationCaptureTask.pill)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onTap: () {
              Navigator.pop(sheetContext, MedicationCaptureTask.pill);
            },
          ),
          const SizedBox(height: 10),
          _MedicationCaptureOption(
            icon: Icons.edit_note_rounded,
            title: text.manualTask,
            subtitle: text.manualTaskSubtitle,
            userSetting: userSetting,
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
}) {
  final text = _MedicationCaptureText(
    userSetting.language,
    multiPillIdentificationEnabled:
        userSetting.multiPillIdentificationLabEnabled,
  );

  return showModalBottomSheet<PrescriptionImageSource>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    // 함수이름: showPrescriptionImageSourceOptions.builder callback
    // 함수역할: 약 정보 분석 작업과 처방전 이미지 출처 선택에 SizedBox을 적용해 현재 배치를 구성한다.
    // 매개변수:
    // - sheetContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
    // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
    builder: (sheetContext) {
      return _MedicationCaptureOptionSheet(
        children: [
          _MedicationCaptureOption(
            icon: Icons.photo_camera_outlined,
            title: text.cameraOption,
            subtitle: text.cameraOptionSubtitle,
            userSetting: userSetting,
            // 함수이름: showPrescriptionImageSourceOptions.onTap callback
            // 함수역할: `Navigator.pop(sheetContext, PrescriptionImageSource.camera)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onTap: () {
              Navigator.pop(sheetContext, PrescriptionImageSource.camera);
            },
          ),
          const SizedBox(height: 10),
          _MedicationCaptureOption(
            icon: Icons.photo_library_outlined,
            title: text.galleryOption,
            subtitle: text.galleryOptionSubtitle,
            userSetting: userSetting,
            // 함수이름: showPrescriptionImageSourceOptions.onTap callback
            // 함수역할: `Navigator.pop(sheetContext, PrescriptionImageSource.gallery)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onTap: () {
              Navigator.pop(sheetContext, PrescriptionImageSource.gallery);
            },
          ),
        ],
      );
    },
  );
}

// 클래스명: _MedicationCaptureOptionSheet
// 역할: 큰 글씨에서도 스크롤 가능한 입력 선택 시트를 담당한다.
// 주요 책임:
// - 공통 상단 핸들과 선택지 여백을 제공한다.
// - 큰 글자 설정에서도 선택지가 화면 아래로 넘치지 않게 한다.
// 속성:
// - children (List<Widget>): 순서대로 배치할 콘텐츠 위젯 목록.
class _MedicationCaptureOptionSheet extends StatelessWidget {
  final List<Widget> children;

  // 함수이름: _MedicationCaptureOptionSheet
  // 함수역할: 큰 글씨에서도 스크롤 가능한 입력 선택 시트에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - children (List<Widget>): 순서대로 배치할 콘텐츠 위젯 목록.
  // 반환값: 입력 설정이 반영된 _MedicationCaptureOptionSheet 인스턴스.
  const _MedicationCaptureOptionSheet({required this.children});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 큰 글씨에서도 스크롤 가능한 입력 선택 시트 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 큰 글씨에서도 스크롤 가능한 입력 선택 시트에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: MedBuddyColors.outline,
                borderRadius: MedBuddyRadii.pill,
              ),
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}

// 클래스명: _MedicationCaptureOption
// 역할: 분석 작업 또는 사진 출처의 선택 행을 담당한다.
// 주요 책임:
// - 아이콘, 제목, 설명을 사용자 글자 크기에 맞춰 표시한다.
// - 선택 시 호출자가 전달한 동작을 실행한다.
// 속성:
// - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
// - title (String): 화면·구역·항목에 표시할 제목.
// - subtitle (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
class _MedicationCaptureOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final UserSetting userSetting;
  final VoidCallback onTap;

  // 함수이름: _MedicationCaptureOption
  // 함수역할: 분석 작업 또는 사진 출처의 선택 행에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - subtitle (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - onTap (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _MedicationCaptureOption 인스턴스.
  const _MedicationCaptureOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.userSetting,
    required this.onTap,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 분석 작업 또는 사진 출처의 선택 행 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 분석 작업 또는 사진 출처의 선택 행에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Material(
      color: const Color(0xFFF4FFF4),
      borderRadius: MedBuddyRadii.card,
      child: InkWell(
        borderRadius: MedBuddyRadii.card,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: Border.all(color: MedBuddyColors.mint, width: 1.6),
          ),
          child: Row(
            children: [
              Icon(icon, color: MedBuddyColors.primary, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 17 * scale,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 13 * scale,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: MedBuddyColors.primary,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 클래스명: _MedicationCaptureText
// 역할: 약 정보 분석 작업과 처방전 이미지 출처 선택에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 약 정보 분석 작업과 처방전 이미지 출처 선택에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
// - multiPillIdentificationEnabled (bool): 여러 알약 사진 식별을 사용할지 여부.
class _MedicationCaptureText {
  final String language;
  final bool multiPillIdentificationEnabled;

  // 함수이름: _MedicationCaptureText
  // 함수역할: 약 정보 분석 작업과 처방전 이미지 출처 선택에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // - multiPillIdentificationEnabled (bool): 여러 알약 사진 식별을 사용할지 여부.
  // 반환값: 입력 설정이 반영된 _MedicationCaptureText 인스턴스.
  const _MedicationCaptureText(
    this.language, {
    required this.multiPillIdentificationEnabled,
  });

  // 함수이름: isEnglish
  // 함수역할: 언어 코드가 en과 정확히 일치하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language == 'en';

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
  // 함수역할: 현재 언어와 입력값에 맞춰 "한 알을 식별하거나 알약별 사진을 추가해 실험실 일괄 검토를 합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get pillTaskSubtitle {
    if (multiPillIdentificationEnabled) {
      return isEnglish
          ? 'Identify one pill or add separate photos for a Labs batch review.'
          : '한 알을 식별하거나 알약별 사진을 추가해 실험실 일괄 검토를 합니다.';
    }
    return isEnglish
        ? 'Compare a photographed pill with MFDS candidates.'
        : '촬영한 알약 한 개를 식약처 제품 후보와 비교합니다.';
  }

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
  // 함수이름: cameraOption
  // 함수역할: 현재 언어와 입력값에 맞춰 "카메라로 촬영" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get cameraOption => isEnglish ? 'Take Photo' : '카메라로 촬영';
  // 함수이름: cameraOptionSubtitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전을 바로 촬영합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get cameraOptionSubtitle =>
      isEnglish ? 'Take a prescription photo now.' : '처방전을 바로 촬영합니다.';
  // 함수이름: galleryOption
  // 함수역할: 현재 언어와 입력값에 맞춰 "갤러리에서 선택" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get galleryOption => isEnglish ? 'Choose From Gallery' : '갤러리에서 선택';
  // 함수이름: galleryOptionSubtitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장된 처방전 이미지를 불러옵니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get galleryOptionSubtitle =>
      isEnglish ? 'Load a saved prescription image.' : '저장된 처방전 이미지를 불러옵니다.';
}
